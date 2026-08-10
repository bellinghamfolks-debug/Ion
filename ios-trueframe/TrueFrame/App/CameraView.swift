import SwiftUI
import AVFoundation
import CoreGraphics

/// The accessible camera. A blind user hears one prioritized instruction at a
/// time and feels leveling haptics; the big capture button announces readiness.
struct CameraView: View {
    @StateObject private var coordinator = FrameGuidanceCoordinator()
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var captured: CGImage?
    @State private var capturedLevel = LevelReading(rollDegrees: 0, pitchDegrees: 0)
    @State private var capturedAnalysis: FrameAnalysis?
    @State private var showReview = false

    var body: some View {
        ZStack {
            CameraPreview(session: coordinator.camera.session)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            VStack {
                // Live guidance — large, high contrast, and a VoiceOver live region.
                Text(coordinator.guidanceText)
                    .font(.title.weight(.bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding()
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 16))
                    .padding(.top, 24)
                    .accessibilityLabel(coordinator.guidanceText)
                    .accessibilityAddTraits(.updatesFrequently)

                Spacer()

                HStack(spacing: 24) {
                    controlButton(settings.t("Is it level?"), systemImage: "level") {
                        coordinator.announceStatus()
                    }
                    captureButton
                    controlButton(settings.t("Close"), systemImage: "xmark") {
                        coordinator.stop(); dismiss()
                    }
                }
                .padding(.bottom, 28)
            }
        }
        .onAppear {
            coordinator.verbosity = settings.verbosity
            coordinator.autoCaptureEnabled = settings.autoCapture
            coordinator.feedback.hapticFirst = settings.hapticFirst
            coordinator.language = settings.effectiveCode
            coordinator.camera.onPhoto = handlePhoto
            coordinator.onAutoCapture = { coordinator.camera.capturePhoto() }
            coordinator.start()
        }
        .onDisappear { coordinator.stop() }
        .fullScreenCover(isPresented: $showReview) {
            if let cg = captured {
                ReviewView(image: cg, capturedLevel: capturedLevel, analysis: capturedAnalysis)
                    .environmentObject(settings)
            }
        }
    }

    private var captureButton: some View {
        Button {
            capturedLevel = coordinator.level
            capturedAnalysis = coordinator.latestAnalysis
            coordinator.camera.capturePhoto()
        } label: {
            ZStack {
                Circle().fill(.white).frame(width: 78, height: 78)
                Circle().stroke(.black, lineWidth: 2).frame(width: 88, height: 88)
            }
        }
        .accessibilityLabel(settings.t("Capture"))
        .accessibilityValue(coordinator.level.isLevel ? settings.t("Camera is level") : settings.t("Camera is tilted"))
        .accessibilityHint(settings.t("Takes the photo. You will hear a quality report."))
    }

    private func controlButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title2)
                .padding(16)
                .background(.black.opacity(0.5), in: Circle())
                .foregroundStyle(.white)
        }
        .accessibilityLabel(title)
    }

    private func handlePhoto(_ cg: CGImage?, _ meta: [String: Any]?) {
        guard let cg else {
            coordinator.feedback.speak(settings.t("Capture failed. Try again."), interrupt: true)
            return
        }
        coordinator.feedback.play(.captured)
        captured = cg
        showReview = true
    }
}

/// AVCaptureVideoPreviewLayer bridged into SwiftUI.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let v = PreviewUIView()
        v.previewLayer.session = session
        v.previewLayer.videoGravity = .resizeAspectFill
        return v
    }
    func updateUIView(_ uiView: PreviewUIView, context: Context) {}

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
