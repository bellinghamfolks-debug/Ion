import SwiftUI

struct ReportView: View {
    @EnvironmentObject private var store: DiagnosticsStore
    @State private var textURL: URL?
    @State private var pdfURL: URL?
    @State private var jsonURL: URL?
    @State private var exportError: String?

    var body: some View {
        List {
            Section("ملخص الجلسة") {
                valueRow("الجهاز", store.session.device.marketingName)
                valueRow("الإصدار", "\(store.session.device.systemName) \(store.session.device.systemVersion)")
                valueRow("الفحوص المكتملة", "\(store.completedCount) من \(store.totalCount)")
                valueRow("المؤشر الحالي", store.healthScore.map { "\($0) من 100" } ?? "غير محسوب")
            }

            Section("تصدير قابل للوصول") {
                exportRow(
                    title: "تقرير نصي",
                    detail: "الأنسب لقارئ الشاشة",
                    icon: "doc.plaintext",
                    url: textURL
                ) { textURL = try ReportService().makeText(session: store.session) }

                exportRow(
                    title: "تقرير PDF",
                    detail: "للطباعة والمشاركة الرسمية",
                    icon: "doc.richtext",
                    url: pdfURL
                ) { pdfURL = try ReportService().makePDF(session: store.session) }

                exportRow(
                    title: "بيانات JSON",
                    detail: "نسخة تقنية قابلة للنقل",
                    icon: "curlybraces",
                    url: jsonURL
                ) { jsonURL = try ReportService().makeJSON(session: store.session) }
            }

            Section("تفاصيل الفحوصات") {
                ForEach(TestCategory.allCases) { category in
                    resultDisclosure(category)
                }
            }

            Section {
                TestDisclaimer()
                Text("لا تدخل الفحوص غير المنفذة أو غير القابلة للفحص في حساب المؤشر.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("التقرير")
        .navigationBarTitleDisplayMode(.inline)
        .alert("تعذر التصدير", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("حسنًا", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }

    private func valueRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label)، \(value)")
    }

    @ViewBuilder
    private func exportRow(
        title: String,
        detail: String,
        icon: String,
        url: URL?,
        generate: @escaping () throws -> Void
    ) -> some View {
        if let url {
            ShareLink(item: url) {
                Label {
                    VStack(alignment: .leading) {
                        Text("مشاركة \(title)")
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
            .accessibilityHint("يفتح قائمة مشاركة الملف")
        } else {
            Button {
                do { try generate() }
                catch { exportError = error.localizedDescription }
            } label: {
                Label {
                    VStack(alignment: .leading) {
                        Text("إنشاء \(title)")
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: icon)
                }
            }
        }
    }

    private func resultDisclosure(_ category: TestCategory) -> some View {
        let result = store.result(for: category)
        return DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                if !result.summaryAr.isEmpty { Text(result.summaryAr) }
                Text("مصدر النتيجة: \(result.evidence.titleAr)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(result.metrics) { MetricRow(metric: $0) }
                if let limitation = result.limitationAr {
                    Text("حدود الفحص: \(limitation)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if result.outcome != .notRun {
                    Button("مسح نتيجة هذا الفحص", role: .destructive) {
                        store.clear(category)
                    }
                }
            }
            .padding(.vertical, 8)
        } label: {
            HStack {
                Text(category.titleAr)
                Spacer()
                OutcomeBadge(outcome: result.outcome)
            }
        }
    }
}
