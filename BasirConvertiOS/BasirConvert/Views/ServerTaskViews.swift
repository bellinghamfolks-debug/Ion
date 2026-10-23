import SwiftUI

/// Long summaries and natural-style texts in the Tasks tab: every unfinished
/// one, with its progress, and the ones finished in the last week, which open
/// their result. They stay here until they end, whatever happens to Basir.
struct ServerTasksSection: View {
    @EnvironmentObject private var l10n: L10n
    @EnvironmentObject private var settings: SettingsStore
    @ObservedObject private var center = ServerTaskCenter.shared
    @Binding var open: ServerTask?

    var body: some View {
        Section {
            ForEach(center.visible) { task in
                row(task)
            }
        } header: {
            Text(l10n.t("التلخيص وتحرير الأسلوب", "Summaries and style editing"))
                .font(.title3.weight(.bold))
                .foregroundStyle(BasirPalette.primaryText)
                .textCase(nil)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private func row(_ task: ServerTask) -> some View {
        Button { open = task } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .top) {
                    Image(systemName: icon(task))
                        .foregroundStyle(color(task))
                        .accessibilityHidden(true)
                    Text(task.title)
                        .font(.headline)
                        .foregroundStyle(BasirPalette.primaryText)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(status(task))
                    .font(.subheadline)
                    .foregroundStyle(BasirPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if task.isActive, task.total > 0 {
                    ProgressView(value: Double(task.percent), total: 100).tint(BasirPalette.accent)
                }
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(task.title)
        .accessibilityValue(status(task))
        .accessibilityAction(named: l10n.t("فتح", "Open")) { open = task }
        .listRowBackground(BasirPalette.surface)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if task.isActive {
                Button(role: .destructive) { center.cancel(task.id, configuration: settings.configuration) } label: {
                    Label(l10n.t("إلغاء المهمة", "Cancel task"), systemImage: "xmark")
                }
            } else {
                if task.state == .failed {
                    Button { center.retry(task.id, configuration: settings.configuration, l10n: l10n) } label: {
                        Label(l10n.t("إعادة المحاولة", "Try again"), systemImage: "arrow.clockwise")
                    }
                    .tint(.green)
                }
                Button(role: .destructive) { center.remove(task.id) } label: {
                    Label(l10n.t("إزالة من القائمة", "Remove from the list"), systemImage: "trash")
                }
            }
        }
        .modifier(ServerTaskActions(task: task))
    }

    private func status(_ task: ServerTask) -> String {
        switch task.state {
        case .sending:
            return task.detail.isEmpty ? l10n.t("جارٍ الإرسال", "Sending") : task.detail
        case .working:
            let detail = task.detail.isEmpty ? l10n.t("يعمل عليها الخادم", "The server is working on it") : task.detail
            return task.total > 0 ? "\(detail) · \(task.percent)٪" : detail
        case .finished:
            return l10n.t("مكتملة · اضغط لفتحها", "Done · tap to open")
        case .failed:
            return RestyleRunner.message(for: BasirError.conversionFailed(task.error ?? ""), l10n: l10n)
                + l10n.t(" · اسحب لإعادة المحاولة", " · swipe to try again")
        case .cancelled:
            return l10n.t("ملغاة", "Cancelled")
        }
    }

    private func icon(_ task: ServerTask) -> String {
        switch task.state {
        case .finished: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        case .cancelled: return "stop.circle.fill"
        default: return task.kind == .restyle ? "text.word.spacing" : "text.quote"
        }
    }

    private func color(_ task: ServerTask) -> Color {
        switch task.state {
        case .finished: return BasirPalette.success
        case .failed: return BasirPalette.danger
        case .cancelled: return BasirPalette.secondaryText
        default: return BasirPalette.accent
        }
    }
}

/// The same actions for VoiceOver as the swipe gives by touch.
private struct ServerTaskActions: ViewModifier {
    @EnvironmentObject private var l10n: L10n
    @EnvironmentObject private var settings: SettingsStore
    let task: ServerTask

    func body(content: Content) -> some View {
        let center = ServerTaskCenter.shared
        if task.isActive {
            content.accessibilityAction(named: l10n.t("إلغاء المهمة", "Cancel task")) {
                center.cancel(task.id, configuration: settings.configuration)
            }
        } else if task.state == .failed {
            content
                .accessibilityAction(named: l10n.t("إعادة المحاولة", "Try again")) {
                    center.retry(task.id, configuration: settings.configuration, l10n: l10n)
                }
                .accessibilityAction(named: l10n.t("إزالة من القائمة", "Remove from the list")) { center.remove(task.id) }
        } else {
            content.accessibilityAction(named: l10n.t("إزالة من القائمة", "Remove from the list")) { center.remove(task.id) }
        }
    }
}

/// What a task in the list opens: its result when done, its screen with the progress otherwise.
struct ServerTaskDestination: View {
    @EnvironmentObject private var l10n: L10n
    @Environment(\.dismiss) private var dismiss
    let task: ServerTask

    var body: some View {
        switch task.kind {
        case .restyle:
            if task.state == .finished, let entry = RestyleStore.entries().first(where: { $0.id == task.id }) {
                NavigationStack {
                    RestyleResultView(entry: entry)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button(l10n.t("إغلاق", "Close")) { dismiss() } }
                        }
                }
                .escapeToDismiss { dismiss() }
            } else {
                RestyleView()
                    .onAppear { RestyleRunner.shared.focus(task.id) }
            }
        case .summary:
            if let source = Self.summarySource(task) {
                SummaryView(source: source)
            } else {
                NavigationStack {
                    InlineMessage(text: l10n.t("افتح الملخص من الملف نفسه في «ملفاتي».", "Open the summary from the file itself in My Files."),
                                  isError: false)
                        .appScreenContent()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button(l10n.t("إغلاق", "Close")) { dismiss() } }
                        }
                }
            }
        }
    }

    /// The summary screen for the task's own document (its text was kept with the task).
    static func summarySource(_ task: ServerTask) -> SummarySource? {
        guard let data = ServerTaskStore.body(for: task.id), let home = task.summaryHome else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let body = try? decoder.decode(SummaryRequestBody.self, from: data) else { return nil }
        let summaryHome: SummaryHome
        var output: URL?
        if home.hasPrefix("output:"), let folder = try? FileAccess.outputDirectory() {
            output = folder.appendingPathComponent(String(home.dropFirst("output:".count)))
            summaryHome = .output(output!)
        } else if home.hasPrefix("key:") {
            summaryHome = .key(String(home.dropFirst("key:".count)))
        } else {
            return nil
        }
        return SummarySource(title: body.title, text: body.text, files: body.files, home: summaryHome, outputURL: output)
    }
}
