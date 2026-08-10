import SwiftUI
import AVFoundation
import CoreGraphics

/// Accessible camera surface designed around three channels: live image for
/// low-vision users, concise speech for VoiceOver, and directional haptics.
struct CameraView: View {
    @StateObject private var coordinator = FrameGuidanceCoordinator()
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var captured: CGImage?
    @State private var capturedLevel = LevelReading(rollDegrees: 0, pitchDegrees: 0)
    @State private var capturedAnalysis: FrameAnalysis?
    @State private var showReview = false

    private var isLowVisionMode: Bool { settings.interfaceMode == "Low Vision" }

    var body: some View {
        ZStack {
            CameraPreview(session: coordinator.camera.session)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            LinearGradient(
                colors: [.black.opacity(0.68), .clear, .black.opacity(0.78)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 16) {
                topStatus
                Spacer()
                guidanceCard
                bottomControls
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 18)
        }
        .onAppear(perform: startCamera)
        .onDisappear { coordinator.stop() }
        .onChange(of: coordinator.cameraError) { _, message in
            guard let message, !message.isEmpty else { return }
            let spoken = settings.isArabic ? localizedCameraError(message) : message
            coordinator.feedback.speak(spoken, interrupt: true)
        }
        .fullScreenCover(isPresented: $showReview) {
            if let image = captured {
                ReviewView(image: image,
                           capturedLevel: capturedLevel,
                           analysis: capturedAnalysis)
                    .environmentObject(settings)
            }
        }
    }

    private var topStatus: some View {
        HStack(spacing: 10) {
            Image(systemName: coordinator.cameraReady ? "camera.fill" : "hourglass")
                .font(.headline)
                .accessibilityHidden(true)

            Text(coordinator.cameraReady
                 ? settings.t("Camera ready")
                 : settings.t("Camera starting"))
                .font(.headline)

            Spacer()

            Button {
                coordinator.announceStatus()
            } label: {
                Image(systemName: "level")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(settings.t("Check alignment"))
            .accessibilityHint(settings.t("Speaks the most important adjustment."))
        }
        .foregroundStyle(.white)
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(.black.opacity(0.48), in: Capsule())
    }

    private var guidanceCard: some View {
        VStack(spacing: 8) {
            Text(coordinator.guidanceText)
                .font(isLowVisionMode ? .largeTitle.weight(.bold) : .title2.weight(.bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(coordinator.guidanceText)
                .accessibilityAddTraits(.updatesFrequently)

            if settings.autoCapture {
                Label(settings.t("Auto capture is on"), systemImage: "sparkles")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.88))
                    .accessibilityLabel(settings.t("Auto capture is on"))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var bottomControls: some View {
        HStack(alignment: .center, spacing: 28) {
            roundControl(systemImage: "xmark", label: settings.t("Close")) {
                coordinator.stop()
                dismiss()
            }

            captureButton

            roundControl(systemImage: "speaker.wave.2.fill", label: settings.t("Check alignment")) {
                coordinator.announceStatus()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var captureButton: some View {
        Button(action: captureCurrentFrame) {
            ZStack {
                Circle()
                    .fill(.white)
                    .frame(width: isLowVisionMode ? 88 : 76, height: isLowVisionMode ? 88 : 76)
                Circle()
                    .stroke(.white.opacity(0.55), lineWidth: 3)
                    .frame(width: isLowVisionMode ? 102 : 88, height: isLowVisionMode ? 102 : 88)
                Circle()
                    .stroke(.black.opacity(0.7), lineWidth: 2)
                    .frame(width: isLowVisionMode ? 78 : 68, height: isLowVisionMode ? 78 : 68)
            }
        }
        .disabled(!coordinator.cameraReady)
        .opacity(coordinator.cameraReady ? 1 : 0.55)
        .accessibilityLabel(settings.t("Capture"))
        .accessibilityValue(captureAccessibilityValue)
        .accessibilityHint(settings.t("Takes the photo. You will hear a quality report."))
    }

    private var captureAccessibilityValue: String {
        guard coordinator.cameraReady else { return settings.t("Camera starting") }
        return coordinator.level.isLevel
            ? settings.t("Camera is level")
            : settings.t("Camera is tilted")
    }

    private func roundControl(systemImage: String,
                              label: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .frame(width: 52, height: 52)
                .background(.black.opacity(0.5), in: Circle())
                .foregroundStyle(.white)
        }
        .accessibilityLabel(label)
    }

    private func startCamera() {
        coordinator.verbosity = settings.verbosity
        coordinator.autoCaptureEnabled = settings.autoCapture
        coordinator.feedback.hapticFirst = settings.hapticFirst
        coordinator.language = settings.effectiveCode
        coordinator.camera.onPhoto = handlePhoto

        // Auto capture must snapshot the exact analysis that caused the capture.
        // The old implementation captured the photo but left review metadata at
        // its initial zero/nil values.
        coordinator.onAutoCapture = captureCurrentFrame
        coordinator.start()
    }

    private func captureCurrentFrame() {
        guard coordinator.cameraReady else {
            coordinator.feedback.speak(settings.t("Camera starting"), interrupt: true)
            return
        }
        capturedLevel = coordinator.level
        capturedAnalysis = coordinator.latestAnalysis
        coordinator.camera.capturePhoto()
    }

    private func handlePhoto(_ image: CGImage?, _ metadata: [String: Any]?) {
        guard let image else {
            coordinator.feedback.speak(settings.t("Capture failed. Try again."), interrupt: true)
            return
        }
        coordinator.feedback.play(.captured)
        captured = image
        showReview = true
    }

    private func localizedCameraError(_ english: String) -> String {
        switch english {
        case "Camera access is required to take photos.": return "يحتاج التطبيق إلى إذن الكاميرا لالتقاط الصور."
        case "Camera access is disabled. Enable it in Settings.": return "الوصول إلى الكاميرا متوقف. فعّله من إعدادات الآيفون."
        case "The camera is not ready yet.": return "الكاميرا لم تجهز بعد."
        case "Capture failed. Try again.": return "تعذر التقاط الصورة. حاول مرة أخرى."
        case "The captured image could not be decoded.": return "تعذر فتح الصورة بعد التقاطها."
        default: return settings.t("Camera error. Try again.")
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {}

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        override func layoutSubviews() {
            super.layoutSubviews()
            updatePreviewOrientation()
        }

        private func updatePreviewOrientation() {
            guard let interfaceOrientation = window?.windowScene?.interfaceOrientation,
                  let connection = previewLayer.connection,
                  connection.isVideoOrientationSupported else {
                return
            }

            switch interfaceOrientation {
            case .portrait:
                connection.videoOrientation = .portrait
            case .portraitUpsideDown:
                connection.videoOrientation = .portraitUpsideDown
            case .landscapeLeft:
                connection.videoOrientation = .landscapeLeft
            case .landscapeRight:
                connection.videoOrientation = .landscapeRight
            default:
                break
            }
        }
    }
}
