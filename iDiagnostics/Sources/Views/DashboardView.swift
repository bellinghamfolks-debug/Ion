import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: DiagnosticsStore
    @State private var showResetConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    summaryCard
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section("الفحوصات") {
                    ForEach(TestCategory.allCases) { category in
                        NavigationLink(value: category) {
                            testRow(category)
                        }
                    }
                }

                Section("النتائج") {
                    NavigationLink {
                        ReportView()
                    } label: {
                        Label("التقرير والتصدير", systemImage: "doc.text.magnifyingglass")
                    }
                }

                Section {
                    TestDisclaimer()
                    Label("لا يرسل التطبيق نتائجك أو تسجيلاتك إلى أي خادم.", systemImage: "lock.shield.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("الخصوصية والدقة")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("فحص الآيفون")
            .navigationDestination(for: TestCategory.self) { category in
                DiagnosticDestinationView(category: category)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("جلسة جديدة", role: .destructive) {
                        showResetConfirmation = true
                    }
                }
            }
            .confirmationDialog(
                "بدء جلسة جديدة؟",
                isPresented: $showResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("مسح النتائج الحالية", role: .destructive) {
                    store.startNewSession()
                }
                Button("إلغاء", role: .cancel) {}
            } message: {
                Text("سيبدأ تقرير جديد. لا يمكن استعادة النتائج الحالية بعد المسح.")
            }
        }
    }

    private var summaryCard: some View {
        DiagnosticCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 14) {
                    ZStack {
                        Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 9)
                        Circle()
                            .trim(from: 0, to: store.progress)
                            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(store.completedCount)/\(store.totalCount)")
                            .font(.headline.monospacedDigit())
                    }
                    .frame(width: 84, height: 84)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("اكتمل \(store.completedCount) من \(store.totalCount) فحصًا")

                    VStack(alignment: .leading, spacing: 5) {
                        Text(store.session.device.marketingName)
                            .font(.title3.bold())
                        Text("\(store.session.device.systemName) \(store.session.device.systemVersion)")
                            .foregroundStyle(.secondary)
                        if let score = store.healthScore {
                            Text("المؤشر الحالي: \(score) من 100")
                                .font(.headline)
                        } else {
                            Text("ابدأ فحصًا لإظهار المؤشر")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let next = TestCategory.allCases.first(where: { !store.result(for: $0).outcome.isCompleted }) {
                    NavigationLink(value: next) {
                        Label("الفحص التالي: \(next.titleAr)", systemImage: "play.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Label("اكتملت جميع الفحوصات", systemImage: "checkmark.seal.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(.horizontal, AppTheme.screenPadding)
        .padding(.vertical, 8)
    }

    private func testRow(_ category: TestCategory) -> some View {
        let result = store.result(for: category)
        return HStack(spacing: 13) {
            Image(systemName: category.systemImage)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 34)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(category.titleAr).font(.headline)
                Text(category.subtitleAr)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            OutcomeBadge(outcome: result.outcome)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(category.titleAr)، \(category.subtitleAr)، النتيجة: \(result.outcome.titleAr)")
        .accessibilityHint("اضغط مرتين لفتح الفحص")
    }
}

private struct DiagnosticDestinationView: View {
    let category: TestCategory

    @ViewBuilder
    var body: some View {
        switch category {
        case .system: SystemInfoTestView()
        case .display: DisplayTestView()
        case .multiTouch: MultiTouchTestView()
        case .sensors: MotionTestView()
        case .connectivity: ConnectivityTestView()
        case .camera: CameraTestView()
        case .microphone: MicrophoneTestView()
        case .speaker: SpeakerTestView()
        case .haptics: HapticsTestView()
        case .buttons: ButtonsTestView()
        case .biometrics: BiometricsTestView()
        }
    }
}
