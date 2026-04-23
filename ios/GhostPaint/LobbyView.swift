// GhostPaint · lobby / join / countdown (v0.3 · room-code edition)
// BTD6-style UX: host creates a room, code is displayed, friends type the code.

import SwiftUI

struct LobbyView: View {
    @EnvironmentObject var client: GameClient
    @AppStorage("callsign") private var name: String = ""
    @State private var codeInput: String = ""

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [Color(hex: "#1a1438"), Color(hex: "#0a0612")],
                center: .top, startRadius: 20, endRadius: 800
            ).ignoresSafeArea()

            switch client.phase {
            case .disconnected, .connecting, .joining:
                entryView
            case .inLobby:
                lobbyRoster
            case .countdown:
                countdown
            default:
                EmptyView()
            }
        }
    }

    // ─── entry screen: callsign + optional code ─────────────
    var entryView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("GHOSTPAINT")
                    .font(.system(size: 34, weight: .medium, design: .monospaced))
                    .tracking(8)
                    .foregroundColor(Color(hex: "#c8a6ff"))
                Text("AR PAINTBALL · MULTIPLAYER")
                    .font(.system(size: 11, design: .monospaced))
                    .tracking(6)
                    .foregroundColor(.cyan.opacity(0.7))

                VStack(alignment: .leading, spacing: 14) {
                    Text("CALLSIGN").font(.system(size: 10, design: .monospaced)).tracking(3).foregroundColor(.cyan.opacity(0.7))
                    TextField("Your name (3–12 chars)", text: $name)
                        .textFieldStyle(IronManField())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)

                    Text("ROOM CODE").font(.system(size: 10, design: .monospaced)).tracking(3).foregroundColor(.cyan.opacity(0.7))
                    TextField("6 digits — leave blank to host", text: $codeInput)
                        .textFieldStyle(IronManField())
                        .keyboardType(.numberPad)
                        .onChange(of: codeInput) { _, v in
                            // strip non-digits, cap at 6
                            let digits = v.filter { $0.isNumber }
                            codeInput = String(digits.prefix(6))
                        }

                    Button(action: connect) {
                        Text(buttonLabel)
                            .tracking(4)
                            .font(.system(.callout, design: .monospaced).weight(.medium))
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                    }
                    .buttonStyle(IronManButton())
                    .disabled(name.count < 3 || isBusy || (!codeInput.isEmpty && codeInput.count != 6))
                }
                .padding(24)
                .frame(maxWidth: 380)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color(hex: "#1f1838").opacity(0.6)))
                .overlay(IronManPanelBorder())

                if let status = client.statusText {
                    Text(status).font(.system(.caption, design: .monospaced))
                        .foregroundColor(.cyan.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
                if let err = client.errorText {
                    Text(err).font(.system(.caption, design: .monospaced))
                        .foregroundColor(Color(hex: "#ff3040"))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Text("Leave the code blank to host a new room.\nFriends type your 6-digit code to join.")
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
        if client.phase == .connecting { return "CONNECTING…" }
        if client.phase == .joining    { return "JOINING…" }
        return codeInput.isEmpty ? "CREATE ROOM" : "JOIN ROOM \(codeInput)"
    }

    func connect() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if codeInput.isEmpty {
            client.host(name: trimmed)
        } else {
            client.join(code: codeInput, name: trimmed)
        }
    }

    // ─── lobby roster (room code shown prominently) ─────────
    var lobbyRoster: some View {
        VStack(spacing: 16) {
            Text("LOBBY")
                .font(.system(size: 24, weight: .medium, design: .monospaced))
                .tracking(10)
                .foregroundColor(Color(hex: "#c8a6ff"))

            // Room code banner · host shares this with friends
            if let code = client.roomCode {
                VStack(spacing: 4) {
                    Text("ROOM CODE")
                        .font(.system(size: 10, design: .monospaced))
                        .tracking(4)
                        .foregroundColor(Color(hex: "#c8a6ff"))
                    Text(code)
                        .font(.system(size: 32, weight: .medium, design: .monospaced))
                        .tracking(12)
                        .foregroundColor(Color(hex: "#ffd166"))
                        .shadow(color: Color(hex: "#ffd166").opacity(0.5), radius: 10)
                    Text(client.isHost ? "Share with your squad" : "Joined")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.gray)
                        .tracking(2)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 28)
                .background(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: "#ffd166"), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            }

            if let state = client.state {
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

                    Button(action: { client.leave() }) {
                        Text("LEAVE ROOM")
                            .tracking(5).padding(.vertical, 10).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(IronManButton(color: Color(hex: "#ff3040")))
                }
                .padding(.horizontal, 24)
            }

            Text("All-ready starts the match.\nSolo test bypasses the ready gate.")
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
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
