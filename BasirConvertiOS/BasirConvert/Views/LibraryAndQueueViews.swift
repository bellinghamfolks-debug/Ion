import SwiftUI

private enum LibrarySort: String, CaseIterable, Identifiable {
    case newest
    case oldest
    case name
    case size

    var id: String { rawValue }

    @MainActor
    func title(_ l10n: L10n) -> String {
        switch self {
        case .newest: return l10n.t("الأحدث أولًا", "Newest first")
        case .oldest: return l10n.t("الأقدم أولًا", "Oldest first")
        case .name: return l10n.t("بالاسم", "By name")
        case .size: return l10n.t("بالحجم", "By size")
        }
    }
}

struct ResultLibraryView: View {
    @EnvironmentObject private var l10n: L10n
    @EnvironmentObject private var library: OutputLibraryStore
    @State private var previewItem: OutputRecord?
    @State private var shareItem: OutputRecord?
    @State private var exportItem: OutputRecord?
    @State private var openItem: OutputRecord?
    @State private var renameItem: OutputRecord?
    @State private var deleteItem: OutputRecord?
    @State private var reportItem: OutputRecord?
    @State private var newName = ""
    @State private var query = ""
    @AppStorage("library_sort") private var sortRaw = LibrarySort.newest.rawValue

    private var sort: LibrarySort { LibrarySort(rawValue: sortRaw) ?? .newest }

    private var filtered: [OutputRecord] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = needle.isEmpty ? library.items : library.items.filter {
            $0.displayName.localizedCaseInsensitiveContains(needle)
                || ($0.sourceName?.localizedCaseInsensitiveContains(needle) ?? false)
        }
        switch sort {
        case .newest: return matches.sorted { $0.createdAt > $1.createdAt }
        case .oldest: return matches.sorted { $0.createdAt < $1.createdAt }
        case .name: return matches.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        case .size: return matches.sorted { $0.byteCount > $1.byteCount }
        }
    }

    private struct LibraryGroup: Identifiable {
        let id: String
        let title: String?
        let items: [OutputRecord]
    }

    /// Day groups when sorting by date; a single unnamed group otherwise.
    private var groups: [LibraryGroup] {
        let items = filtered
        guard sort == .newest || sort == .oldest else { return [LibraryGroup(id: "all", title: nil, items: items)] }
        let calendar = Calendar.current
        var order: [Date] = []
        var buckets: [Date: [OutputRecord]] = [:]
        for item in items {
            let day = calendar.startOfDay(for: item.createdAt)
            if buckets[day] == nil { order.append(day) }
            buckets[day, default: []].append(item)
        }
        return order.map {
            LibraryGroup(id: String($0.timeIntervalSince1970), title: dayTitle($0), items: buckets[$0] ?? [])
        }
    }

    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: BasirSpacing.m) {
                    Text(l10n.t("ملفاتي", "My files"))
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    if library.items.isEmpty {
                        InfoCard(
                            title: l10n.t("لا توجد نتائج بعد", "No results yet"),
                            text: l10n.t("ستظهر ملفات Word المكتملة هنا تلقائيًا.",
                                         "Completed Word files will appear here automatically."),
                            systemImage: "tray"
                        )
                    } else {
                        sortMenu
                        if filtered.isEmpty {
                            InfoCard(title: l10n.t("لا توجد نتائج مطابقة", "No matching files"),
                                     text: l10n.t("جرّب كلمة بحث أخرى.", "Try another search word."),
                                     systemImage: "magnifyingglass")
                        }
                        ForEach(groups) { group in
                            if let title = group.title { SectionHeading(title: title) }
                            ForEach(group.items) { item in resultCard(item) }
                        }
                    }
                    if let error = library.errorMessage { InlineMessage(text: error, isError: true) }
                }
                .appScreenContent(bottomPadding: 28)
            }
            .refreshable { library.refresh() }
        }
        .foregroundStyle(BasirPalette.primaryText)
        .navigationTitle(l10n.t("ملفاتي", "My files"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: l10n.t("ابحث في ملفاتك", "Search your files"))
        .onAppear { library.refresh() }
        .sheet(item: $previewItem) { QuickLookPreview(url: $0.url).ignoresSafeArea() }
        .sheet(item: $shareItem) { ActivityShareView(urls: [$0.url]) }
        .sheet(item: $exportItem) { ExportDocumentPicker(urls: [$0.url]) }
        .sheet(item: $openItem) { OpenInApplicationView(url: $0.url) }
        .sheet(item: $reportItem) { item in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: BasirSpacing.l) {
                        Text(item.displayName)
                            .font(.title3.weight(.bold))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        if let report = item.quality {
                            QualityReportCard(report: report)
                        }
                    }
                    .appScreenContent()
                }
                .background(BasirPalette.background.ignoresSafeArea())
                .navigationTitle(l10n.t("تقرير التحقق", "Verification report"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(l10n.t("تم", "Done")) { reportItem = nil }
                    }
                }
            }
            .escapeToDismiss { reportItem = nil }
            .presentationDetents([.medium, .large])
        }
        .alert(l10n.t("إعادة تسمية النتيجة", "Rename result"), isPresented: Binding(
            get: { renameItem != nil }, set: { if !$0 { renameItem = nil } }
        )) {
            TextField(l10n.t("اسم الملف", "File name"), text: $newName)
            Button(l10n.t("إلغاء", "Cancel"), role: .cancel) { renameItem = nil }
            Button(l10n.t("حفظ الاسم", "Save name")) {
                if let item = renameItem { _ = try? library.rename(item, to: newName) }
                renameItem = nil
            }
        }
        .confirmationDialog(
            l10n.t("حذف هذا الملف؟", "Delete this file?"),
            isPresented: Binding(get: { deleteItem != nil }, set: { if !$0 { deleteItem = nil } }),
            titleVisibility: .visible
        ) {
            Button(l10n.t("حذف نهائيًا", "Delete permanently"), role: .destructive) {
                if let item = deleteItem { try? library.delete(item) }
                deleteItem = nil
            }
            Button(l10n.t("إلغاء", "Cancel"), role: .cancel) { deleteItem = nil }
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker(l10n.t("الترتيب", "Sort"), selection: $sortRaw) {
                ForEach(LibrarySort.allCases) { Text($0.title(l10n)).tag($0.rawValue) }
            }
        } label: {
            Label(l10n.t("الترتيب: \(sort.title(l10n))", "Sort: \(sort.title(l10n))"),
                  systemImage: "arrow.up.arrow.down")
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
        }
        .tint(BasirPalette.accent)
    }

    private func resultCard(_ item: OutputRecord) -> some View {
        VStack(alignment: .leading, spacing: BasirSpacing.m) {
            Label(item.displayName, systemImage: "doc.richtext.fill")
                .font(.headline)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Text(metadataText(item))
                .font(.footnote)
                .foregroundStyle(BasirPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let quality = item.quality {
                Button { reportItem = item } label: { QualityBadge(report: quality) }
                    .buttonStyle(.plain)
            }
            AdaptiveStack {
                CardActionButton(title: l10n.t("معاينة", "Preview"), systemImage: "eye.fill", prominent: true) {
                    previewItem = item
                }
                CardActionButton(title: l10n.t("مشاركة", "Share"), systemImage: "square.and.arrow.up") {
                    shareItem = item
                }
            }
            AdaptiveStack {
                CardActionButton(title: l10n.t("حفظ في الملفات", "Save to Files"), systemImage: "folder.badge.plus") {
                    exportItem = item
                }
                Menu {
                    Button { openItem = item } label: {
                        Label(l10n.t("فتح باستخدام", "Open in app"), systemImage: "arrow.up.forward.app")
                    }
                    Button { beginRename(item) } label: {
                        Label(l10n.t("إعادة تسمية", "Rename"), systemImage: "pencil")
                    }
                    Button(role: .destructive) { deleteItem = item } label: {
                        Label(l10n.t("حذف", "Delete"), systemImage: "trash")
                    }
                } label: {
                    Label(l10n.t("المزيد", "More"), systemImage: "ellipsis.circle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .background(BasirPalette.accent.opacity(0.10),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .tint(BasirPalette.accent)
            }
        }
        .glassSurface()
        // VoiceOver: one stop per file. Double-tap previews; swipe up or down
        // for share, save, open, rename, delete, and the verification report.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.displayName)
        .accessibilityValue(accessibilitySummary(item))
        .accessibilityHint(l10n.t("اضغط مرتين للمعاينة. اسحب للأعلى أو للأسفل لبقية الإجراءات.",
                                  "Double-tap to preview. Swipe up or down for more actions."))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { previewItem = item }
        .accessibilityAction(named: l10n.t("معاينة", "Preview")) { previewItem = item }
        .accessibilityAction(named: l10n.t("مشاركة", "Share")) { shareItem = item }
        .accessibilityAction(named: l10n.t("حفظ في الملفات", "Save to Files")) { exportItem = item }
        .accessibilityAction(named: l10n.t("فتح باستخدام", "Open in app")) { openItem = item }
        .accessibilityAction(named: l10n.t("إعادة تسمية", "Rename")) { beginRename(item) }
        .accessibilityAction(named: l10n.t("حذف", "Delete")) { deleteItem = item }
        .modifier(ReportActionModifier(item: item, title: l10n.t("تقرير التحقق", "Verification report")) {
            reportItem = item
        })
    }

    private func beginRename(_ item: OutputRecord) {
        newName = item.displayName
        renameItem = item
    }

    private func accessibilitySummary(_ item: OutputRecord) -> String {
        var parts = [metadataText(item)]
        if let quality = item.quality {
            parts.append(quality.hasConcerns ? l10n.t("تم التحقق مع ملاحظات", "verified with notes")
                                             : l10n.t("تم التحقق من الجودة", "quality verified"))
        }
        return parts.joined(separator: l10n.isArabic ? "، " : ", ")
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return l10n.t("اليوم", "Today") }
        if calendar.isDateInYesterday(day) { return l10n.t("أمس", "Yesterday") }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(l10n.locale))
    }

    private func metadataText(_ item: OutputRecord) -> String {
        var parts = [item.humanReadableSize,
                     item.createdAt.formatted(.dateTime.hour().minute().locale(l10n.locale))]
        if let source = item.sourceName { parts.append(l10n.t("المصدر: \(source)", "Source: \(source)")) }
        if let count = item.itemCount { parts.append(l10n.t("العناصر: \(count)", "Items: \(count)")) }
        if let language = item.languageCode, language != "auto" {
            let value = SupportedLanguage.language(code: language).name(interface: l10n.language)
            parts.append(l10n.t("اللغة: \(value)", "Language: \(value)"))
        }
        return parts.joined(separator: " • ")
    }
}

/// Adds the verification-report action only to files that have a report.
private struct ReportActionModifier: ViewModifier {
    let item: OutputRecord
    let title: String
    let action: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if item.quality != nil {
            content.accessibilityAction(named: title, action)
        } else {
            content
        }
    }
}

struct JobQueueView: View {
    @EnvironmentObject private var l10n: L10n
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var pendingDeleteJobID: UUID?
    @State private var isReordering = false

    var body: some View {
        ZStack {
            AuroraBackground()
            if viewModel.jobs.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: BasirSpacing.m) {
                        Text(l10n.t("المهام", "Tasks"))
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .accessibilityAddTraits(.isHeader)
                        InfoCard(title: l10n.t("لا توجد مهام", "The queue is empty"),
                                 text: l10n.t("ابدأ مهمة من تبويب «جديد».",
                                              "Start a task from the New tab."),
                                 systemImage: "checklist")
                    }
                    .appScreenContent(bottomPadding: 28)
                }
            } else {
                List {
                    Section {
                        ForEach(viewModel.jobs) { job in
                            row(job)
                        }
                        .onMove(perform: viewModel.moveJobs)
                    } header: {
                        Text(l10n.t("المهام", "Tasks"))
                            .font(.title2.weight(.bold))
                            .foregroundStyle(BasirPalette.primaryText)
                            .textCase(nil)
                            .accessibilityAddTraits(.isHeader)
                    }
                }
                .scrollContentBackground(.hidden)
                .environment(\.editMode, .constant(isReordering ? .active : .inactive))
            }
        }
        .navigationTitle(l10n.t("المهام", "Tasks"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if viewModel.jobs.count > 1 {
                ToolbarItem(placement: .primaryAction) {
                    Button(isReordering ? l10n.t("تم", "Done") : l10n.t("ترتيب", "Reorder")) {
                        isReordering.toggle()
                    }
                }
            }
        }
        .confirmationDialog(
            l10n.t("حذف المهمة؟", "Delete task?"),
            isPresented: Binding(get: { pendingDeleteJobID != nil }, set: { if !$0 { pendingDeleteJobID = nil } }),
            titleVisibility: .visible
        ) {
            Button(l10n.t("حذف المهمة", "Delete task"), role: .destructive) {
                if let id = pendingDeleteJobID { viewModel.removeJob(id) }
                pendingDeleteJobID = nil
            }
            Button(l10n.t("إلغاء", "Cancel"), role: .cancel) { pendingDeleteJobID = nil }
        }
    }

    private func row(_ job: BasirJob) -> some View {
        Button { viewModel.selectJob(job.id) } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .top) {
                    Image(systemName: icon(job.status))
                        .foregroundStyle(color(job.status))
                        .accessibilityHidden(true)
                    Text(job.sourceName)
                        .font(.headline)
                        .foregroundStyle(BasirPalette.primaryText)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(statusText(job))
                    .font(.subheadline)
                    .foregroundStyle(BasirPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if job.status == .running {
                    ProgressView(value: Double(JobStep.overallPercent(for: job.progress)), total: 100)
                        .tint(BasirPalette.accent)
                }
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(job.sourceName)
        .accessibilityValue(statusText(job))
        .accessibilityAction(named: l10n.t("فتح المهمة", "Open task")) { viewModel.selectJob(job.id) }
        .accessibilityAction(named: job.status == .running ? l10n.t("إيقاف مؤقت", "Pause")
                                                           : l10n.t("استئناف أو إعادة المحاولة", "Resume or retry")) {
            if job.status == .running { viewModel.pause() } else { viewModel.resume(jobID: job.id) }
        }
        .accessibilityAction(named: l10n.t("حذف المهمة", "Delete task")) {
            if job.status != .running { pendingDeleteJobID = job.id }
        }
        .listRowBackground(BasirPalette.surface)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if job.status == .running {
                Button { viewModel.pause() } label: { Label(l10n.t("إيقاف مؤقت", "Pause"), systemImage: "pause") }
                    .tint(.orange)
            } else if [.paused, .failed, .cancelled, .waitingForNetwork, .partial].contains(job.status) {
                Button { viewModel.resume(jobID: job.id) } label: { Label(l10n.t("استئناف", "Resume"), systemImage: "play") }
                    .tint(.green)
            }
            if job.status != .running {
                Button(role: .destructive) { pendingDeleteJobID = job.id } label: {
                    Label(l10n.t("حذف المهمة", "Delete task"), systemImage: "trash")
                }
            }
        }
    }

    private func statusText(_ job: BasirJob) -> String {
        switch job.status {
        case .idle: return l10n.t("جديدة", "New")
        case .queued: return l10n.t("بانتظار البدء", "Queued")
        case .waitingForNetwork: return l10n.t("بانتظار الشبكة", "Waiting for network")
        case .running: return JobStep.spokenStatus(for: job.progress, l10n: l10n)
        case .paused: return l10n.t("متوقفة مؤقتًا", "Paused")
        case .partial: return l10n.t("نتيجة جزئية جاهزة", "Partial result ready")
        case .completed: return l10n.t("مكتملة", "Completed")
        case .failed: return l10n.t("تحتاج إعادة محاولة", "Needs retry")
        case .cancelled: return l10n.t("ملغاة", "Cancelled")
        }
    }

    private func icon(_ status: JobStatus) -> String {
        switch status {
        case .completed: return "checkmark.circle.fill"
        case .partial: return "exclamationmark.circle.fill"
        case .running: return "hourglass.circle.fill"
        case .paused: return "pause.circle.fill"
        case .waitingForNetwork: return "wifi.slash"
        case .failed: return "xmark.octagon.fill"
        case .cancelled: return "stop.circle.fill"
        default: return "clock.fill"
        }
    }

    private func color(_ status: JobStatus) -> Color {
        switch status {
        case .completed: return BasirPalette.success
        case .partial, .paused, .waitingForNetwork: return BasirPalette.warning
        case .failed: return BasirPalette.danger
        default: return BasirPalette.accent
        }
    }
}
