import SwiftUI

/// A full read-only summary: the health score, the device snapshot, and every
/// recorded result with its outcome, summary and metrics. Records nothing.
/// Exports a PDF via `ReportService` and shares it with `ShareLink`.
struct ReportView: View {
    @EnvironmentObject private var store: DiagnosticsStore

    @State private var snapshot = DeviceIdentity.snapshot()
    @State private var exportURL: URL?

    private var scoreTint: Color {
        switch store.healthScore {
        case 80...:   return .green
        case 50..<80: return .orange
        default:      return .red
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                scoreCard
                snapshotCard

                ForEach(store.orderedResults) { result in
                    resultCard(result)
                }
            }
            .padding(Theme.screenPadding)
        }
        .navigationTitle("التقرير الكامل")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let url = exportURL {
                    ShareLink(item: url) {
                        Label("مشاركة", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityLabel("مشاركة تقرير PDF")
                } else {
                    Button {
                        exportURL = ReportService().makePDF(
                            snapshot: snapshot,
                            results: store.orderedResults,
                            healthScore: store.healthScore
                        )
                    } label: {
                        Label("تصدير PDF", systemImage: "doc.badge.arrow.up")
                    }
                    .accessibilityLabel("تصدير التقرير كملف PDF")
                }
            }
        }
    }

    // MARK: - Cards

    private var scoreCard: some View {
        Card {
            HStack(spacing: 20) {
                ZStack {
                    Circle().stroke(.quaternary, lineWidth: 12)
                    Circle()
                        .trim(from: 0, to: CGFloat(store.healthScore) / 100)
                        .stroke(scoreTint, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(store.healthScore)")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                        Text("من 100").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 96, height: 96)

                VStack(alignment: .leading, spacing: 6) {
                    Text("درجة صحة الجهاز").font(.headline)
                    Text("اكتمل \(store.completedCount) من \(store.totalCount) فحصًا")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("درجة صحة الجهاز \(store.healthScore) من 100، اكتمل \(store.completedCount) من \(store.totalCount) فحصًا")
    }

    private var snapshotCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("معلومات الجهاز").font(.headline)
                infoRow("الجهاز", snapshot.marketingName)
                infoRow("المعرّف", snapshot.modelIdentifier)
                infoRow("نظام التشغيل", "\(snapshot.systemName) \(snapshot.systemVersion)")
                infoRow("تاريخ التقرير", snapshot.generatedAt.formatted(date: .abbreviated, time: .shortened))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    private func resultCard(_ result: TestResult) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: result.category.systemImage)
                        .foregroundStyle(.tint)
                    Text(result.category.titleAr).font(.headline)
                    Spacer()
                    Label(result.outcome.titleAr, systemImage: result.outcome.systemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(result.outcome.color)
                        .labelStyle(.titleAndIcon)
                }

                if !result.summaryAr.isEmpty {
                    Text(result.summaryAr)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if !result.metrics.isEmpty {
                    Divider()
                    ForEach(result.metrics) { metric in
                        HStack {
                            Text(metric.label).foregroundStyle(.secondary)
                            Spacer()
                            Text(metric.value).fontWeight(.medium)
                        }
                        .font(.caption)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(metric.label): \(metric.value)")
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(result.category.titleAr)، الحالة: \(result.outcome.titleAr)")
    }
}
