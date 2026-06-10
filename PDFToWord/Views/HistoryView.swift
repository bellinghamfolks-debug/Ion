import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        NavigationStack {
            Group {
                if appModel.records.isEmpty {
                    ContentUnavailableView(
                        L10n.text("لا توجد تحويلات"),
                        systemImage: "doc.text.magnifyingglass",
                        description: Text(L10n.text("ستظهر هنا الملفات المكتملة والتحويلات التي يمكن استئنافها."))
                    )
                } else {
                    List {
                        ForEach(appModel.records) { record in
                            recordRow(record)
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    Button(L10n.text("حذف"), role: .destructive) {
                                        appModel.deleteRecord(record)
                                    }
                                }
                        }
                    }
                    .refreshable { appModel.refreshRecords() }
                }
            }
            .navigationTitle(L10n.text("سجل التحويل"))
        }
    }

    @ViewBuilder
    private func recordRow(_ record: ConversionJobRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Image(systemName: icon(for: record.status))
                    .foregroundStyle(color(for: record.status))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(record.sourceName)
                        .font(.headline)
                    Text(record.status.localizedTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(record.createdAt, format: .dateTime.day().month().year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: record.progress)
                .accessibilityLabel(L10n.format("تقدم الملف: %@", record.sourceName))
                .accessibilityValue(L10n.format("الصفحات المكتملة: %d من %d", record.completedPages, record.totalPages))

            Text(L10n.format("الصفحات المكتملة: %d من %d", record.completedPages, record.totalPages))
                .font(.caption)
                .foregroundStyle(.secondary)

            if let model = record.optionsSnapshot?.model {
                Text(L10n.format("النموذج المحفوظ للمهمة: %@", model))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if record.status == .completed, let byteCount = record.outputByteCount {
                Text(L10n.format(
                    "حجم Word المتحقق منه: %@",
                    ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let minimumQuality = record.minimumQualityScore {
                Text(L10n.format("أدنى درجة قبول داخلية: %d%%", Int(minimumQuality * 100)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !record.normalizedHandwrittenPages.isEmpty {
                Text(L10n.format(
                    "صفحات خط يدوي أو مختلط: %@",
                    L10n.pageList(record.normalizedHandwrittenPages)
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if !record.normalizedFallbackPages.isEmpty {
                Text(L10n.format(
                    "صفحات بالنص المحلي: %@",
                    L10n.pageList(record.normalizedFallbackPages)
                ))
                .font(.caption)
                .foregroundStyle(.orange)
            }

            if !record.normalizedWarnings.isEmpty {
                DisclosureGroup(L10n.format("تحذيرات الجودة: %d", record.normalizedWarnings.count)) {
                    ForEach(record.normalizedWarnings, id: \.self) { warning in
                        Text(warning)
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                }
            }

            if let error = record.errorMessage, record.status == .failed || record.status == .cancelled {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            HStack {
                if record.status != .completed {
                    Button {
                        appModel.resume(record, options: settings.options)
                    } label: {
                        Label(L10n.text("استئناف"), systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appModel.isConverting)
                    .accessibilityHint(record.optionsSnapshot == nil
                        ? L10n.text("يستأنف المهمة القديمة ويثبت الإعدادات الحالية")
                        : L10n.text("يستأنف باستخدام إعدادات المهمة المحفوظة"))
                }

                if let output = appModel.outputURL(for: record) {
                    ShareLink(item: output) {
                        Label(L10n.text("مشاركة"), systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }

    private func icon(for status: JobStatus) -> String {
        switch status {
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .cancelled: return "pause.circle.fill"
        case .building: return "doc.badge.gearshape"
        default: return "arrow.triangle.2.circlepath"
        }
    }

    private func color(for status: JobStatus) -> Color {
        switch status {
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .orange
        default: return .accentColor
        }
    }
}
