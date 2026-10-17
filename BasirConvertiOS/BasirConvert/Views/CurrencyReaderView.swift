import AVFoundation
import CoreML
import SwiftUI
import UIKit
import Vision

/// Currency reader: point the camera at a Saudi riyal note and hear its value.
///
/// Everything runs on the iPhone: no picture leaves it and it works offline.
/// A small model names the note several times a second, the note's printed
/// number is read as text, and ``CurrencyVoter`` speaks only when both agree
/// over consecutive frames — for someone who cannot check the answer, silence
/// is better than a wrong value.
struct CurrencyReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var l10n: L10n
    @StateObject private var reader = CurrencyReaderController()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CurrencyCameraPreview(session: reader.session)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            VStack(spacing: BasirSpacing.m) {
                Spacer()
                VStack(spacing: BasirSpacing.s) {
                    Text(reader.headline)
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    Text(reader.guidance)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                    if reader.summing {
                        Text(l10n.t("المجموع: \(RiyalAmount.arabic(reader.total))", "Total: \(RiyalAmount.english(reader.total))"))
                            .font(.title2.weight(.bold))
                    }
                }
                .foregroundStyle(.white)
                .padding(BasirSpacing.l)
                .frame(maxWidth: .infinity)
                .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 24))
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.updatesFrequently)

                HStack(spacing: BasirSpacing.m) {
                    controlButton(reader.summing ? l10n.t("إيقاف الجمع", "Stop counting")
                                                 : l10n.t("بدء الجمع", "Start counting"),
                                  systemImage: reader.summing ? "sum" : "plus.forwardslash.minus") {
                        reader.toggleSumming()
                    }
                    if reader.summing {
                        controlButton(l10n.t("تصفير المجموع", "Reset total"), systemImage: "arrow.counterclockwise") {
                            reader.resetTotal()
                        }
                    }
                    controlButton(reader.torchOn ? l10n.t("إطفاء الإضاءة", "Turn off light") : l10n.t("تشغيل الإضاءة", "Turn on light"),
                                  systemImage: reader.torchOn ? "flashlight.off.fill" : "flashlight.on.fill") {
                        reader.toggleTorch()
                    }
                }
                Button {
                    reader.stop()
                    dismiss()
                } label: {
                    Text(l10n.t("إغلاق", "Close"))
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .tint(BasirPalette.accent)
            }
            .padding(BasirSpacing.l)
        }
        .onAppear { reader.start(l10n: l10n) }
        .onDisappear { reader.stop() }
        .accessibilityAction(.escape) {
            reader.stop()
            dismiss()
        }
    }

    private func controlButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.bordered)
        .tint(.white)
    }
}

/// Camera, recognition, speech and haptics.
@MainActor
final class CurrencyReaderController: NSObject, ObservableObject {
    @Published var headline = ""
    @Published var guidance = ""
    @Published var torchOn = false
    @Published var summing = false
    @Published var total = 0

    nonisolated let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private nonisolated let queue = DispatchQueue(label: "com.basir.currency-reader")
    private nonisolated let textQueue = DispatchQueue(label: "com.basir.currency-reader.text")
    private nonisolated(unsafe) var lastFrame = Date.distantPast
    private nonisolated(unsafe) var lastText = Date.distantPast
    private nonisolated(unsafe) var readingText = false
    private nonisolated(unsafe) var textPass = 0
    private nonisolated(unsafe) var printed: (values: Set<RiyalNote>, time: Date) = ([], .distantPast)
    private nonisolated(unsafe) var model: VNCoreMLModel?
    private var voter = CurrencyVoter()
    private var l10n: L10n?
    private let speech = AVSpeechSynthesizer()
    private var configured = false
    private var darkSince: Date?
    private var lastGuidance = Date.distantPast
    private var autoTorch = false

    /// The trained model, compiled into the app. The printed number alone
    /// is never enough (prices and receipts carry the same numbers).
    nonisolated static func loadModel() -> VNCoreMLModel? {
        guard let url = Bundle.main.url(forResource: "RiyalClassifier", withExtension: "mlmodelc"),
              let model = try? MLModel(contentsOf: url) else { return nil }
        return try? VNCoreMLModel(for: model)
    }

    func start(l10n: L10n) {
        self.l10n = l10n
        headline = l10n.t("قارئ العملات", "Currency reader")
        guidance = l10n.t("أمسك الورقة النقدية أمام الكاميرا، على بُعد شبر تقريبًا.",
                          "Hold the banknote about 20 cm in front of the camera.")
        announce(guidance)
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in granted ? self.configureAndRun() : self.denied() }
            }
        default:
            denied()
        }
    }

    func stop() {
        setTorch(false)
        speech.stopSpeaking(at: .immediate)
        let session = self.session
        queue.async { if session.isRunning { session.stopRunning() } }
    }

    func toggleTorch() {
        autoTorch = false
        setTorch(!torchOn)
    }

    func toggleSumming() {
        summing.toggle()
        if summing { total = 0 }
        voter.reshowGap = summing ? 2 : 1
        announce(summing ? (l10n?.t("بدأ الجمع. ضع الأوراق أمام الكاميرا، واحدة تلو الأخرى.",
                                    "Counting started. Hold the banknotes in front of the camera, one at a time.") ?? "")
                         : (l10n?.t("توقّف الجمع. المجموع: \(RiyalAmount.arabic(total)).",
                                    "Counting stopped. Total: \(RiyalAmount.english(total)).") ?? ""))
    }

    func resetTotal() {
        total = 0
        announce(l10n?.t("المجموع الآن صفر.", "The total is now zero.") ?? "")
    }

    private func denied() {
        guidance = l10n?.t("للسماح لبصير باستخدام الكاميرا، افتح إعدادات iPhone وفعّل إذن الكاميرا لبصير، ثم حاول مجددًا.",
                           "Open iPhone Settings and allow Basir to access the camera, then try again.") ?? ""
        announce(guidance)
    }

    private func configureAndRun() {
        if !configured {
            configured = true
            session.beginConfiguration()
            session.sessionPreset = .hd1280x720
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else {
                session.commitConfiguration()
                guidance = l10n?.t("تعذّر تشغيل الكاميرا. حاول مجددًا.", "Couldn’t start the camera. Please try again.") ?? ""
                announce(guidance)
                return
            }
            session.addInput(input)
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String:
                                            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(self, queue: queue)
            if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
            session.commitConfiguration()
            if (try? device.lockForConfiguration()) != nil {
                if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
                if device.isAutoFocusRangeRestrictionSupported { device.autoFocusRangeRestriction = .near }
                device.unlockForConfiguration()
            }
        }
        let session = self.session
        queue.async { [weak self] in
            if self?.model == nil { self?.model = Self.loadModel() }
            let loaded = self?.model != nil
            if !session.isRunning { session.startRunning() }
            if !loaded {
                Task { @MainActor in
                    guard let self else { return }
                    self.guidance = self.l10n?.t("تعذّر تشغيل الكاميرا. حاول مجددًا.", "Couldn’t start the camera. Please try again.") ?? ""
                    self.announce(self.guidance)
                }
            }
        }
    }

    private func setTorch(_ on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
            torchOn = on
        } catch { }
    }

    // MARK: Decisions (main actor)

    fileprivate func handle(_ observation: CurrencyObservation, brightness: Double) {
        handleLight(brightness)
        guard let verdict = voter.add(observation) else { return }
        switch verdict {
        case .note(let note):
            guard let l10n else { return }
            var spoken = note.spoken(l10n)
            if summing {
                total += note.rawValue
                spoken += l10n.t(". المجموع: \(RiyalAmount.arabic(total))", ". Total: \(RiyalAmount.english(total))")
            }
            headline = note.spoken(l10n)
            guidance = l10n.t("ضع ورقة أخرى أمام الكاميرا، أو اقلب الورقة إلى الوجه الآخر.",
                              "Hold another banknote in front of the camera, or turn this one over.")
            announce(spoken, interrupt: true)
            tap(note.hapticTaps)
        case .uncertain:
            guard Date().timeIntervalSince(lastGuidance) > 4, let l10n else { return }
            lastGuidance = Date()
            guidance = l10n.t("قرّب الورقة قليلًا وثبّتها أمام الكاميرا.", "Move the banknote a little closer and hold it still.")
            announce(guidance)
        case .nothing:
            break
        }
    }

    private func handleLight(_ brightness: Double) {
        let dark = brightness < 0.18
        if dark {
            darkSince = darkSince ?? Date()
            if !torchOn, let since = darkSince, Date().timeIntervalSince(since) > 1.5 {
                autoTorch = true
                setTorch(true)
                announce(l10n?.t("شُغّلت الإضاءة تلقائيًا لأن المكان مظلم.", "The light turned on automatically because it’s dark.") ?? "")
            }
        } else {
            darkSince = nil
        }
    }

    private func announce(_ text: String, interrupt: Bool = false) {
        guard !text.isEmpty else { return }
        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .announcement, argument: text)
            return
        }
        if interrupt { speech.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: l10n?.isArabic == false ? "en-US" : "ar-SA")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        speech.speak(utterance)
    }

    /// One tap for 1 riyal up to eight for 500, so the value can be felt.
    private func tap(_ count: Int) {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.prepare()
        for index in 0..<count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18 * Double(index)) { generator.impactOccurred() }
        }
    }
}

extension CurrencyReaderController: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        let now = Date()
        guard now.timeIntervalSince(lastFrame) >= 0.2,
              let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrame = now
        let brightness = Self.brightness(pixels)

        var note: RiyalNote?
        var confidence = 0.0
        if let model {
            let request = VNCoreMLRequest(model: model)
            request.imageCropAndScaleOption = .centerCrop
            try? VNImageRequestHandler(cvPixelBuffer: pixels, orientation: .right).perform([request])
            if let best = (request.results as? [VNClassificationObservation])?.first {
                note = RiyalNote(label: best.identifier)
                confidence = Double(best.confidence)
            }
        }
        // The printed number, read less often (it is slower), kept for a second
        // and a half. Alternate passes read the frame upside down, for a note
        // held the other way up.
        if now.timeIntervalSince(lastText) >= 0.4, !readingText {
            lastText = now
            readingText = true
            textPass += 1
            let orientation: CGImagePropertyOrientation = textPass % 2 == 0 ? .left : .right
            let copy = pixels
            textQueue.async { [weak self] in
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = false
                request.recognitionLanguages = Self.textLanguages
                try? VNImageRequestHandler(cvPixelBuffer: copy, orientation: orientation).perform([request])
                // Text cut by the frame's edge may be part of a bigger number ("50" of "500").
                let lines = (request.results ?? []).filter { Self.inside($0.boundingBox) }
                    .compactMap { $0.topCandidates(1).first?.string }
                self?.printed = (PrintedValue.notes(in: lines), Date())
                self?.readingText = false
            }
        }
        let printedNow = now.timeIntervalSince(printed.time) < 1.5 ? printed.values : []
        let observation = CurrencyObservation(note: note, confidence: confidence, printed: printedNow,
                                              time: now.timeIntervalSinceReferenceDate)
        Task { @MainActor in self.handle(observation, brightness: brightness) }
    }

    /// Arabic and English where this iOS reads them; an unsupported language
    /// would make every request fail.
    nonisolated static let textLanguages: [String] = {
        let supported = (try? VNRecognizeTextRequest().supportedRecognitionLanguages()) ?? []
        let wanted = ["ar-SA", "en-US"].filter(supported.contains)
        return wanted.isEmpty ? ["en-US"] : wanted
    }()

    nonisolated static func inside(_ box: CGRect) -> Bool {
        box.minX > 0.015 && box.minY > 0.015 && box.maxX < 0.985 && box.maxY < 0.985
    }

    /// Average of the luma plane, sampled sparsely: 0 is black, 1 is white.
    nonisolated static func brightness(_ pixels: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        guard CVPixelBufferGetPlaneCount(pixels) > 0,
              let base = CVPixelBufferGetBaseAddressOfPlane(pixels, 0) else { return 1 }
        let width = CVPixelBufferGetWidthOfPlane(pixels, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixels, 0)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(pixels, 0)
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        var sum = 0, count = 0
        for y in Swift.stride(from: 0, to: height, by: 24) {
            for x in Swift.stride(from: 0, to: width, by: 24) {
                sum += Int(bytes[y * stride + x])
                count += 1
            }
        }
        return count == 0 ? 1 : Double(sum) / Double(count) / 255
    }
}

/// The camera feed, for anyone who can see it; hidden from VoiceOver.
private struct CurrencyCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) { }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
