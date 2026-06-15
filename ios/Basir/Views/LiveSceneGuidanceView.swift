import SwiftUI

struct LiveSceneGuidanceView: View {
    @StateObject private var controller = LiveSceneGuidanceController(
        arabic: BasirSettings.shared.language == .arabic,
        useGps: false
    )
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("live_scene_use_gps") private var useGps = false

    var body: some View {
        BasirScreen {
            BasirStatusBanner(
                text: L10n.t(
                    "الوصف المباشر قد يتأخر أو يخطئ. لا تستخدمه وحده لعبور الطرق أو الدرج، واستمر في استخدام العصا أو وسيلة التنقل المعتادة.",
                    "Live description may be delayed or wrong. Never use it alone for roads or stairs, and keep using your cane or usual mobility aid."
                ),
                tone: .warning,
                title: L10n.t("تنبيه سلامة", "Safety notice")
            )

            statusCard
            lastLineCard

            if let error = controller.errorMessage {
                BasirStatusBanner(text: error, tone: .danger)
            }

            Toggle(isOn: $useGps) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.t("استخدام الموقع التقريبي", "Use approximate location"))
                        .font(.body.weight(.medium))
                    Text(L10n.t("قد يساعد في فهم نوع المكان، ولا يوفّر ملاحة أو توجيهًا دقيقًا.",
                                 "May help identify the type of place, but does not provide navigation or precise guidance."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(controller.isRunning)
            .basirCardSurface()

            primaryButton

            BasirPageIntro(
                text: L10n.t(
                    "تعمل الكاميرا ما دام بصير ظاهرًا على الشاشة. تتوقف الجلسة عند قفل الشاشة أو الانتقال إلى تطبيق آخر.",
                    "The camera runs only while Basir is visible. The session stops when the screen locks or you switch apps."
                ),
                tone: .neutral
            )
        }
        .navigationTitle(L10n.t("الوصف المباشر", "Live scene description"))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { controller.stop() }
        }
        .onDisappear { controller.stop() }
    }

    private var statusCard: some View {
        HStack(spacing: 14) {
            Image(systemName: controller.isRunning ? "dot.radiowaves.left.and.right" : "pause.circle.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(statusColor)
                .frame(width: 52, height: 52)
                .background(statusColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 15))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.t("الحالة", "Status"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(controller.lastStatus.isEmpty
                     ? L10n.t("جاهز للبدء", "Ready to start")
                     : controller.lastStatus)
                    .font(.headline)
                    .foregroundStyle(statusColor)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            Spacer()
        }
        .basirCardSurface()
        .accessibilityElement(children: .combine)
    }

    private var lastLineCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L10n.t("آخر وصف منطوق", "Last spoken description"),
                  systemImage: "speaker.wave.2.fill")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
            Text(controller.lastLine.isEmpty
                 ? L10n.t("لم يبدأ الوصف بعد.", "No description yet.")
                 : controller.lastLine)
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.updatesFrequently)
        }
        .basirCardSurface()
    }

    @ViewBuilder
    private var primaryButton: some View {
        if controller.isRunning {
            Button(role: .destructive) { controller.stop() } label: {
                Label(L10n.t("إيقاف الوصف وإغلاق الكاميرا", "Stop description and close camera"),
                      systemImage: "stop.circle.fill")
            }
            .buttonStyle(BasirPrimaryButtonStyle(tone: .danger))
        } else {
            Button {
                controller.configure(
                    arabic: BasirSettings.shared.language == .arabic,
                    useGps: useGps
                )
                controller.start()
            } label: {
                Label(L10n.t("بدء الوصف المباشر", "Start live description"),
                      systemImage: "play.circle.fill")
            }
            .buttonStyle(BasirPrimaryButtonStyle(tone: .success))
        }
    }

    private var statusColor: Color {
        switch controller.hazardLevel.lowercased() {
        case "stop": return .red
        case "caution": return .orange
        default: return controller.isRunning ? .green : .secondary
        }
    }
}
