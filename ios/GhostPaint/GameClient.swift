// GhostPaint · WebSocket client + cloud URL bootstrap
// ObservableObject that the whole UI reads from.
//
// Architecture (v0.3 · cloud):
//   1. fetchCurrentURL() hits raw.githubusercontent.com/.../server/current-url.txt
//      to get the Lightning Studio tunnel URL (which rotates).
//   2. Converts https://… → wss://…/ws?role=player and opens the WebSocket.
//   3. Sends create_room or join_room with name + optional code.
//   4. Handles room_joined, state, and gameplay messages as before.

import Foundation
import SwiftUI

@MainActor
final class GameClient: NSObject, ObservableObject, URLSessionWebSocketDelegate {

    // ─── public state ───────────────────────────────────────
    @Published var phase: ClientPhase = .disconnected
    @Published var serverURL: URL? = nil              // resolved wss:// URL
    @Published var me: Player? = nil
    @Published var state: PublicState? = nil
    @Published var roomCode: String? = nil
    @Published var isHost: Bool = false
    @Published var killFeedTicker: [KillEntry] = []
    @Published var lastDamageAt: Date? = nil
    @Published var iJustHit: Bool = false
    @Published var iJustKilled: Bool = false
    @Published var errorText: String? = nil
    @Published var statusText: String? = nil          // "Waking server…", etc.
    @Published var debugLog: [String] = []
    @Published var rawLastMessage: String = ""

    // ─── debug helper ───────────────────────────────────────
    private func debug(_ line: String) {
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        debugLog.append("\(stamp) \(line)")
        if debugLog.count > 30 { debugLog.removeFirst(debugLog.count - 30) }
        print("[GAMECLIENT] \(line)")
    }

    // ─── URL bootstrap source (stable, never changes) ───────
    private let bootstrapURL = URL(string:
        "https://raw.githubusercontent.com/navneet07/AR-PainBall/main/server/current-url.txt"
    )!

    // ─── reconnect / resume bookkeeping ─────────────────────
    private enum PendingAction {
        case none
        case host(name: String)
        case join(code: String, name: String)
    }
    private var pendingAction: PendingAction = .none
    private var task: URLSessionWebSocketTask? = nil
    private var reconnectWorkItem: DispatchWorkItem? = nil
    private var cachedOrigin: URL? = nil              // https://xxx.trycloudflare.com

    // ─── public entry points ────────────────────────────────

    /// Host a new room. Server will reply with a 6-digit code.
    func host(name: String) {
        pendingAction = .host(name: name)
        startConnectFlow()
    }

    /// Join an existing room by code.
    func join(code: String, name: String) {
        pendingAction = .join(code: code, name: name)
        startConnectFlow()
    }

    /// Cancel everything and go back to disconnected.
    func leave() {
        send(.leave)
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        pendingAction = .none
        phase = .disconnected
        me = nil
        state = nil
        roomCode = nil
        isHost = false
        errorText = nil
        statusText = nil
    }

    // ─── connect flow ───────────────────────────────────────
    private func startConnectFlow() {
        errorText = nil
        phase = .connecting
        statusText = "Resolving server…"
        Task { await self.connectFlow(forceRefresh: false) }
    }

    private func connectFlow(forceRefresh: Bool) async {
        // 1. Get origin URL (cached if we already have one)
        let origin: URL
        if let cached = cachedOrigin, !forceRefresh {
            origin = cached
        } else {
            statusText = "Resolving server…"
            guard let fetched = await fetchCurrentURL() else {
                phase = .disconnected
                errorText = "Can't reach the bootstrap URL. Check your connection."
                statusText = nil
                return
            }
            cachedOrigin = fetched
            origin = fetched
            debug("bootstrap origin: \(origin.absoluteString)")
        }

        // 2. Build wss URL
        guard let wsURL = makeWebSocketURL(origin: origin) else {
            phase = .disconnected
            errorText = "Bad server URL: \(origin.absoluteString)"
            statusText = nil
            return
        }
        serverURL = wsURL
        statusText = "Waking server…"

        // 3. Open socket
        openSocket(url: wsURL)
    }

    /// Fetches the current tunnel URL from GitHub raw. ~1s.
    private func fetchCurrentURL() async -> URL? {
        var req = URLRequest(url: bootstrapURL)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 10
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let trimmed = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard let url = URL(string: trimmed), trimmed.hasPrefix("http") else {
                debug("fetch URL: malformed contents: \(trimmed.prefix(80))")
                return nil
            }
            return url
        } catch {
            debug("fetch URL failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Converts `https://xxx.trycloudflare.com` → `wss://xxx.trycloudflare.com/ws?role=player`.
    private func makeWebSocketURL(origin: URL) -> URL? {
        guard var comps = URLComponents(url: origin, resolvingAgainstBaseURL: false) else { return nil }
        switch comps.scheme {
        case "https":  comps.scheme = "wss"
        case "http":   comps.scheme = "ws"
        default:       comps.scheme = "wss"
        }
        comps.path = "/ws"
        comps.query = "role=player"
        return comps.url
    }

    private func openSocket(url: URL) {
        task?.cancel(with: .goingAway, reason: nil)
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        let t = session.webSocketTask(with: url)
        t.resume()
        self.task = t
        receiveLoop()
    }

    // ─── URLSessionWebSocketDelegate ────────────────────────
    nonisolated func urlSession(_ session: URLSession,
                                webSocketTask: URLSessionWebSocketTask,
                                didOpenWithProtocol protocolName: String?) {
        Task { @MainActor in
            self.debug("WS OPEN")
            self.statusText = nil
            self.sendPendingAction()
        }
    }

    nonisolated func urlSession(_ session: URLSession,
                                webSocketTask: URLSessionWebSocketTask,
                                didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                                reason: Data?) {
        Task { @MainActor in
            self.debug("WS CLOSE code=\(closeCode.rawValue)")
            self.phase = .disconnected
            self.errorText = "Connection closed (code \(closeCode.rawValue))"
            self.scheduleReconnect()
        }
    }

    /// Replay the queued action once the socket is open.
    private func sendPendingAction() {
        switch pendingAction {
        case .host(let name):
            phase = .joining
            debug("→ create_room name=\(name)")
            send(.createRoom(name: name))
        case .join(let code, let name):
            phase = .joining
            debug("→ join_room code=\(code) name=\(name)")
            send(.joinRoom(code: code, name: name))
        case .none:
            break
        }
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self = self else { return }
            Task { @MainActor in
                switch result {
                case .failure(let err):
                    self.debug("RX error: \(err.localizedDescription)")
                    self.phase = .disconnected
                    self.errorText = err.localizedDescription
                    self.scheduleReconnect()
                case .success(let msg):
                    if case let .string(text) = msg {
                        self.rawLastMessage = text
                        if let data = text.data(using: .utf8) {
                            self.dispatch(data: data)
                        }
                    } else if case .data = msg {
                        self.debug("RX binary ignored")
                    }
                    self.receiveLoop()
                }
            }
        }
    }

    private func scheduleReconnect() {
        if case .none = pendingAction { return }
        reconnectWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.phase = .connecting
            // On reconnect, re-fetch URL in case the tunnel rotated while we were down.
            Task { await self.connectFlow(forceRefresh: true) }
        }
        reconnectWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: item)
    }

    // ─── dispatch ───────────────────────────────────────────
    private func dispatch(data: Data) {
        let decoder = JSONDecoder()
        let msg: ServerMessage
        do {
            msg = try decoder.decode(ServerMessage.self, from: data)
        } catch {
            let preview = String(data: data, encoding: .utf8)?.prefix(80) ?? ""
            debug("DECODE FAIL: \(error.localizedDescription) · \(preview)")
            return
        }
        switch msg {
        case .roomJoined(let room, let you):
            self.me = you
            self.roomCode = room.code
            self.isHost = room.isHost
            self.phase = .inLobby
            self.statusText = nil
            debug("ROOM_JOINED code=\(room.code) host=\(room.isHost) as \(you.name)/\(you.bibId)")

        case .state(let s, let roomCode):
            self.state = s
            if let rc = roomCode, self.roomCode == nil { self.roomCode = rc }
            let prev = self.phase
            switch s.phase {
            case "lobby":     if self.me != nil { self.phase = .inLobby }
            case "countdown": self.phase = .countdown
            case "playing":   self.phase = .playing
            case "ended":     self.phase = .ended
            default: break
            }
            if prev != self.phase {
                debug("STATE phase: \(prev) → \(self.phase) (server=\(s.phase))")
            }

        case .gameStart:
            debug("GAME_START → .playing")
            self.phase = .playing

        case .hit(let shooterId, _, _, _):
            if shooterId == me?.id {
                self.iJustHit = true
                Haptics.medium()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.iJustHit = false }
            }

        case .damage(_, _, _):
            self.lastDamageAt = Date()
            Haptics.damage()

        case .kill(let shooterId, _):
            if shooterId == me?.id {
                self.iJustKilled = true
                Haptics.kill()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.iJustKilled = false }
            }

        case .respawn:
            break

        case .gameEnd:
            self.phase = .ended

        case .reloadComplete, .shotMissed, .dryFire:
            break

        case .error(let e):
            self.errorText = e
            debug("SERVER ERROR: \(e)")
            // Hard errors (e.g. "Room not found") mean we shouldn't keep retrying.
            if e.lowercased().contains("not found") || e.lowercased().contains("in progress") {
                pendingAction = .none
                task?.cancel(with: .goingAway, reason: nil)
                phase = .disconnected
            }

        case .unknown:
            break
        }
    }

    // ─── outgoing ───────────────────────────────────────────
    func toggleReady() {
        guard let me = me, let p = state?.players.first(where: { $0.id == me.id }) else { return }
        send(.ready(!p.ready))
    }
    func fire(targetBib: String?, worldPos: [Double]? = nil) {
        send(.fire(targetBib: targetBib, worldPos: worldPos))
        Haptics.fire()
    }
    func forceStart() { send(.forceStart) }
    func resetLobby() { send(.resetLobby) }

    private func send(_ msg: ClientMessage) {
        guard let task = task else { return }
        let enc = JSONEncoder()
        guard let data = try? enc.encode(msg),
              let s = String(data: data, encoding: .utf8) else { return }
        task.send(.string(s)) { _ in }
    }
}

// ─── haptics ─────────────────────────────────────────────────
import UIKit
enum Haptics {
    static func fire() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func medium() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func damage() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    static func kill() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}
