import SwiftUI

/// Live camera test: shows a preview, lets the user switch front/back and toggle
/// the back-camera flash, then self-assess pass/fail. Records `.camera`.
struct CameraTestView: View {
    @EnvironmentObject private var store: DiagnosticsStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = CameraController()

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                switch camera.permission {
                case .denied:
                    PermissionDeniedCard(
                        systemImage: "camera.fill",
                        message: "لا يمكن الوصول إلى الكاميرا. فعّل إذن الكاميرا من الإعدادات لإجراء الفحص.")
                default:
                    previewSection
                    controlsSection
                    PassFailControls(onPass: { record(.pass) },
                                     onFail: { record(.fail) })
                }
            }
            .padding(Theme.screenPadding)
        }
        .navigationTitle(TestCategory.camera.titleAr)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { camera.requestAccessAndStart() }
        .onDisappear { camera.stop() }
    }

    // MARK: Sections

    private var previewSection: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .fill(Color.black)
            CameraPreview(session: camera.session)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
            if !camera.isRunning {
                ProgressView()
                    .tint(.white)
            }
        }
        .frame(height: 380)
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.25), value: camera.side)
        .accessibilityElement()
        .accessibilityLabel("معاينة الكاميرا المباشرة")
        .accessibilityValue(camera.side == .back ? "الكاميرا الخلفية" : "الكاميرا الأمامية")
    }

    private var controlsSection: some View {
        Card {
            VStack(spacing: 14) {
                Button {
                    withAnimation { camera.toggleSide() }
                } label: {
                    Label(camera.side == .back ? "التبديل إلى الأمامية" : "التبديل إلى الخلفية",
                          systemImage: "arrow.triangle.2.circlepath.camera")
                        .frame(maxWidth: .infinity, minHeight: 30)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityLabel("تبديل الكاميرا")
                .accessibilityHint(camera.side == .back
                                   ? "التبديل إلى الكاميرا الأمامية"
                                   : "التبديل إلى الكاميرا الخلفية")

                if camera.hasTorch {
                    Button {
                        camera.toggleTorch()
                    } label: {
                        Label(camera.torchOn ? "إطفاء الفلاش" : "تشغيل الفلاش",
                              systemImage: camera.torchOn ? "bolt.slash.fill" : "bolt.fill")
                            .frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(camera.torchOn ? .yellow : .accentColor)
                    .controlSize(.large)
                    .accessibilityLabel(camera.torchOn ? "إطفاء الفلاش" : "تشغيل الفلاش")
                    .accessibilityHint("الفلاش متاح على الكاميرا الخلفية فقط")
                } else {
                    Text("الفلاش متاح على الكاميرا الخلفية فقط")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("الفلاش غير متاح على الكاميرا الحالية")
                }
            }
        }
    }

    // MARK: Recording

    private func record(_ outcome: TestOutcome) {
        let side = camera.side == .back ? "الخلفية" : "الأمامية"
        let result = TestResult(
            category: .camera,
            outcome: outcome,
            summaryAr: outcome == .pass
                ? "المعاينة والفلاش يعملان كما هو متوقع."
                : "أبلغ المستخدم عن مشكلة في الكاميرا أو الفلاش.",
            metrics: [
                .init(label: "الكاميرا المُختبرة", value: side),
                .init(label: "الفلاش", value: camera.hasTorch ? "متاح" : "غير متاح")
            ])
        store.record(result)
        camera.stop()
        dismiss()
    }
}
