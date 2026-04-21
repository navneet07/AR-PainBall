// GhostPaint · live QR detection using Apple's Vision framework
// Feed it CVPixelBuffer from ARKit; get back [DetectedBib].

import Foundation
import Vision
import CoreVideo
import CoreGraphics
import QuartzCore

struct DetectedBib: Identifiable {
    var id: String { payload }
    let payload: String          // e.g. "bib-03"
    let boundingBox: CGRect      // normalized 0..1, origin bottom-left (Vision convention)
    let timestamp: TimeInterval
}

@MainActor
final class QRScanner: ObservableObject {
    @Published var visibleBibs: [DetectedBib] = []

    private var lastRunAt: TimeInterval = 0
    private let minInterval: TimeInterval = 1.0 / 15   // 15 fps max to save battery

    func detect(pixelBuffer: CVPixelBuffer) {
        let now = CACurrentMediaTime()
        guard now - lastRunAt > minInterval else { return }
        lastRunAt = now

        let req = VNDetectBarcodesRequest { [weak self] request, _ in
            guard let self = self else { return }
            let observations = (request.results as? [VNBarcodeObservation]) ?? []
            let bibs: [DetectedBib] = observations.compactMap { obs in
                guard obs.symbology == VNBarcodeSymbology.qr else { return nil }
                guard let payload = obs.payloadStringValue, payload.hasPrefix("bib-") else { return nil }
                return DetectedBib(payload: payload, boundingBox: obs.boundingBox, timestamp: now)
            }
            Task { @MainActor in
                self.visibleBibs = bibs
            }
        }
        req.symbologies = [VNBarcodeSymbology.qr]

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            try? handler.perform([req])
        }
    }

    /// The reticle is the center rectangle of the screen. A bib is "aimed at"
    /// if its bounding box center falls inside the reticle zone.
    /// Vision's boundingBox is normalized with origin bottom-left.
    func bibInReticle(reticleFraction: CGFloat = 0.25) -> DetectedBib? {
        let center = CGPoint(x: 0.5, y: 0.5)
        let half = reticleFraction / 2
        let reticle = CGRect(x: center.x - half, y: center.y - half, width: reticleFraction, height: reticleFraction)
        return visibleBibs.first { bib in
            let c = CGPoint(x: bib.boundingBox.midX, y: bib.boundingBox.midY)
            return reticle.contains(c)
        }
    }
}
