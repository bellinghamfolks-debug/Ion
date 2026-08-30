import SwiftUI

struct ResultLibraryView: View {
    @EnvironmentObject private var l10n: L10n
    @EnvironmentObject private var library: OutputLibraryStore
    @State private var previewItem: OutputRecord?
    @State private var shareItem: OutputRecord?
    @State private var exportItem: OutputRecord?
    @State private var openItem: OutputRecord?
    @State private var renameItem: OutputRecord?
    @State private var deleteItem: OutputRecord?
    @State private var newName = ""

    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    BasirHeroCard(
                        title: l10n.t("الملفات الناتجة", "My files and results"),
                        subtitle: l10n.t("عاين ملفاتك السابقة أو أعد تسميتها أو احفظ نسخة منها.",
                                         "Open any previous result, rename it, or save another copy."),
                        systemImage: "folder.fill.badge.person.crop"
                    )
                    if library.items.isEmpty {
                        InfoCard(
                            title: l10n.t("لا توجد نتائج بعد", "No results yet"),
                            text: l10n.t("ستظهر ملفات Word المكتملة هنا تلقائيًا.",
                                         "Completed Word files will appear here automatically."),
                            systemImage: "tray"
                        )
                    } else {
                        ForEach(library.items) { item in resultCard(item) }
                    }
                    if let error = library.errorMessage { InlineMessage(text: error, isError: true) }
                }
                .appScreenContent(bottomPadding: 28)
            }
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 8) }
            .refreshable { library.refresh() }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear { library.refresh() }
        .sheet(item: $previewItem) { QuickLookPreview(url: $0.url).ignoresSafeArea() }
        .sheet(item: $shareItem) { ActivityShareView(urls: [$0.url]) }
        .sheet(item: $exportItem) { ExportDocumentPicker(urls: [$0.url]) }
        .sheet(item: $openItem) { OpenInApplicationView(url: $0.url) }
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

    private func resultCard(_ item: OutputRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(item.displayName, systemImage: "doc.richtext.fill")
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(3)
            Text(metadataText(item))
                .font(.footnote)
                .foregroundStyle(BasirPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                action(l10n.t("معاينة", "Preview"), "eye.fill") { previewItem = item }
                action(l10n.t("مشاركة", "Share"), "square.and.arrow.up") { shareItem = item }
            }
            HStack {
                action(l10n.t("فتح باستخدام", "Open in app"), "arrow.up.forward.app") { openItem = item }
                action(l10n.t("حفظ في تطبيق الملفات", "Save to Files"), "folder.badge.plus") { exportItem = item }
            }
            Menu {
                Button(l10n.t("إعادة تسمية", "Rename"), systemImage: "pencil") {
                    newName = item.displayName
                    renameItem = item
                }
                Button(l10n.t("حذف", "Delete"), systemImage: "trash", role: .destructive) {
                    deleteItem = item
                }
            } label: {
                Label(l10n.t("إدارة الملف", "Manage file"), systemImage: "ellipsis.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(BasirPalette.cyan)
        }
        .glassSurface(accent: BasirPalette.cyan)
        .accessibilityElement(children: .contain)
    }

    private func action(_ title: String, _ icon: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
        }
        .buttonStyle(.bordered)
        .tint(BasirPalette.cyan)
    }

    private func metadataText(_ item: OutputRecord) -> String {
        var parts = [item.humanReadableSize,
                     item.createdAt.formatted(date: .abbreviated, time: .shortened)]
        if let source = item.sourceName { parts.append(l10n.t("المصدر: \(source)", "Source: \(source)")) }
        if let count = item.itemCount { parts.append(l10n.t("العناصر: \(count)", "Items: \(count)")) }
        if let language = item.languageCode, language != "auto" {
            let value = SupportedLanguage.language(code: language).name(interface: l10n.language)
            parts.append(l10n.t("اللغة: \(value)", "Language: \(value)"))
        }
        return parts.joined(separator: " • ")
    }
}

struct JobQueueView: View {
    @EnvironmentObject private var l10n: L10n
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var pendingDeleteJobID: UUID?

    var body: some View {
        ZStack {
            AuroraBackground()
            VStack(spacing: 0) {
                if viewModel.jobs.isEmpty {
                    ScrollView {
                        VStack(spacing: 14) {
                            BasirHeroCard(
                                title: l10n.t("المهام", "Tasks"),
                                subtitle: l10n.t("تابع المهام الجارية والمكتملة، أو استأنف مهمة متوقفة.",
                                                 "Running, paused, and previous tasks appear here."),
                                systemImage: "list.bullet.rectangle.fill"
                            )
                            InfoCard(title: l10n.t("لا توجد مهام", "The queue is empty"),
                                     text: l10n.t("اختر ملفًا من قسم التحويل أو الترجمة للبدء.",
                                                  "Choose a file in Convert or Translate to begin."),
                                     systemImage: "checklist")
                        }
                        .appScreenContent(bottomPadding: 28)
                    }
                    .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 8) }
                } else {
                    List {
                        ForEach(viewModel.jobs) { job in
                            Button { viewModel.selectJob(job.id) } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    HStack {
                                        Image(systemName: icon(job.status)).foregroundStyle(color(job.status))
                                        Text(job.sourceName).font(.headline).foregroundStyle(.white).lineLimit(2)
                                    }
                                    Text(statusText(job))
                                        .font(.subheadline)
                                        .foregroundStyle(BasirPalette.secondaryText)
                                    if job.progress.total > 0 {
                                        ProgressView(value: job.progress.fraction ?? 0).tint(BasirPalette.cyan)
                                    }
                                }
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(job.sourceName)
                            .accessibilityValue(statusText(job))
                            .accessibilityAction(named: l10n.t("فتح المهمة", "Open task")) { viewModel.selectJob(job.id) }
                            .accessibilityAction(named: l10n.t("إعادة المحاولة", "Retry")) {
                                if job.status != .running { viewModel.resume(jobID: job.id) }
                            }
                            .accessibilityAction(named: l10n.t("حذف المهمة", "Delete task")) {
                                if job.status != .running { pendingDeleteJobID = job.id }
                            }
                            .listRowBackground(Color.black)
                            .listRowSeparator(.hidden)
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
                        .onMove(perform: viewModel.moveJobs)
                    }
                    .scrollContentBackground(.hidden)
                    .environment(\.editMode, .constant(.active))
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
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

    private func statusText(_ job: BasirJob) -> String {
        let state: String
        switch job.status {
        case .idle: state = l10n.t("جديدة", "New")
        case .queued: state = l10n.t("بانتظار البدء", "Queued")
        case .waitingForNetwork: state = l10n.t("بانتظار الشبكة", "Waiting for network")
        case .running: state = l10n.t("قيد التنفيذ", "Running")
        case .paused: state = l10n.t("متوقفة مؤقتًا", "Paused")
        case .partial: state = l10n.t("نتيجة جزئية", "Partial result")
        case .completed: state = l10n.t("مكتملة", "Completed")
        case .failed: state = l10n.t("تحتاج إعادة محاولة", "Needs retry")
        case .cancelled: state = l10n.t("ملغاة", "Cancelled")
        }
        guard job.progress.total > 0 else { return state }
        return "\(state) • \(job.progress.current)/\(job.progress.total)"
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
        case .completed: return .green
        case .partial, .paused, .waitingForNetwork: return .orange
        case .failed: return .red
        default: return BasirPalette.cyan
        }
    }
}

