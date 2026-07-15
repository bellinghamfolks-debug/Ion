import SwiftUI

/// The home screen: a health-score header and a grid of every diagnostic,
/// each showing its current outcome and linking to its test screen.
struct DashboardView: View {
    @EnvironmentObject private var store: DiagnosticsStore

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    HealthScoreHeader(score: store.healthScore,
                                      completed: store.completedCount,
                                      total: store.totalCount)

                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(TestCategory.allCases) { category in
                            NavigationLink {
                                destination(for: category)
                            } label: {
                                TestCardView(result: store.result(for: category))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    NavigationLink {
                        ReportView()
                    } label: {
                        Label("عرض التقرير الكامل", systemImage: "doc.text.fill")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity, minHeight: 34)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 4)
                }
                .padding(Theme.screenPadding)
            }
            .navigationTitle("تشخيص الآيفون")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("إعادة", systemImage: "arrow.counterclockwise") { store.reset() }
                        .accessibilityLabel("إعادة تعيين كل الفحوصات")
                }
            }
        }
    }

    @ViewBuilder
    private func destination(for category: TestCategory) -> some View {
        switch category {
        case .system:       SystemInfoView()
        case .display:      DisplayTestView()
        case .multiTouch:   MultiTouchTestView()
        case .sensors:      SensorTestView()
        case .connectivity: ConnectivityTestView()
        case .camera:       CameraTestView()
        case .microphone:   MicrophoneTestView()
        case .speaker:      SpeakerTestView()
        case .haptics:      HapticsTestView()
        case .buttons:      ButtonsTestView()
        case .biometrics:   BiometricsTestView()
        }
    }
}

/// The circular health-score gauge shown at the top of the dashboard.
struct HealthScoreHeader: View {
    let score: Int
    let completed: Int
    let total: Int

    private var tint: Color {
        switch score {
        case 80...: return .green
        case 50..<80: return .orange
        default: return .red
        }
    }

    var body: some View {
        Card {
            HStack(spacing: 20) {
                ZStack {
                    Circle().stroke(.quaternary, lineWidth: 12)
                    Circle()
                        .trim(from: 0, to: CGFloat(score) / 100)
                        .stroke(tint, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.6), value: score)
                    VStack(spacing: 0) {
                        Text("\(score)").font(.system(size: 30, weight: .bold, design: .rounded))
                        Text("من 100").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 96, height: 96)

                VStack(alignment: .leading, spacing: 6) {
                    Text("درجة صحة الجهاز").font(.headline)
                    Text(completed == 0 ? "ابدأ الفحوصات لتقييم جهازك"
                                        : "اكتمل \(completed) من \(total) فحصًا")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("درجة صحة الجهاز \(score) من 100، اكتمل \(completed) من \(total) فحصًا")
    }
}

/// One tappable diagnostic card in the dashboard grid.
struct TestCardView: View {
    let result: TestResult

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: result.category.systemImage)
                        .font(.title2)
                        .foregroundStyle(.tint)
                    Spacer()
                    Image(systemName: result.outcome.systemImage)
                        .foregroundStyle(result.outcome.color)
                        .accessibilityHidden(true)
                }
                Text(result.category.titleAr).font(.headline)
                Text(result.category.subtitleAr)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(result.outcome.titleAr)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(result.outcome.color)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(result.category.titleAr)، الحالة: \(result.outcome.titleAr)")
        .accessibilityHint(result.category.subtitleAr)
    }
}
