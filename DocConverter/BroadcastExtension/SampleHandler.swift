import ReplayKit
import UIKit
import CoreImage

/// Broadcast Upload Extension: receives the phone screen (e.g. the eSight
/// Companion app showing the glasses camera), throttles to ~1 frame every 2s,
/// sends it to the server's /convert/live-ocr, and hands the recognised text to
/// the main app (via the shared App Group + a Darwin notification) which speaks
/// it aloud. Kept memory-light (no on-device OCR) to respect the ~50MB limit.
class SampleHandler: RPBroadcastSampleHandler {
    private let appGroup = "group.com.bellinghamfolks.docconverter"
    private let endpoint = URL(string: "https://ion-production-da28.up.railway.app/convert/live-ocr")!
    private let darwinName = "com.bellinghamfolks.docconverter.livetext"
    private let minInterval: TimeInterval = 2.0

    private var lastSent = Date(timeIntervalSince1970: 0)
    private var inFlight = false
    private var lastText = ""
    private let ciContext = CIContext(options: [.priorityRequestLow: true])

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video, !inFlight else { return }
        let now = Date()
        guard now.timeIntervalSince(lastSent) >= minInterval else { return }
        guard let pixel = CMSampleBufferGetImageBuffer(sampleBuffer),
              let jpeg = jpeg(from: pixel, maxEdge: 1600, quality: 0.6) else { return }
        lastSent = now
        inFlight = true
        send(jpeg)
    }

    private func send(_ jpeg: Data) {
        let model = UserDefaults(suiteName: appGroup)?.string(forKey: "live.model") ?? "gemini-3.6-flash"
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 15
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "imageBase64": jpeg.base64EncodedString(),
            "model": model,
        ])
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let self else { return }
            defer { self.inFlight = false }
            guard let data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let text = obj["text"] as? String else { return }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed != self.lastText else { return }
            self.lastText = trimmed
            self.publish(trimmed)
        }.resume()
    }

    private func publish(_ text: String) {
        let d = UserDefaults(suiteName: appGroup)
        d?.set(text, forKey: "live.text")
        d?.set(Date().timeIntervalSince1970, forKey: "live.ts")
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(darwinName as CFString), nil, nil, true)
    }

    private func jpeg(from pixelBuffer: CVPixelBuffer, maxEdge: CGFloat, quality: CGFloat) -> Data? {
        let ci = CIImage(cvPixelBuffer: pixelBuffer)
        let extent = ci.extent
        guard extent.width > 0, extent.height > 0 else { return nil }
        let scale = min(1, maxEdge / max(extent.width, extent.height))
        let scaled = scale < 1 ? ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) : ci
        guard let cg = ciContext.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg).jpegData(compressionQuality: quality)
    }
}
