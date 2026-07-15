import SwiftUI
import LocalAuthentication

/// The `.biometrics` diagnostic: reports the enrolled biometry type and lets the
/// user run an authentication. When no biometrics are enrolled/available it is
/// recorded honestly as `.unsupported`.
struct BiometricsTestView: View {
    @EnvironmentObject private var store: DiagnosticsStore
    @StateObject private var hardware = HardwareService()

    @State private var isAuthenticating = false
    @State private var lastResultAr: String?
    @State private var lastSucceeded = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                typeCard

                if hardware.biometricsAvailable {
                    authCard
                } else {
                    unavailableCard
                }

                if let lastResultAr {
                    Card {
                        HStack(spacing: 12) {
                            Image(systemName: lastSucceeded
                                  ? TestOutcome.pass.systemImage
                                  : TestOutcome.fail.systemImage)
                                .foregroundStyle(lastSucceeded ? TestOutcome.pass.color : TestOutcome.fail.color)
                                .accessibilityHidden(true)
                            Text(lastResultAr).font(.subheadline.weight(.semibold))
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(lastResultAr)
                }
            }
            .padding(Theme.screenPadding)
        }
        .navigationTitle(TestCategory.biometrics.titleAr)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            hardware.refreshBiometry()
            if !hardware.biometricsAvailable { recordUnsupported() }
        }
    }

    private var biometryIcon: String {
        switch hardware.biometryType {
        case .faceID:  return "faceid"
        case .touchID: return "touchid"
        default:       return "person.crop.circle.badge.questionmark"
        }
    }

    private var typeCard: some View {
        Card {
            HStack(spacing: 16) {
                Image(systemName: biometryIcon)
                    .font(.largeTitle)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("نوع المصادقة المكتشف").font(.subheadline).foregroundStyle(.secondary)
                    Text(hardware.biometryTypeAr).font(.title2.weight(.bold))
                }
                Spacer()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("نوع المصادقة المكتشف: \(hardware.biometryTypeAr)")
    }

    private var authCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("اضغط للتحقق من عمل \(hardware.biometryTypeAr)")
                    .font(.headline)
                PrimaryButton(title: isAuthenticating ? "جارٍ التحقق..." : "بدء المصادقة",
                              systemImage: "lock.open") {
                    runAuthentication()
                }
                .disabled(isAuthenticating)
            }
        }
    }

    private var unavailableCard: some View {
        Card {
            HStack(spacing: 14) {
                Image(systemName: TestOutcome.unsupported.systemImage)
                    .font(.title)
                    .foregroundStyle(TestOutcome.unsupported.color)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("المصادقة البيومترية غير متاحة").font(.headline)
                    Text("لا يوجد Face ID أو Touch ID مُفعّل أو مُسجَّل على هذا الجهاز")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("المصادقة البيومترية غير متاحة. لا يوجد Face ID أو Touch ID مُفعّل أو مُسجَّل على هذا الجهاز")
    }

    private func runAuthentication() {
        isAuthenticating = true
        Task {
            let success = await hardware.authenticate()
            isAuthenticating = false
            lastSucceeded = success
            lastResultAr = success ? "نجحت المصادقة البيومترية" : "فشلت المصادقة أو أُلغيت"
            if success { recordPass() }
        }
    }

    private func recordPass() {
        let result = TestResult(
            category: .biometrics,
            outcome: .pass,
            summaryAr: "نجحت المصادقة باستخدام \(hardware.biometryTypeAr)",
            metrics: [.init(label: "النوع", value: hardware.biometryTypeAr)]
        )
        store.record(result)
    }

    private func recordUnsupported() {
        let result = TestResult(
            category: .biometrics,
            outcome: .unsupported,
            summaryAr: "لا تتوفر مصادقة بيومترية مُسجَّلة على هذا الجهاز",
            metrics: [.init(label: "النوع", value: hardware.biometryTypeAr)]
        )
        store.record(result)
    }
}
