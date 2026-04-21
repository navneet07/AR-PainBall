// GhostPaint · lobby / join / countdown
// Applies the Iron Man aesthetic.

import SwiftUI

struct LobbyView: View {
    @EnvironmentObject var client: GameClient
    @State private var name: String = ""
    @State private var host: String = ""
    @State private var port: String = "8200"

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [Color(hex: "#1a1438"), Color(hex: "#0a0612")],
                center: .top, startRadius: 20, endRadius: 800
            ).ignoresSafeArea()

            switch client.phase {
            case .disconnected, .connecting:
                connectView
            case .joining:
                ProgressView("Joining…").tint(.cyan)
            case .inLobby:
                lobbyRoster
            case .countdown:
                countdown
            default:
                EmptyView()
            }
        }
    }

    // ─── connect screen (now also captures callsign) ────────
    var connectView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("GHOSTPAINT")
                    .font(.system(size: 34, weight: .medium, design: .monospaced))
                    .tracking(8)
                    .foregroundColor(Color(hex: "#c8a6ff"))
                Text("AR PAINTBALL · LOCAL LAN")
                    .font(.system(size: 11, design: .monospaced))
                    .tracking(6)
                    .foregroundColor(.cyan.opacity(0.7))

                VStack(alignment: .leading, spacing: 12) {
                    if !client.discoveredHosts.isEmpty {
                        Text("FOUND").font(.system(size: 10, design: .monospaced)).tracking(3).foregroundColor(.cyan.opacity(0.7))
                        ForEach(client.discoveredHosts) { h in
                            Button(action: { joinDiscovered(h) }) {
                                HStack {
                                    Image(systemName: "dot.radiowaves.right")
                                    Text(h.name).font(.system(.callout, design: .monospaced))
                                    Spacer()
                                }
                                .padding(12)
                                .foregroundColor(.cyan)
                                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.cyan, lineWidth: 1))
                            }
                            .disabled(name.count < 3)
                        }
                        Divider().background(Color.cyan.opacity(0.3))
                    }

                    Text("CALLSIGN").font(.system(size: 10, design: .monospaced)).tracking(3).foregroundColor(.cyan.opacity(0.7))
                    TextField("Your name (3-12 chars)", text: $name)
                        .textFieldStyle(IronManField())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)

                    Text("SERVER").font(.system(size: 10, design: .monospaced)).tracking(3).foregroundColor(.cyan.opacity(0.7))
                    HStack(spacing: 8) {
                        TextField("Mac IP (e.g. 172.20.10.12)", text: $host)
                            .textFieldStyle(IronManField())
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.numbersAndPunctuation)
                        TextField("8200", text: $port)
                            .textFieldStyle(IronManField())
                            .keyboardType(.numberPad)
                            .frame(width: 80)
                    }

                    Button(action: connectAndJoin) {
                        Text(buttonLabel)
                            .tracking(4)
                            .font(.system(.callout, design: .monospaced).weight(.medium))
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                    }
                    .buttonStyle(IronManButton())
                    .disabled(host.isEmpty || name.count < 3 || isBusy)
                }
                .padding(24)
                .frame(maxWidth: 380)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color(hex: "#1f1838").opacity(0.6)))
                .overlay(IronManPanelBorder())

                if let err = client.errorText {
                    Text(err).font(.system(.caption, design: .monospaced))
                        .foregroundColor(Color(hex: "#ff3040"))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Text("Tip: same WiFi as the Mac. Find Mac IP with `ipconfig getifaddr en0`.")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.top, 4)
            }
            .padding()
        }
    }

    private var isBusy: Bool {
        client.phase == .connecting || client.phase == .joining
    }

    private var buttonLabel: String {
        switch client.phase {
        case .connecting: return "CONNECTING…"
        case .joining:    return "JOINING…"
        default:          return "CONNECT & JOIN"
        }
    }

    func connectAndJoin() {
        let p = Int(port) ?? 8200
        client.connectAndJoin(host: host, port: p, name: name)
    }

    func joinDiscovered(_ h: GameClient.DiscoveredHost) {
        client.connectAndJoin(host: h.host, port: h.port, name: name)
    }

    // ─── lobby roster ───────────────────────────────────────
    var lobbyRoster: some View {
        VStack(spacing: 16) {
            Text("LOBBY")
                .font(.system(size: 24, weight: .medium, design: .monospaced))
                .tracking(10)
                .foregroundColor(Color(hex: "#c8a6ff"))

            if client.me == nil {
                VStack {
                    TextField("Your callsign (3–12 chars)", text: $name)
                        .textFieldStyle(IronManField())
                        .onSubmit(joinWithName)
                    Button(action: joinWithName) {
                        Text("JOIN").tracking(6).padding(.vertical, 12).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(IronManButton())
                    .disabled(name.count < 3)
                }
                .padding().frame(maxWidth: 340)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color(hex: "#1f1838").opacity(0.6)))
                .overlay(IronManPanelBorder())
            } else if let state = client.state {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(state.players) { p in
                        HStack(spacing: 10) {
                            Circle().fill(Color(hex: p.color)).frame(width: 14, height: 14)
                                .shadow(color: Color(hex: p.color), radius: 6)
                            Text(p.name).font(.system(.callout, design: .monospaced))
                                .foregroundColor(p.id == client.me?.id ? .cyan : Color(hex: "#e9e3ff"))
                            if p.id == client.me?.id {
                                Text("(YOU)").font(.system(.caption2, design: .monospaced)).foregroundColor(.cyan.opacity(0.6)).tracking(2)
                            }
                            Spacer()
                            Text(p.ready ? "✓ READY" : "…")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(p.ready ? Color(hex: "#69f0ae") : Color(hex: "#8b86b3"))
                                .tracking(2)
                        }
                        .padding(.vertical, 4)
                        Divider().background(Color.cyan.opacity(0.1))
                    }
                }
                .padding().frame(maxWidth: 400)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color(hex: "#1f1838").opacity(0.6)))
                .overlay(IronManPanelBorder())

                VStack(spacing: 12) {
                    Button(action: { client.toggleReady() }) {
                        let myP = state.players.first(where: { $0.id == client.me?.id })
                        Text(myP?.ready == true ? "UN-READY" : "READY UP").tracking(6).padding(.vertical, 12).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(IronManButton(color: Color(hex: "#69f0ae")))

                    Button(action: { client.forceStart() }) {
                        Text("START SOLO · AR TEST")
                            .tracking(5).padding(.vertical, 12).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(IronManButton(color: Color(hex: "#ffd166")))
                }
                .padding(.horizontal, 24)
            }

            Text("Normal: everyone taps Ready → countdown.\nSolo test: tap START SOLO to jump straight to the AR camera.")
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }

    func joinWithName() {
        client.join(name: name)
    }

    // ─── countdown ──────────────────────────────────────────
    var countdown: some View {
        let ends = client.state?.countdownEndsAt ?? 0
        let leftMs = max(0, ends - Date().timeIntervalSince1970 * 1000)
        let secs = Int(ceil(leftMs / 1000))
        return VStack(spacing: 16) {
            Text("GET READY").tracking(10).font(.system(size: 20, design: .monospaced))
                .foregroundColor(Color(hex: "#c8a6ff"))
            Text("\(max(1, secs))")
                .font(.system(size: 180, weight: .medium, design: .monospaced))
                .foregroundColor(Color(hex: "#ffd166"))
                .shadow(color: Color(hex: "#ffd166"), radius: 30)
                .contentTransition(.numericText())
                .animation(.default, value: secs)
        }
    }
}

// ─── styles ─────────────────────────────────────────────────
struct IronManField: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.system(.callout, design: .monospaced))
            .foregroundColor(Color(hex: "#e9e3ff"))
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 2).fill(Color.black.opacity(0.5)))
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.cyan.opacity(0.35), lineWidth: 1))
    }
}

struct IronManButton: ButtonStyle {
    var color: Color = .cyan
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(color)
            .background(color.opacity(configuration.isPressed ? 0.2 : 0.08))
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(color, lineWidth: 1))
            .shadow(color: color.opacity(0.4), radius: 8)
    }
}

struct IronManPanelBorder: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 4).stroke(Color.cyan.opacity(0.3), lineWidth: 1)
            .overlay(
                GeometryReader { g in
                    Path { p in
                        let len: CGFloat = 16
                        let o: CGFloat = 1
                        // four corner brackets
                        p.move(to: CGPoint(x: o, y: len)); p.addLine(to: CGPoint(x: o, y: o)); p.addLine(to: CGPoint(x: len, y: o))
                        p.move(to: CGPoint(x: g.size.width - len, y: o)); p.addLine(to: CGPoint(x: g.size.width - o, y: o)); p.addLine(to: CGPoint(x: g.size.width - o, y: len))
                        p.move(to: CGPoint(x: o, y: g.size.height - len)); p.addLine(to: CGPoint(x: o, y: g.size.height - o)); p.addLine(to: CGPoint(x: len, y: g.size.height - o))
                        p.move(to: CGPoint(x: g.size.width - len, y: g.size.height - o)); p.addLine(to: CGPoint(x: g.size.width - o, y: g.size.height - o)); p.addLine(to: CGPoint(x: g.size.width - o, y: g.size.height - len))
                    }
                    .stroke(Color.cyan, lineWidth: 2)
                    .shadow(color: .cyan, radius: 4)
                }
            )
    }
}
