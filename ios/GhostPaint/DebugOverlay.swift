// GhostPaint · on-screen debug overlay
// Tap the phase pill (top-right) to expand/collapse the log panel.
// Shows: current phase, WS state, last 30 debug lines. Essential during dev.

import SwiftUI

struct DebugOverlay: View {
    @EnvironmentObject var client: GameClient
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            pill
                .onTapGesture { expanded.toggle() }
            if expanded {
                panel
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.top, 4)
        .padding(.trailing, 8)
        .animation(.easeOut(duration: 0.2), value: expanded)
    }

    var pill: some View {
        HStack(spacing: 5) {
            Circle().fill(phaseColor).frame(width: 6, height: 6).shadow(color: phaseColor, radius: 3)
            Text(phaseLabel).font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(2)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.black.opacity(0.65))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(phaseColor.opacity(0.5), lineWidth: 1))
        .cornerRadius(10)
    }

    var panel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("DEBUG LOG · tap pill to close")
                .font(.system(size: 8, design: .monospaced)).tracking(2)
                .foregroundColor(Color(hex: "#c8a6ff"))
            ForEach(client.debugLog.suffix(12).reversed(), id: \.self) { line in
                Text(line)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(2)
            }
            if !client.rawLastMessage.isEmpty {
                Divider().background(Color.cyan.opacity(0.3))
                Text("LAST RAW:").font(.system(size: 8, design: .monospaced)).tracking(2).foregroundColor(.cyan.opacity(0.7))
                Text(client.rawLastMessage.prefix(200))
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(4)
            }
        }
        .padding(10)
        .frame(width: 320, alignment: .leading)
        .background(Color.black.opacity(0.85))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.cyan.opacity(0.35), lineWidth: 1))
        .cornerRadius(4)
        .shadow(color: .cyan.opacity(0.3), radius: 6)
        .padding(.top, 4)
    }

    var phaseLabel: String {
        switch client.phase {
        case .disconnected: return "DISCONNECT"
        case .connecting:   return "CONNECTING"
        case .joining:      return "JOINING"
        case .inLobby:      return "LOBBY"
        case .countdown:    return "COUNTDOWN"
        case .playing:      return "PLAYING"
        case .ended:        return "ENDED"
        }
    }

    var phaseColor: Color {
        switch client.phase {
        case .disconnected: return Color(hex: "#ff3040")
        case .connecting, .joining: return Color(hex: "#ffd166")
        case .inLobby:      return Color(hex: "#5cf6ff")
        case .countdown:    return Color(hex: "#c8a6ff")
        case .playing:      return Color(hex: "#69f0ae")
        case .ended:        return Color(hex: "#ff7030")
        }
    }
}
