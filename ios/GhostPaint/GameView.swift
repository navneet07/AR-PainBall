// GhostPaint · main gameplay view
// ARKit camera feed + SwiftUI HUD overlay

import SwiftUI
import ARKit
import CoreMotion

struct GameView: View {
    @EnvironmentObject var client: GameClient
    @StateObject private var scanner = QRScanner()
    @StateObject private var motion = MotionManager()

    var body: some View {
        ZStack {
            ARCameraContainer(scanner: scanner)
                .ignoresSafeArea()

            DamageVignette(isFlashing: client.lastDamageAt != nil && Date().timeIntervalSince(client.lastDamageAt!) < 0.3)

            // HUD
            VStack {
                topBar
                compass
                Spacer()
            }
            HStack {
                killFeed; Spacer(); scoreboard
            }
            .padding(.horizontal, 16).padding(.top, 96)

            reticle

            VStack {
                Spacer()
                HStack(alignment: .bottom) {
                    healthPanel; Spacer(); ammoPanel
                }
                .padding(.horizontal, 16).padding(.bottom, 24)
            }
        }
        .onTapGesture { fire() }
    }

    func fire() {
        let target = scanner.bibInReticle(reticleFraction: 0.25)?.payload
        client.fire(targetBib: target)
    }

    // ─── HUD components ─────────────────────────────────────
    var topBar: some View {
        HStack {
            Text("GHOSTPAINT").font(.system(size: 10, design: .monospaced)).tracking(4).foregroundColor(Color(hex: "#c8a6ff"))
            if let s = client.state, s.phase == "playing", let end = s.matchEndsAt {
                let left = max(0, Int((end - Date().timeIntervalSince1970 * 1000) / 1000))
                Text(String(format: "%d:%02d", left/60, left % 60))
                    .font(.system(size: 13, design: .monospaced)).foregroundColor(.cyan)
                    .tracking(2)
            }
            Spacer()
            Circle().fill(Color(hex: "#69f0ae")).frame(width: 6, height: 6).shadow(color: .green, radius: 3)
            Text("LIVE").font(.system(size: 9, design: .monospaced)).foregroundColor(Color(hex: "#69f0ae")).tracking(2)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color.black.opacity(0.4))
        .overlay(Rectangle().frame(height: 1).foregroundColor(.cyan.opacity(0.3)), alignment: .bottom)
    }

    var compass: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2).fill(Color.black.opacity(0.4))
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.cyan.opacity(0.3), lineWidth: 1))
                .shadow(color: .cyan.opacity(0.3), radius: 8)
            GeometryReader { g in
                let heading = motion.heading  // 0..360
                let tickSpacing: CGFloat = 30
                HStack(spacing: 0) {
                    ForEach(-3..<13) { i in
                        let deg = (CGFloat(i) * 30 + 360).truncatingRemainder(dividingBy: 360)
                        Text(label(for: deg))
                            .font(.system(size: 10, design: .monospaced)).foregroundColor(.cyan)
                            .tracking(1.4)
                            .frame(width: tickSpacing)
                    }
                }
                .offset(x: g.size.width/2 - heading/360 * tickSpacing * 12 - tickSpacing/2)
            }
            Triangle().fill(Color.cyan).frame(width: 8, height: 6).shadow(color: .cyan, radius: 3).offset(y: -14)
        }
        .frame(height: 22)
        .padding(.horizontal, 60).padding(.top, 6)
    }

    func label(for deg: CGFloat) -> String {
        let rounded = Int((deg / 30).rounded()) * 30
        switch rounded % 360 {
        case 0: return "N"; case 30: return "30"; case 60: return "60"
        case 90: return "E"; case 120: return "120"; case 150: return "150"
        case 180: return "S"; case 210: return "210"; case 240: return "240"
        case 270: return "W"; case 300: return "300"; case 330: return "330"
        default: return "\(rounded)"
        }
    }

    var killFeed: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("KILL FEED").font(.system(size: 9, design: .monospaced)).tracking(3).foregroundColor(Color(hex: "#c8a6ff"))
            ForEach(Array((client.state?.killFeed ?? []).prefix(4))) { k in
                let sh = client.state?.players.first { $0.id == k.shooterId }
                let vi = client.state?.players.first { $0.id == k.victimId }
                HStack(spacing: 6) {
                    Text(sh?.name ?? "?").foregroundColor(Color(hex: sh?.color ?? "#5cf6ff"))
                    Text("→").foregroundColor(.gray)
                    Text(vi?.name ?? "?").foregroundColor(Color(hex: vi?.color ?? "#ff3040"))
                }
                .font(.system(size: 10, design: .monospaced))
                .padding(.leading, 8)
                .overlay(Rectangle().frame(width: 2).foregroundColor(Color(hex: "#ff3040")), alignment: .leading)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 3).fill(Color.black.opacity(0.4)))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.cyan.opacity(0.3), lineWidth: 1))
        .shadow(color: .cyan.opacity(0.3), radius: 6)
        .frame(maxWidth: 200, alignment: .leading)
    }

    var scoreboard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SCOREBOARD").font(.system(size: 9, design: .monospaced)).tracking(3).foregroundColor(Color(hex: "#c8a6ff"))
            ForEach(sortedPlayers) { p in
                HStack(spacing: 6) {
                    Circle().fill(Color(hex: p.color)).frame(width: 8, height: 8).shadow(color: Color(hex: p.color), radius: 3)
                    Text(p.name).font(.system(size: 10, design: .monospaced)).foregroundColor(p.alive ? Color(hex: "#e9e3ff") : .gray)
                    Spacer()
                    Text("\(p.kills)").font(.system(size: 10, design: .monospaced)).foregroundColor(.cyan).tracking(1)
                }
            }
        }
        .padding(10)
        .frame(width: 180, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 3).fill(Color.black.opacity(0.4)))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.cyan.opacity(0.3), lineWidth: 1))
        .shadow(color: .cyan.opacity(0.3), radius: 6)
    }

    var sortedPlayers: [Player] {
        (client.state?.players ?? []).sorted { a, b in
            if a.kills != b.kills { return a.kills > b.kills }
            return a.deaths < b.deaths
        }
    }

    var reticle: some View {
        ZStack {
            Circle().strokeBorder(client.iJustHit ? Color(hex: "#ff3040") : .cyan, lineWidth: 1.5)
                .frame(width: 56, height: 56)
                .shadow(color: client.iJustHit ? Color(hex: "#ff3040") : .cyan, radius: 6)
            Rectangle().fill(client.iJustHit ? Color(hex: "#ff3040") : .cyan).frame(width: 1.5, height: 36)
            Rectangle().fill(client.iJustHit ? Color(hex: "#ff3040") : .cyan).frame(width: 36, height: 1.5)
        }
        .scaleEffect(client.iJustHit ? 1.25 : 1.0)
        .animation(.easeOut(duration: 0.15), value: client.iJustHit)
    }

    var healthPanel: some View {
        let myP = client.state?.players.first { $0.id == client.me?.id }
        let hp = myP?.hp ?? 100
        return VStack(alignment: .leading, spacing: 4) {
            Text("HEALTH").font(.system(size: 9, design: .monospaced)).tracking(3).foregroundColor(Color(hex: "#c8a6ff"))
            Text("\(hp)").font(.system(size: 24, weight: .medium, design: .monospaced))
                .foregroundColor(hp < 30 ? Color(hex: "#ff3040") : .cyan)
            ZStack(alignment: .leading) {
                Rectangle().fill(Color(hex: "#ff3040").opacity(0.15)).frame(width: 120, height: 6)
                Rectangle().fill(Color(hex: "#ff3040")).frame(width: CGFloat(hp) / 100 * 120, height: 6)
                    .shadow(color: Color(hex: "#ff3040"), radius: 4)
            }
            .overlay(Rectangle().stroke(Color(hex: "#ff3040"), lineWidth: 1))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 3).fill(Color.black.opacity(0.4)))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.cyan.opacity(0.3), lineWidth: 1))
        .shadow(color: .cyan.opacity(0.3), radius: 6)
    }

    var ammoPanel: some View {
        let myP = client.state?.players.first { $0.id == client.me?.id }
        let ammo = myP?.ammo ?? 15
        let reloading = myP?.reloading ?? false
        return VStack(alignment: .trailing, spacing: 4) {
            Text("AMMO").font(.system(size: 9, design: .monospaced)).tracking(3).foregroundColor(Color(hex: "#c8a6ff"))
            Text(reloading ? "RELOAD" : "\(ammo) / 15")
                .font(.system(size: 24, weight: .medium, design: .monospaced))
                .foregroundColor(reloading ? Color(hex: "#ffd166") : .cyan)
                .opacity(reloading || ammo <= 3 ? 0.7 : 1)
                .animation(.easeInOut(duration: 0.4).repeatForever(), value: reloading)
        }
        .padding(12)
        .frame(minWidth: 120, alignment: .trailing)
        .background(RoundedRectangle(cornerRadius: 3).fill(Color.black.opacity(0.4)))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.cyan.opacity(0.3), lineWidth: 1))
        .shadow(color: .cyan.opacity(0.3), radius: 6)
    }
}

// ─── AR camera container ────────────────────────────────────
struct ARCameraContainer: UIViewRepresentable {
    let scanner: QRScanner

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.session.delegate = context.coordinator
        let config = ARWorldTrackingConfiguration()
        config.environmentTexturing = .automatic
        view.session.run(config)
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(scanner: scanner) }

    final class Coordinator: NSObject, ARSessionDelegate {
        let scanner: QRScanner
        init(scanner: QRScanner) { self.scanner = scanner }
        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            Task { @MainActor in
                scanner.detect(pixelBuffer: frame.capturedImage)
            }
        }
    }
}

// ─── motion (compass) ───────────────────────────────────────
@MainActor
final class MotionManager: ObservableObject {
    @Published var heading: CGFloat = 0
    private let mgr = CMMotionManager()
    private let head = CMHeadphoneMotionManager()

    init() {
        // NOTE: v1 reads heading via CMMotionManager device attitude.
        // v1.1 polish pass: upgrade to CLLocationManagerDelegate.didUpdateHeading
        // for proper magnetic-north-aware compass.
        if mgr.isDeviceMotionAvailable {
            mgr.deviceMotionUpdateInterval = 1.0 / 15
            mgr.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
                guard let motion = motion else { return }
                let yaw = motion.attitude.yaw            // radians, 0 = reference
                let deg = (CGFloat(yaw) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
                self?.heading = deg
            }
        }
    }
}

import CoreLocation

// ─── small shapes ───────────────────────────────────────────
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

struct DamageVignette: View {
    let isFlashing: Bool
    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .overlay(
                RadialGradient(colors: [.clear, Color(hex: "#ff3040").opacity(isFlashing ? 0.6 : 0)], center: .center, startRadius: 200, endRadius: 500)
                    .blendMode(.screen)
            )
            .allowsHitTesting(false)
            .animation(.easeOut(duration: 0.25), value: isFlashing)
    }
}
