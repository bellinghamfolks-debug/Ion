// LiveSceneGuidanceController.swift
//
// iOS counterpart to Android's LiveWalkingController +
// LiveWalkingService (v3.2). Captures one JPEG every 2 seconds from
// the back camera via AVCaptureSession, sends it to Gemini in JSON
// mode with the live scene guidance prompt, and turns the response
// into:
//
//   1. Haptic feedback proportional to hazard.level
//        - stop     → 3 long pulses (notification .error)
//        - caution  → 2 short pulses (notification .warning)
//        - none     → silent
//   2. TTS announcement using a strict priority:
//        - hazard always speaks (never filtered)
//        - path speaks only on change and only when it is NOT a
//          near-duplicate of the last 3 spoken paths (Levenshtein
//          similarity ≥ 0.75 → suppress)
//        - scene speaks at most every 12 seconds
//   3. Rolling 3-frame summary fed back into the next prompt so
//      Gemini stops re-narrating the same corridor.
//
// Why no foreground "service" equivalent
// ──────────────────────────────────────
// iOS prohibits camera access from the background. The session is
// torn down automatically when the app backgrounds (the user's
// blind-walking session ends at the lock-screen, by design).
// We don't fight this — we surface a clear "Stopped" status when
// the app enters the background.
//
// Threading
// ─────────
// AVCaptureSession startup + frame capture happens on a dedicated
// session queue. Gemini calls run via async/await on the cooperative
// pool. UI bindings (@Published) are written on the main actor so
// SwiftUI can observe without dispatch hops.

#if canImport(UIKit)
@preconcurrency import AVFoundation
import Combine
import CoreLocation
import Foundation
import UIKit


private final class CaptureSessionWorker: @unchecked Sendable {
    private let captureSession = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "basir.live_scene.capture", qos: .userInitiated)
    private var configured = false
    private var captureInFlight = false
    private var photoDelegate: PhotoDelegate?

    func start(completion: @escaping @Sendable (String?) -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard granted else { completion("camera_denied"); return }
                self?.start(completion: completion)
            }
            return
        }
        guard status != .denied && status != .restricted else {
            completion("camera_denied")
            return
        }

        queue.async { [weak self] in
            guard let self else { return }
            if !self.configured {
                self.captureSession.beginConfiguration()
                self.captureSession.sessionPreset = .high
                let camera = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back)
                    ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                    ?? AVCaptureDevice.default(for: .video)
                guard let camera,
                      let input = try? AVCaptureDeviceInput(device: camera),
                      self.captureSession.canAddInput(input),
                      self.captureSession.canAddOutput(self.photoOutput) else {
                    self.captureSession.commitConfiguration()
                    completion("camera_open_failed")
                    return
                }
                self.captureSession.addInput(input)
                self.captureSession.addOutput(self.photoOutput)
                self.captureSession.commitConfiguration()
                self.configured = true
            }
            if !self.captureSession.isRunning { self.captureSession.startRunning() }
            completion(nil)
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            if self.captureSession.isRunning { self.captureSession.stopRunning() }
            self.captureInFlight = false
            self.photoDelegate = nil
        }
    }

    func capture(completion: @escaping @Sendable (Data?) -> Void) {
        queue.async { [weak self] in
            guard let self, self.captureSession.isRunning, !self.captureInFlight else {
                completion(nil)
                return
            }
            self.captureInFlight = true
            let settings = AVCapturePhotoSettings(
                format: [AVVideoCodecKey: AVVideoCodecType.jpeg]
            )
            let delegate = PhotoDelegate { [weak self] data in
                guard let self else { completion(nil); return }
                self.queue.async { [weak self] in
                    guard let self else { completion(nil); return }
                    self.captureInFlight = false
                    self.photoDelegate = nil
                    completion(data)
                }
            }
            self.photoDelegate = delegate
            self.photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }
}

@MainActor
final class LiveSceneGuidanceController: NSObject, ObservableObject {

    // ───── Published UI state ─────

    @Published private(set) var isRunning = false
    @Published private(set) var lastStatus: String = ""
    @Published private(set) var lastLine: String = ""
    @Published private(set) var hazardLevel: String = "none"
    @Published private(set) var errorMessage: String?

    // ───── Tuning constants (match Android) ─────

    private let captureInterval: TimeInterval = 2.0
    private let sceneRepeatInterval: TimeInterval = 12.0
    private let pathHistorySize = 3
    private let pathSimilarityThreshold = 0.75

    // ───── Capture pipeline ─────

    private let captureWorker = CaptureSessionWorker()
    private var captureTimer: Timer?
    private var aiBusy = false
    private var aiTask: Task<Void, Never>?
    private var locationTask: Task<Void, Never>?

    // ───── Inputs (mutable so the View can re-apply user settings at
    //   each Start without having to rebuild the @StateObject). ─────

    private var arabic: Bool
    private var useGps: Bool

    /// Re-apply user settings before a fresh start(). Has no effect
    /// while a session is already running.
    func configure(arabic: Bool, useGps: Bool) {
        guard !isRunning else { return }
        self.arabic = arabic
        self.useGps = useGps
    }

    // ───── Rolling state ─────

    private var recentSummaries: [String] = []
    private var recentSpokenPaths: [String] = []
    private var lastSpokenPath = ""
    private var lastSceneSpokenAt: Date = .distantPast
    private var locationLabel: String?

    init(arabic: Bool, useGps: Bool) {
        self.arabic = arabic
        self.useGps = useGps
        super.init()
    }

    // ───── Public API ─────

    /// Start the guidance loop. Idempotent. Posts an error to
    /// errorMessage when the camera or Gemini key is unusable.
    func start() {
        guard !isRunning else { return }
        guard AiProviderFactory.isConfigured else {
            errorMessage = arabic
                ? "أكمل إعداد اتصال الذكاء الاصطناعي قبل بدء الوصف المباشر."
                : "Finish configuring the AI connection before starting live scene guidance."
            return
        }
        isRunning = true
        errorMessage = nil
        lastStatus = arabic ? "أفتح الكاميرا..." : "Opening camera..."
        locationTask?.cancel()
        if useGps {
            locationTask = Task { [weak self] in
                await self?.fetchLocationOnce()
            }
        }
        captureWorker.start { [weak self] errorCode in
            Task { @MainActor in
                guard let self else { return }
                guard self.isRunning else {
                    self.captureWorker.stop()
                    return
                }
                if let errorCode { self.fail(errorCode) }
                else { self.startCaptureTimer() }
            }
        }
    }

    /// Stop the loop. Idempotent.
    func stop() {
        guard isRunning else { return }
        isRunning = false
        captureTimer?.invalidate()
        captureTimer = nil
        captureWorker.stop()
        aiTask?.cancel()
        aiTask = nil
        locationTask?.cancel()
        locationTask = nil
        aiBusy = false
        recentSummaries.removeAll()
        recentSpokenPaths.removeAll()
        lastSpokenPath = ""
        lastSceneSpokenAt = .distantPast
        hazardLevel = "none"
        lastStatus = arabic ? "توقف الوصف المباشر." : "Live description stopped."
    }

    // ───── AVCaptureSession setup ─────

    private func startCaptureTimer() {
        lastStatus = arabic ? "الوصف المباشر يعمل الآن." : "Live description is running."
        captureTimer?.invalidate()
        // Fire immediately, then every captureInterval.
        triggerCapture()
        captureTimer = Timer.scheduledTimer(
            withTimeInterval: captureInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.triggerCapture() }
        }
    }

    private func triggerCapture() {
        guard isRunning else { return }
        // Skip when a previous frame's AI call is still in flight —
        // mirrors the aiBusy compareAndSet on Android.
        if aiBusy { return }
        captureWorker.capture { [weak self] data in
            Task { @MainActor in self?.onJpegReady(data) }
        }
    }

    private func onJpegReady(_ jpeg: Data?) {
        guard isRunning, let jpeg else { return }
        aiBusy = true
        aiTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.aiBusy = false
                self.aiTask = nil
            }
            guard let prepared = await Task.detached(priority: .userInitiated, operation: {
                ImagePreprocessor.jpeg(from: jpeg, maxLongEdge: 1_280, quality: 0.72)
            }).value, self.isRunning, !Task.isCancelled else { return }
            await self.sendToAi(jpeg: prepared)
        }
    }

    // ───── Gemini round trip ─────

    private func sendToAi(jpeg: Data) async {
        do {
            let context = GeminiPrompts.liveSceneGuidanceInput(
                recentSummaries: snapshotRecentSummaries(),
                locationLabel: locationLabel)
            // Route through the configured provider so Proxy mode
            // works too. The Direct provider switches to JSON mode
            // internally when it sees task == .liveScene; the Proxy
            // provider passes the prompt through verbatim and the
            // upstream server / Gemini still returns a JSON string.
            let text = try await AiProviderFactory.current().ask(
                task: .liveScene,
                input: context,
                instruction: GeminiPrompts.liveSceneGuidanceInstruction,
                language: arabic ? .arabic : .english,
                imageData: jpeg,
                mimeType: "image/jpeg")
            guard isRunning, !Task.isCancelled else { return }
            let trimmed = stripJsonFence(text)
            guard let data = trimmed.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data)
                            as? [String: Any] else {
                throw GeminiError.decode("liveScene response was not JSON")
            }
            handleResponse(obj)
        } catch {
            if Task.isCancelled || !isRunning { return }
            // Silent skip: a single failed frame should not break the
            // session — the next one in 2 seconds usually succeeds.
            let mapped = UserFriendlyErrorMapper.map(error)
            lastStatus = (arabic
                          ? "تعذّر تحليل لقطة: "
                          : "Could not analyze frame: ") + Self.shortError(mapped)
        }
    }

    /// Strip ```json fences when an upstream proxy doesn't honour
    /// JSON mode and Gemini wraps the object in markdown. The Direct
    /// path already returns bare JSON via responseFormat, so this
    /// is a no-op there.
    private func stripJsonFence(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("```") {
            if let firstNewline = t.firstIndex(of: "\n") {
                t = String(t[t.index(after: firstNewline)...])
            }
            if t.hasSuffix("```") { t = String(t.dropLast(3)) }
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func handleResponse(_ resp: [String: Any]) {
        let hazardObj = resp["hazard"] as? [String: Any] ?? [:]
        let rawLevel = ((hazardObj["level"] as? String) ?? "none").lowercased()
        let level = ["stop", "caution", "none"].contains(rawLevel) ? rawLevel : "none"
        let hazardDesc = boundedLine(hazardObj["description"] as? String, maxCharacters: 220)
        let path = boundedLine(resp["path"] as? String, maxCharacters: 160)
        let scene = boundedLine(resp["scene"] as? String, maxCharacters: 160)

        // Update rolling summary so the next prompt can say "don't repeat".
        let summary = "hazard=\(level) path=\"\(path)\""
            + (scene.isEmpty ? "" : " scene=\"\(scene)\"")
        recentSummaries.append(summary)
        if recentSummaries.count > 3 { recentSummaries.removeFirst() }

        // Haptics
        fireHaptic(forLevel: level)

        // Priority-based speech (hazard always; path filtered; scene rare).
        var toSpeak: String? = nil
        let hazardActive = (level.lowercased() == "stop"
                            || level.lowercased() == "caution")
                            && !hazardDesc.isEmpty
        if hazardActive {
            toSpeak = hazardDesc
        } else if !path.isEmpty
                  && path.lowercased() != lastSpokenPath.lowercased()
                  && !isNearDuplicatePath(path) {
            toSpeak = path
            lastSpokenPath = path
            recordSpokenPath(path)
        } else if !scene.isEmpty
                  && Date().timeIntervalSince(lastSceneSpokenAt) > sceneRepeatInterval {
            toSpeak = scene
            lastSceneSpokenAt = Date()
        }

        self.hazardLevel = level
        let statusText = arabic
            ? "آخر وصف: " + (path.isEmpty ? "—" : path)
            : "Last description: " + (path.isEmpty ? "—" : path)
        self.lastStatus = statusText
        if let spoken = toSpeak {
            self.lastLine = spoken
            SpeechSynthesizer.shared.speak(spoken, utteranceId: "live_scene")
            ArchiveStore.shared.appendLog(type: "live_scene", content: spoken)
        }
    }


    /// Proxy responses are not guaranteed to honour Gemini's response schema.
    /// Collapse whitespace and cap text before it reaches TTS, logs, or the
    /// rolling prompt so malformed output cannot create an unbounded loop.
    private func boundedLine(_ value: String?, maxCharacters: Int) -> String {
        let compact = (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#,
                                  with: " ",
                                  options: .regularExpression)
        return String(compact.prefix(maxCharacters))
    }

    // ───── Haptics (mirrors Android's vibrateForLevel) ─────

    private func fireHaptic(forLevel level: String) {
        switch level.lowercased() {
        case "stop":
            // Three discrete impacts ~120 ms apart so the user can
            // distinguish the count even through clothing / a pocket.
            let gen = UIImpactFeedbackGenerator(style: .heavy)
            gen.prepare()
            gen.impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { gen.impactOccurred() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) { gen.impactOccurred() }
        case "caution":
            // Two medium impacts.
            let gen = UIImpactFeedbackGenerator(style: .medium)
            gen.prepare()
            gen.impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { gen.impactOccurred() }
        default:
            break
        }
    }

    // ───── Levenshtein-based dedup (mirrors Android v3.2) ─────

    private func recordSpokenPath(_ path: String) {
        recentSpokenPaths.append(path)
        while recentSpokenPaths.count > pathHistorySize {
            recentSpokenPaths.removeFirst()
        }
    }

    private func isNearDuplicatePath(_ candidate: String) -> Bool {
        let norm = normalise(candidate)
        guard !norm.isEmpty else { return false }
        for past in recentSpokenPaths {
            let pn = normalise(past)
            guard !pn.isEmpty else { continue }
            let dist = Self.levenshtein(norm, pn)
            let maxLen = max(norm.count, pn.count)
            let similarity = 1.0 - Double(dist) / Double(maxLen)
            if similarity >= pathSimilarityThreshold { return true }
        }
        return false
    }

    private func normalise(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
         .lowercased()
         .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private static func levenshtein(_ a: String, _ b: String) -> Int {
        if a == b { return 0 }
        let aChars = Array(a); let bChars = Array(b)
        if aChars.isEmpty { return bChars.count }
        if bChars.isEmpty { return aChars.count }
        // Keep the inner buffer along the shorter side.
        let (s, t) = aChars.count <= bChars.count
            ? (aChars, bChars) : (bChars, aChars)
        let n = s.count; let m = t.count
        var prev = [Int](0...n)
        var curr = [Int](repeating: 0, count: n + 1)
        for i in 1...m {
            curr[0] = i
            let bi = t[i - 1]
            for j in 1...n {
                let cost = s[j - 1] == bi ? 0 : 1
                curr[j] = min(min(curr[j - 1] + 1, prev[j] + 1),
                              prev[j - 1] + cost)
            }
            swap(&prev, &curr)
        }
        return prev[n]
    }

    // ───── GPS one-shot + reverse geocode ─────

    private func fetchLocationOnce() async {
        let loc = await LocationService.shared.fetchOnce()
        guard isRunning, !Task.isCancelled, let loc else { return }
        let geocoder = CLGeocoder()
        let placemarks = try? await geocoder.reverseGeocodeLocation(loc)
        guard isRunning, !Task.isCancelled else { return }
        let label: String = {
            if let p = placemarks?.first {
                let joined = [p.thoroughfare, p.subLocality, p.locality, p.country]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                    .joined(separator: ", ")
                if !joined.isEmpty { return joined }
            }
            return String(format: "%.4f,%.4f",
                          loc.coordinate.latitude, loc.coordinate.longitude)
        }()
        guard isRunning, !Task.isCancelled else { return }
        locationLabel = label
        locationTask = nil
        lastStatus = (arabic ? "أُضيف الموقع إلى الوصف: " : "Location added to descriptions: ") + label
    }

    // ───── Helpers ─────

    private func snapshotRecentSummaries() -> String {
        if recentSummaries.isEmpty { return "(none)" }
        return recentSummaries.enumerated()
            .map { "\($0.offset + 1)) \($0.element)" }
            .joined(separator: "\n")
    }

    private func fail(_ code: String) {
        isRunning = false
        captureTimer?.invalidate()
        captureTimer = nil
        switch code {
        case "camera_denied":
            errorMessage = arabic
                ? "لم يُسمح بالوصول إلى الكاميرا. فعّل الإذن من إعدادات iPhone."
                : "Camera access is not allowed. Enable it in iPhone Settings."
        case "camera_open_failed":
            errorMessage = arabic
                ? "لم أتمكن من فتح الكاميرا على هذا الجهاز."
                : "I couldn't open the camera on this device."
        default:
            errorMessage = arabic
                ? "تعذّر تشغيل الوصف المباشر. أغلق الشاشة وافتحها، ثم أعد المحاولة."
                : "Live description could not start. Close this screen, reopen it, and try again."
        }
        lastStatus = arabic ? "توقف الوصف بسبب خطأ." : "Live description stopped because of an error."
    }

    private static func shortError(_ s: String) -> String {
        s.count > 80 ? String(s.prefix(80)) + "…" : s
    }
}

// MARK: - PhotoDelegate

/// AVCapturePhotoOutput only holds the delegate weakly, so we own
/// it from the controller for the duration of each capture.
private final class PhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private let onJpeg: @Sendable (Data?) -> Void
    init(onJpeg: @escaping @Sendable (Data?) -> Void) { self.onJpeg = onJpeg }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        onJpeg(photo.fileDataRepresentation())
    }
}
#endif
