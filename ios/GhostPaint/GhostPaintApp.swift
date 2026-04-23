// GhostPaint · app entry
// iOS 17+ · SwiftUI · ARKit · Vision · Network

import SwiftUI

@main
struct GhostPaintApp: App {
    @StateObject private var client = GameClient()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(client)
                .preferredColorScheme(.dark)
                .persistentSystemOverlays(.hidden)
                .statusBar(hidden: true)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var client: GameClient

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            switch client.phase {
            case .disconnected, .connecting, .joining:
                LobbyView()
            case .inLobby, .countdown:
                LobbyView()
            case .playing:
                GameView()
            case .ended:
                EndOfMatchView()
            }

            // Always-visible debug overlay · tap pill to expand
            DebugOverlay()
        }
    }
}
