import SwiftUI
import UIKit
import AVFoundation
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

/// Photograph pages without seeing the screen: the camera looks for the page
/// and says where to move ("a little to the left", "closer"), taps gently,
/// and captures by itself once the whole page is in view and still. Each
/// captured page is straightened. Done combines the pages into one PDF.
struct GuidedCaptureView: View {
    let onFinish: ([URL]) -> Void
    let onCancel: () -> Void

    @EnvironmentObject private var l10n: L10n
    @StateObject private var camera = GuidedCaptureController()
    @AccessibilityFocusState private var instructionFocused: Bool

    var body: some View {
        ZStack {
            CameraPreview(session: camera.session)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            VStack(spacing: BasirSpacing.l) {
                Text(camera.statusText.isEmpty ? l10n.t("جارٍ تشغيل الكاميرا…", "Starting the camera…") : camera.statusText)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(BasirSpacing.l)
                    .frame(maxWidth: .infinity)
                    .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .accessibilityAddTraits(.updatesFrequently)
                    .accessibilityFocused($instructionFocused)
                Text(l10n.t("الصفحات الملتقطة: \(camera.pages.count)", "Pages captured: \(camera.pages.count)"))
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, BasirSpacing.l)
                    .padding(.vertical, BasirSpacing.s)
                    .background(.black.opacity(0.55), in: Capsule())
                Spacer()
                if let error = camera.errorText {
                    InlineMessage(text: error, isError: true)
                }
                AdaptiveStack(spacing: BasirSpacing.m) {
                    captureButton(l10n.t("التقط الآن", "Capture now"), systemImage: "camera.shutter.button") {
                        camera.captureNow()
                    }
                    captureButton(camera.torchOn ? l10n.t("إطفاء الإضاءة", "Light off") : l10n.t("تشغيل الإضاءة", "Light on"),
                                  systemImage: camera.torchOn ? "flashlight.off.fill" : "flashlight.on.fill") {
                        camera.toggleTorch()
                    }
                }
                AdaptiveStack(spacing: BasirSpacing.m) {
                    captureButton(l10n.t("إلغاء", "Cancel"), systemImage: "xmark") {
                        camera.stop()
                        onCancel()
                    }
                    captureButton(l10n.t("تم (\(camera.pages.count))", "Done (\(camera.pages.count))"),
                                  systemImage: "checkmark", prominent: true) {
                        camera.stop()
                        onFinish(camera.pages)
                    }
                    .disabled(camera.pages.isEmpty)
                }
            }
            .padding(BasirSpacing.l)
        }
        .background(Color.black.ignoresSafeArea())
        .environment(\.layoutDirection, l10n.layoutDirection)
        .onAppear {
            camera.start(l10n: l10n)
            instructionFocused = true
        }
        .onDisappear { camera.stop() }
        .accessibilityAction(.escape) {
            camera.stop()
            onCancel()
        }
    }

    private func captureButton(_ title: String, systemImage: String, prominent: Bool = false,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 56)
                .foregroundStyle(prominent ? BasirPalette.onAccent : .white)
                .background(prominent ? BasirPalette.accent : Color.black.opacity(0.65),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// The camera, the page detector and the speech. Detection runs a few times
/// a second on a background queue; everything the person hears or sees is
/// published on the main actor.
@MainActor
final class GuidedCaptureController: NSObject, ObservableObject {
    @Published var statusText = ""
    @Published var pages: [URL] = []
    @Published var torchOn = false
    @Published var errorText: String?

    nonisolated let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private nonisolated let queue = DispatchQueue(label: "com.basir.guided-capture")
    private var stabilizer = CaptureStabilizer()
    private var l10n: L10n?
    private let speech = AVSpeechSynthesizer()
    private var capturing = false
    private var configured = false
    private nonisolated(unsafe) var lastAnalysis = Date.distantPast

    func start(l10n: L10n) {
        self.l10n = l10n
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    if granted { self.configureAndRun() } else { self.denied() }
                }
            }
        default:
            denied()
        }
    }

    private func denied() {
        errorText = l10n?.t("اسمح لبصير باستخدام الكاميرا من إعدادات iPhone ثم أعد المحاولة.",
                            "Allow Basir to use the camera in iPhone Settings, then try again.")
        announce(errorText ?? "")
    }

    private func configureAndRun() {
        if !configured {
            configured = true
            session.beginConfiguration()
            session.sessionPreset = .photo
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else {
                session.commitConfiguration()
                errorText = l10n?.t("تعذر تشغيل الكاميرا.", "The camera could not start.")
                return
            }
            session.addInput(input)
            if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(self, queue: queue)
            if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
            session.commitConfiguration()
        }
        let session = self.session
        queue.async { if !session.isRunning { session.startRunning() } }
        speak(.searching)
    }

    func stop() {
        setTorch(false)
        speech.stopSpeaking(at: .immediate)
        let session = self.session
        queue.async { if session.isRunning { session.stopRunning() } }
    }

    func toggleTorch() { setTorch(!torchOn) }

    private func setTorch(_ on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
            torchOn = on
        } catch { }
    }

    func captureNow() {
        guard !capturing else { return }
        capturing = true
        let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    fileprivate func handle(_ output: CaptureStabilizer.Output) {
        guard !capturing else { return }
        switch output {
        case .none: break
        case .speak(let instruction):
            speak(instruction)
        case .capture:
            speak(.ready)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            captureNow()
        }
    }

    fileprivate func update(quad: DocumentQuad?) {
        handle(stabilizer.update(quad: quad))
    }

    private func speak(_ instruction: CaptureInstruction) {
        guard let l10n else { return }
        statusText = instruction.spoken(l10n)
        switch instruction {
        case .ready, .holdSteady: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .searching: break
        default: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        announce(statusText)
    }

    private func announce(_ text: String) {
        guard !text.isEmpty else { return }
        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .announcement, argument: text)
        } else {
            speech.stopSpeaking(at: .word)
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: l10n?.isArabic == true ? "ar-SA" : "en-US")
            speech.speak(utterance)
        }
    }

    fileprivate func finishCapture(_ data: Data?) {
        defer {
            capturing = false
            stabilizer.reset()
        }
        guard let data, let image = PageStraightener.straightenedImage(from: data) else {
            errorText = l10n?.t("تعذر التقاط الصفحة. حاول مرة أخرى.", "The page could not be captured. Try again.")
            return
        }
        do {
            let urls = try MediaImport.persist([image], prefix: "صفحة \(pages.count + 1)")
            pages.append(contentsOf: urls)
            errorText = nil
            let text = l10n?.t("التُقطت الصفحة \(pages.count). وجّه الكاميرا إلى الصفحة التالية، أو اختر تم.",
                               "Page \(pages.count) captured. Point the camera at the next page, or choose Done.") ?? ""
            statusText = text
            announce(text)
        } catch {
            errorText = error.localizedDescription
        }
    }
}

extension GuidedCaptureController: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        let now = Date()
        guard now.timeIntervalSince(lastAnalysis) >= 0.15,
              let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastAnalysis = now
        // Back camera buffers are landscape; .right makes them upright (portrait).
        let quad = PageDetector.detect(in: pixels, orientation: .right)
        Task { @MainActor in self.update(quad: quad) }
    }
}

extension GuidedCaptureController: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        let data = error == nil ? photo.fileDataRepresentation() : nil
        Task { @MainActor in self.finishCapture(data) }
    }
}

/// Finds the page in an image with Vision's document segmentation.
enum PageDetector {
    static func detect(in pixels: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> DocumentQuad? {
        let request = VNDetectDocumentSegmentationRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixels, orientation: orientation, options: [:])
        try? handler.perform([request])
        return quad(from: request.results?.first)
    }

    static func detect(in image: CGImage) -> DocumentQuad? {
        let request = VNDetectDocumentSegmentationRequest()
        try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        return quad(from: request.results?.first)
    }

    /// Vision uses a bottom-left origin; guidance uses top-left.
    private static func quad(from observation: VNRectangleObservation?) -> DocumentQuad? {
        guard let observation, observation.confidence >= 0.5 else { return nil }
        func flip(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x, y: 1 - point.y) }
        return DocumentQuad(topLeft: flip(observation.topLeft), topRight: flip(observation.topRight),
                            bottomRight: flip(observation.bottomRight), bottomLeft: flip(observation.bottomLeft))
    }
}

/// Crops a photographed page to its edges and corrects the perspective, so
/// the server receives a flat, straight page.
enum PageStraightener {
    private static let context = CIContext()

    static func straightenedImage(from data: Data) -> UIImage? {
        guard let source = CIImage(data: data, options: [.applyOrientationProperty: true]),
              let full = context.createCGImage(source, from: source.extent) else { return nil }
        guard let quad = PageDetector.detect(in: full), quad.area > 0.15 else {
            return UIImage(cgImage: full)
        }
        let width = source.extent.width, height = source.extent.height
        // Back to Core Image's bottom-left pixel space.
        func pixel(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x * width, y: (1 - point.y) * height) }
        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = source
        filter.topLeft = pixel(quad.topLeft)
        filter.topRight = pixel(quad.topRight)
        filter.bottomRight = pixel(quad.bottomRight)
        filter.bottomLeft = pixel(quad.bottomLeft)
        guard let output = filter.outputImage,
              let corrected = context.createCGImage(output, from: output.extent) else {
            return UIImage(cgImage: full)
        }
        return UIImage(cgImage: corrected)
    }
}

/// Shows the camera feed (for anyone who can see it; hidden from VoiceOver).
private struct CameraPreview: UIViewRepresentable {
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
