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
    @Published var debugLog: [String] = []       // last ~30 lines of activity
    @Published var rawLastMessage: String = ""   // for deep debugging

    private func debug(_ line: String) {
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        debugLog.append("\(stamp) \(line)")
        if debugLog.count > 30 { debugLog.removeFirst(debugLog.count - 30) }
        print("[GAMECLIENT] \(line)")
    }

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
    // Browses for _ghostpaint._tcp services on local.  For each service found,
    // opens a short-lived NWConnection to resolve the real hostname + port,
    // then populates discoveredHosts with usable IP:port pairs.
    func startBrowsing() {
        let params = NWParameters()
        params.includePeerToPeer = false
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_ghostpaint._tcp", domain: "local."), using: params)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                for result in results {
                    self?.resolve(result)
                }
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    private func resolve(_ result: NWBrowser.Result) {
        guard case let .service(serviceName, _, _, _) = result.endpoint else { return }
        let conn = NWConnection(to: result.endpoint, using: .tcp)
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                // Extract resolved remote endpoint → real host + port
                if let remote = conn.currentPath?.remoteEndpoint {
                    if case let .hostPort(host, port) = remote {
                        let hostString: String = {
                            switch host {
                            case .name(let n, _): return n
                            case .ipv4(let a):    return "\(a)"
                            case .ipv6(let a):    return "\(a)"
                            @unknown default:     return "\(host)"
                            }
                        }()
                        Task { @MainActor in
                            let entry = DiscoveredHost(name: serviceName, host: hostString, port: Int(port.rawValue))
                            self?.upsertDiscoveredHost(entry)
                        }
                    }
                }
                conn.cancel()
            case .failed, .cancelled:
                conn.cancel()
            default:
                break
            }
        }
        conn.start(queue: .main)
    }

    private func upsertDiscoveredHost(_ h: DiscoveredHost) {
        if let idx = discoveredHosts.firstIndex(where: { $0.name == h.name }) {
            discoveredHosts[idx] = h
        } else {
            discoveredHosts.append(h)
        }
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
            self.debug("WS OPEN")
            if let name = self.pendingJoinName {
                self.pendingJoinName = nil
                self.phase = .joining
                self.debug("auto-sending join name=\(name)")
                self.send(.join(name: name))
            }
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

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self = self else { return }
            // Always hop to MainActor — dispatch AND next receive-loop fire there,
            // preventing races with @Published writes.
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
        let msg: ServerMessage
        do {
            msg = try decoder.decode(ServerMessage.self, from: data)
        } catch {
            let preview = String(data: data, encoding: .utf8)?.prefix(80) ?? ""
            debug("DECODE FAIL: \(error.localizedDescription) · \(preview)")
            return
        }
        switch msg {
        case .joined(let p):
            self.me = p
            self.phase = .inLobby
            debug("JOINED as \(p.name)/\(p.bibId)")
        case .state(let s):
            self.state = s
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
