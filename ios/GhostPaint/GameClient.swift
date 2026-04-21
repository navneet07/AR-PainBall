// GhostPaint · WebSocket client + Bonjour browser
// ObservableObject that the whole UI reads from.

import Foundation
import SwiftUI
import Network

@MainActor
final class GameClient: NSObject, ObservableObject, URLSessionWebSocketDelegate {

    @Published var phase: ClientPhase = .disconnected
    @Published var serverURL: URL? = nil      // ws://host:port/ws?role=player
    @Published var me: Player? = nil
    @Published var state: PublicState? = nil
    @Published var discoveredHosts: [DiscoveredHost] = []
    @Published var killFeedTicker: [KillEntry] = []
    @Published var lastDamageAt: Date? = nil
    @Published var iJustHit: Bool = false
    @Published var iJustKilled: Bool = false
    @Published var errorText: String? = nil

    struct DiscoveredHost: Identifiable, Equatable {
        let id = UUID()
        let name: String
        let host: String
        let port: Int
    }

    private var task: URLSessionWebSocketTask? = nil
    private var browser: NWBrowser? = nil
    private var reconnectWorkItem: DispatchWorkItem? = nil
    private var manualURL: URL? = nil
    private var pendingJoinName: String? = nil   // queued until socket opens
    private var savedName: String? = nil         // for reconnect

    // ─── Bonjour discovery ──────────────────────────────────
    func startBrowsing() {
        let params = NWParameters()
        params.includePeerToPeer = false
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_ghostpaint._tcp", domain: "local."), using: params)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                self?.discoveredHosts = results.compactMap { result in
                    if case let .service(name, _, _, _) = result.endpoint {
                        // NWBrowser doesn't directly give IP; we'd resolve via NWConnection in v2.
                        // For v1, rely on manual IP entry fallback.
                        return DiscoveredHost(name: name, host: "\(name).local.", port: 8200)
                    }
                    return nil
                }
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func autoConnect() async {
        startBrowsing()
        // v1 strategy: if user hasn't typed an IP, wait briefly for Bonjour, otherwise fall back.
    }

    // ─── connect + auto-join in one shot ────────────────────
    /// Opens a socket and queues a join message. The join is sent the moment
    /// the socket reaches .running state (via URLSessionWebSocketDelegate).
    /// Single-button UX: user enters host + port + name, taps once.
    func connectAndJoin(host: String, port: Int = 8200, name: String) {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "ws://", with: "")
        let urlString = "ws://\(trimmedHost):\(port)/ws?role=player"
        guard let url = URL(string: urlString) else {
            self.errorText = "Bad host/port"; return
        }
        self.manualURL = url
        self.serverURL = url
        self.phase = .connecting
        self.errorText = nil
        self.pendingJoinName = name
        self.savedName = name
        openSocket(url: url)
    }

    /// Legacy entry point — connects without auto-joining.
    func connect(host: String, port: Int = 8200) {
        connectAndJoin(host: host, port: port, name: "Ghost")
    }

    private func openSocket(url: URL) {
        task?.cancel(with: .goingAway, reason: nil)
        // delegateQueue: nil → callbacks on a background queue; we hop to MainActor inside.
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
            if let name = self.pendingJoinName {
                self.pendingJoinName = nil
                self.phase = .joining
                self.send(.join(name: name))
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession,
                                webSocketTask: URLSessionWebSocketTask,
                                didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                                reason: Data?) {
        Task { @MainActor in
            self.phase = .disconnected
            self.errorText = "Connection closed (code \(closeCode.rawValue))"
            self.scheduleReconnect()
        }
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let err):
                Task { @MainActor in
                    self.phase = .disconnected
                    self.errorText = err.localizedDescription
                    self.scheduleReconnect()
                }
            case .success(let msg):
                if case let .string(text) = msg, let data = text.data(using: .utf8) {
                    Task { @MainActor in self.dispatch(data: data) }
                }
                self.receiveLoop()
            }
        }
    }

    private func scheduleReconnect() {
        guard let url = manualURL else { return }
        reconnectWorkItem?.cancel()
        // Re-arm the auto-join for the reconnect attempt
        if let name = self.savedName, self.pendingJoinName == nil {
            self.pendingJoinName = name
        }
        let item = DispatchWorkItem { [weak self] in
            self?.phase = .connecting
            self?.openSocket(url: url)
        }
        reconnectWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: item)
    }

    // ─── dispatch ───────────────────────────────────────────
    private func dispatch(data: Data) {
        let decoder = JSONDecoder()
        guard let msg = try? decoder.decode(ServerMessage.self, from: data) else { return }
        switch msg {
        case .joined(let p):
            self.me = p
            self.phase = .inLobby
        case .state(let s):
            self.state = s
            switch s.phase {
            case "lobby":     if self.me != nil { self.phase = .inLobby }
            case "countdown": self.phase = .countdown
            case "playing":   self.phase = .playing
            case "ended":     self.phase = .ended
            default: break
            }
        case .gameStart:
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
        case .unknown:
            break
        }
    }

    // ─── send ───────────────────────────────────────────────
    func join(name: String) {
        phase = .joining
        send(.join(name: name))
    }
    func toggleReady() {
        guard let me = me, let p = state?.players.first(where: { $0.id == me.id }) else { return }
        send(.ready(!p.ready))
    }
    func fire(targetBib: String?, worldPos: [Double]? = nil) {
        send(.fire(targetBib: targetBib, worldPos: worldPos))
        Haptics.fire()
    }
    func forceStart() {
        send(.forceStart)
    }
    func resetLobby() {
        send(.resetLobby)
    }
    func leave() {
        send(.leave)
        task?.cancel(with: .goingAway, reason: nil)
        phase = .disconnected
        me = nil
    }

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
