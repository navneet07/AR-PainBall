# GhostPaint · iOS client · setup

## What's here

Eight Swift files that form the complete iOS app. Not an `.xcodeproj` yet —
you create that in Xcode and add the files. That's 3 minutes of clicking.

## Setup (one-time)

1. Open **Xcode → File → New → Project → iOS → App**
   - Product name: `GhostPaint`
   - Interface: **SwiftUI**
   - Language: **Swift**
   - Minimum deployments: **iOS 17.0**
   - Save into this folder (`ios/`) — Xcode will create `GhostPaint.xcodeproj/`

2. **Delete** Xcode's auto-generated `ContentView.swift` and `GhostPaintApp.swift`
   (they conflict with ours).

3. **Right-click** the project navigator → **Add Files to "GhostPaint"…** and
   select all 6 `.swift` files from `GhostPaint/`:
   - `GhostPaintApp.swift`
   - `Models.swift`
   - `GameClient.swift`
   - `LobbyView.swift`
   - `GameView.swift`
   - `EndOfMatchView.swift`
   - `QRScanner.swift`

4. In the **Signing & Capabilities** tab:
   - Team: your Apple ID (personal team is fine for local dev)
   - Bundle ID: `com.nitin.ghostpaint` (anything unique)
   - **Add capability:** *nothing additional* — ARKit/Vision/Network are entitlements-free

5. In `Info.plist`, add these keys:
   - `NSCameraUsageDescription` → *"GhostPaint needs the camera to detect player bibs."*
   - `NSLocalNetworkUsageDescription` → *"GhostPaint connects to a local Mac game server."*
   - `NSBonjourServices` (Array) → add item `_ghostpaint._tcp`
   - `NSLocationWhenInUseUsageDescription` → *"Optional minimap needs GPS."*
   - `Privacy - Motion Usage Description` → *"Compass bearing uses device motion."*

6. **Connect your iPhone** via USB → select it as the run destination → **Cmd-R**.

## Play

1. Start the server on your Mac:
   ```
   cd ../server
   npm install
   npm start
   ```
2. Make sure iPhone and Mac are on the same WiFi (or use Mac as hotspot).
3. Open GhostPaint on the iPhone. It'll list the Mac via Bonjour OR you type
   the Mac's LAN IP + port `8200`.
4. Enter callsign, join, ready up. When all players ready, match starts.

## File map

| File | Role |
|---|---|
| `GhostPaintApp.swift` | App entry, phase-driven root view |
| `Models.swift` | Codable message types + ClientPhase enum + Color(hex:) helper |
| `GameClient.swift` | `@MainActor ObservableObject` · WebSocket + Bonjour + haptics |
| `LobbyView.swift` | Connect screen, roster, ready-up, countdown |
| `GameView.swift` | ARKit camera + HUD overlay (compass, HP, ammo, kill feed, scoreboard, reticle) |
| `EndOfMatchView.swift` | Winner banner + final scoreboard + "leave" |
| `QRScanner.swift` | Vision framework QR detection per frame |

## What's NOT in the skeleton (v1.1 work)

- Sound effects · `AVAudioPlayer` setup + pre-loaded `.wav`s (add `Sounds/` folder)
- Paint trail · store `ARAnchor` on each shot, render `SCNNode`s, send world-map
  export to server at match end so other clients can overlay your trail
- LiDAR-aware hit detection · only the iPhone 17 Pro Max / Pro benefits; falls
  back gracefully on non-LiDAR devices today
- CoreLocation heading · currently `CMMotionManager` yaw; upgrade to
  `CLLocationManager.didUpdateHeading` for true magnetic-north compass

## Known linter noise

If you open these `.swift` files **before** putting them in an Xcode project,
you'll see errors like *"Cannot find type 'GameClient' in scope"* — that's
SourceKit linting each file in isolation. Once they're in the same Xcode
target, all those resolve instantly.
