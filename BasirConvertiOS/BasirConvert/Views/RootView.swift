import SwiftUI
import UIKit

private enum AppTab: Hashable {
    case new
    case files
    case settings
}

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var l10n: L10n
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var outputLibrary: OutputLibraryStore
    @EnvironmentObject private var intents: IntentRouter
    @State private var selectedTab: AppTab = .new
    @State private var showComposer = false
    @State private var operation: OperationKind = .convert
    @AppStorage("onboarding_completed_v3_1") private var onboardingCompleted = false
    @AppStorage("video_launch_seen_v1") private var videoLaunchSeen = false
    @State private var sharedVideoLink: SharedVideoLink?
    @State private var showVideoLaunch = false
    @State private var showVideoWork = false

    private var isUnitTestHost: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            tab { BasirHomeView(showComposer: $showComposer)
                .navigationDestination(isPresented: $showComposer) { TaskComposerView(operation: $operation) } }
                .tabItem { Label(l10n.t("الرئيسية", "Home"), systemImage: "house.fill") }
                .tag(AppTab.new)

            tab { ResultLibraryView() }
                .tabItem { Label(l10n.t("ملفاتي", "My files"), systemImage: "folder.fill") }
                .tag(AppTab.files)

            tab { SettingsView(embedded: true) }
                .tabItem { Label(l10n.t("الإعدادات", "Settings"), systemImage: "gearshape.fill") }
                .tag(AppTab.settings)
        }
        .tint(BasirPalette.accent)
        .accessibilityAction(.magicTap) { toggleCurrentJob() }
        .onOpenURL { url in
            if let link = BasirLink(url: url) {
                intents.pendingAction = link == .scan ? .guidedCapture : .readLatestResult
            } else {
                viewModel.receiveExternalURL(url, l10n: l10n)
            }
        }
        .onChange(of: viewModel.routedExternalBatch?.id) { _ in selectTabForRoutedDocument() }
        .onChange(of: viewModel.routedExternalDocument?.id) { _ in selectTabForRoutedDocument() }
        .onChange(of: intents.pendingAction) { _ in handleIntents() }
        .onChange(of: intents.pendingFiles) { _ in handleIntents() }
        .onChange(of: intents.pendingJobID) { _ in handleIntents() }
        .onChange(of: settings.appearance) { _ in applyTheme() }
        .onChange(of: settings.highContrast) { _ in applyTheme() }
        .onAppear { AppActivity.record(screen: "application", action: "launch") }
        .task {
            guard !isUnitTestHost else { return }
            while !Task.isCancelled {
                if scenePhase == .active { await AppActivity.flush(configuration: settings.configuration) }
                do { try await Task.sleep(nanoseconds: 30_000_000_000) } catch { break }
            }
        }
        .onChange(of: scenePhase) { phase in
            AppActivity.record(screen: "application", action: phase == .active ? "foreground" : "background")
            guard phase == .active else { return }
            applyTheme()
            if let link = SharedLinks.takeLatestVideo() { sharedVideoLink = SharedVideoLink(url: link) }
            // Carry on quietly; the video screen, if open, shows the progress. It is opened
            // by Basir itself only after a cold start (below), never over another screen.
            VideoCenter.shared.runner.resumeIfNeeded(configuration: settings.configuration, l10n: l10n)
            // Long summaries carry on to the end (ServerTasks.swift).
            if !isUnitTestHost { ServerTaskCenter.shared.resumeAll(configuration: settings.configuration, l10n: l10n) }
            viewModel.importSharedInbox()
            viewModel.resumeInterruptedJobsIfNeeded()
            outputLibrary.refresh()
        }
        .onAppear {
            applyTheme()
            viewModel.attach(settings: settings, l10n: l10n, outputLibrary: outputLibrary)
            selectTabForRoutedDocument()
            handleIntents()
        }
        .confirmationDialog(
            l10n.t("ماذا تريد أن تفعل بهذه الملفات؟", "What would you like to do with these files?"),
            isPresented: Binding(
                get: { viewModel.externalImportBatch != nil || viewModel.externalImportCandidate != nil },
                set: { if !$0 { viewModel.cancelExternalImport() } }
            ),
            titleVisibility: .visible
        ) {
            let operations = viewModel.externalImportBatch?.operations
                ?? viewModel.externalImportCandidate?.operations
                ?? []
            if operations.contains(.convert) {
                Button(l10n.t("تحويل إلى Word", "Convert to Word")) {
                    selectedTab = .new
                    showComposer = true
                    viewModel.routeExternalImport(to: .convert, l10n: l10n)
                }
            }
            if operations.contains(.translate) {
                Button(l10n.t("ترجمة المستندات", "Translate documents")) {
                    selectedTab = .new
                    showComposer = true
                    viewModel.routeExternalImport(to: .translate, l10n: l10n)
                }
            }
            Button(l10n.t("إلغاء", "Cancel"), role: .cancel) { viewModel.cancelExternalImport() }
        } message: {
            let count = viewModel.externalImportBatch?.urls.count ?? 1
            Text(l10n.t("عدد الملفات: \(count). اختر تحويلها إلى Word أو ترجمتها.",
                        "Files received: \(count). Choose conversion or translation."))
        }
        .alert(
            l10n.t("تعذر فتح الملف", "Could not open the file"),
            isPresented: Binding(
                get: { viewModel.externalImportError != nil },
                set: { if !$0 { viewModel.clearExternalImportError() } }
            )
        ) {
            Button(l10n.t("حسنًا", "OK")) { viewModel.clearExternalImportError() }
        } message: { Text(viewModel.externalImportError ?? "") }
        .sheet(isPresented: $viewModel.isSettingsPresented) {
            SettingsView()
                .withBasirEnvironment(l10n: l10n, settings: settings, viewModel: viewModel,
                                      library: outputLibrary, intents: intents)
        }
        .sheet(isPresented: $viewModel.isJobPresented) {
            JobView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .withBasirEnvironment(l10n: l10n, settings: settings, viewModel: viewModel,
                                      library: outputLibrary, intents: intents)
        }
        .fullScreenCover(isPresented: Binding(
            get: { !onboardingCompleted && !isUnitTestHost },
            set: { if !$0 { onboardingCompleted = true } }
        )) {
            OnboardingView { onboardingCompleted = true }
                .withBasirEnvironment(l10n: l10n, settings: settings, viewModel: viewModel,
                                      library: outputLibrary, intents: intents)
        }
        .fullScreenCover(item: $sharedVideoLink) { shared in
            VideoDescribeView(initialLink: shared.url, startAtOnce: true)
                .withBasirEnvironment(l10n: l10n, settings: settings, viewModel: viewModel,
                                      library: outputLibrary, intents: intents)
        }
        .fullScreenCover(isPresented: $showVideoWork) {
            VideoDescribeView()
                .withBasirEnvironment(l10n: l10n, settings: settings, viewModel: viewModel,
                                      library: outputLibrary, intents: intents)
        }
        .fullScreenCover(isPresented: $showVideoLaunch, onDismiss: { videoLaunchSeen = true }) {
            VideoLaunchView()
                .withBasirEnvironment(l10n: l10n, settings: settings, viewModel: viewModel,
                                      library: outputLibrary, intents: intents)
        }
        .task {
            // A video being described when Basir was closed (or restarted by iOS) carries on,
            // and so do long summaries.
            returnToVideo()
            if !isUnitTestHost { ServerTaskCenter.shared.resumeAll(configuration: settings.configuration, l10n: l10n) }
            // Once, after the welcome screens, for people who already use Basir.
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if onboardingCompleted, !videoLaunchSeen, !isUnitTestHost, sharedVideoLink == nil, !showVideoWork {
                showVideoLaunch = true
            }
        }
    }

    /// Basir started again (iOS closed it) with a video under way, or described
    /// while away: show it.
    private func returnToVideo() {
        guard !isUnitTestHost, onboardingCompleted, sharedVideoLink == nil else { return }
        VideoCenter.shared.runner.resumeIfNeeded(configuration: settings.configuration, l10n: l10n)
        if VideoCenter.shared.shouldShowOnReturn { showVideoWork = true }
    }

    private func tab<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        NavigationStack {
            content().toolbar { commonToolbar }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { MiniJobBar() }
    }

    private func applyTheme() {
        BasirTheme.apply(appearance: settings.appearance, highContrast: settings.highContrast)
    }

    private func selectTabForRoutedDocument() {
        if viewModel.routedExternalBatch != nil || viewModel.routedExternalDocument != nil {
            selectedTab = .new
            showComposer = true
        }
    }

    private func handleIntents() {
        if intents.pendingAction != nil { selectedTab = .new; showComposer = true }
        if let jobID = intents.pendingJobID {
            intents.pendingJobID = nil
            viewModel.selectJob(jobID)
        }
        if !intents.pendingFiles.isEmpty {
            let files = intents.pendingFiles
            intents.pendingFiles = []
            viewModel.receiveExternalURLs(files, l10n: l10n)
        }
    }

    /// Two-finger double-tap (magic tap) pauses the running task or resumes
    /// the most recent paused one, from anywhere in the app.
    private func toggleCurrentJob() {
        if viewModel.activeJob != nil {
            viewModel.pause()
            UIAccessibility.post(notification: .announcement,
                                 argument: l10n.t("أُوقفت المهمة مؤقتًا", "Task paused"))
        } else if let paused = viewModel.jobs.first(where: { $0.status == .paused }) {
            viewModel.resume(jobID: paused.id)
            UIAccessibility.post(notification: .announcement,
                                 argument: l10n.t("استُؤنفت المهمة", "Task resumed"))
        } else {
            UIAccessibility.post(notification: .announcement,
                                 argument: l10n.t("لا توجد مهمة جارية", "No task is running"))
        }
    }

    @ToolbarContentBuilder
    private var commonToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) { NetworkStatusPill() }

    }
}

extension View {
    /// Sheets get every shared object explicitly, so they behave the same on
    /// every supported iOS version.
    @MainActor
    func withBasirEnvironment(
        l10n: L10n,
        settings: SettingsStore,
        viewModel: AppViewModel,
        library: OutputLibraryStore,
        intents: IntentRouter
    ) -> some View {
        environmentObject(l10n)
            .environmentObject(settings)
            .environmentObject(viewModel)
            .environmentObject(library)
            .environmentObject(intents)
            .environmentObject(NetworkMonitor.shared)
            .environment(\.layoutDirection, l10n.layoutDirection)
            .environment(\.locale, l10n.locale)
    }
}

/// A compact card above the tab bar for the current task. Tapping it expands
/// the full task details; the job no longer covers the whole screen.
struct MiniJobBar: View {
    @EnvironmentObject private var l10n: L10n
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let job = viewModel.barJob, !viewModel.isJobPresented {
                content(job)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: viewModel.barJob?.id)
    }

    private func content(_ job: BasirJob) -> some View {
        let percent = JobStep.overallPercent(for: job.progress)
        return HStack(spacing: BasirSpacing.m) {
            Button { viewModel.selectJob(job.id) } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: BasirSpacing.s) {
                        Image(systemName: icon(job.status))
                            .foregroundStyle(BasirPalette.accent)
                            .accessibilityHidden(true)
                        Text(job.sourceName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BasirPalette.primaryText)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if job.status == .running {
                            Text("\(percent)%")
                                .font(.subheadline.monospacedDigit().weight(.semibold))
                                .foregroundStyle(BasirPalette.primaryText)
                        }
                    }
                    Text(statusLine(job))
                        .font(.caption)
                        .foregroundStyle(BasirPalette.secondaryText)
                        .lineLimit(2)
                    if job.status == .running {
                        ProgressView(value: Double(percent), total: 100)
                            .tint(BasirPalette.accent)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(l10n.t("المهمة الحالية: \(job.sourceName)", "Current task: \(job.sourceName)"))
            .accessibilityValue(statusLine(job))
            .accessibilityHint(l10n.t("اضغط مرتين لفتح تفاصيل المهمة", "Double-tap to open task details"))

            toggleButton(job)
        }
        .padding(BasirSpacing.m)
        .background(BasirPalette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(BasirPalette.stroke, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
        .padding(.horizontal, BasirSpacing.m)
        .padding(.bottom, BasirSpacing.s)
    }

    @ViewBuilder
    private func toggleButton(_ job: BasirJob) -> some View {
        if job.status == .running {
            Button { viewModel.pause() } label: {
                Image(systemName: "pause.fill")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .tint(BasirPalette.accent)
            .accessibilityLabel(l10n.t("إيقاف مؤقت", "Pause"))
        } else if [.paused, .waitingForNetwork].contains(job.status) {
            Button { viewModel.resume(jobID: job.id) } label: {
                Image(systemName: "play.fill")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .tint(BasirPalette.accent)
            .accessibilityLabel(l10n.t("استئناف", "Resume"))
        }
    }

    private func statusLine(_ job: BasirJob) -> String {
        if job.isContinuingOnServer { return job.serverContinuationText(l10n) }
        switch job.status {
        case .running: return JobStep.spokenStatus(for: job.progress, l10n: l10n)
        case .queued: return l10n.t("بانتظار البدء", "Queued")
        case .waitingForNetwork: return l10n.t("بانتظار الاتصال", "Waiting for connection")
        case .paused: return l10n.t("متوقفة مؤقتًا. تقدمك محفوظ", "Paused. Progress saved")
        default: return ""
        }
    }

    private func icon(_ status: JobStatus) -> String {
        switch status {
        case .running: return "hourglass"
        case .paused: return "pause.circle.fill"
        case .waitingForNetwork: return "wifi.slash"
        default: return "clock.fill"
        }
    }
}

/// A YouTube link shared into Basir, shown once.
struct SharedVideoLink: Identifiable, Equatable {
    let id = UUID()
    let url: String
}


/// Home is an overview; composition, queue and tools keep their own screens.
struct BasirHomeView: View {
    @Binding var showComposer: Bool
    @EnvironmentObject private var l10n: L10n
    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var library: OutputLibraryStore
    @State private var latestPreview: URL?
    @State private var latestShare: URL?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BasirSpacing.xl) {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "doc.richtext.fill")
                        .font(.system(size: 36)).foregroundStyle(BasirPalette.accent)
                        .padding(18).background(BasirPalette.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 22))
                        .accessibilityHidden(true)
                    Text(l10n.t("ملفاتك، أسهل للقراءة", "Your files, easier to read"))
                        .font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                    Text(l10n.t("حوّل مستندًا أو ترجمه، وتابع النتيجة من مكان واحد.", "Convert or translate a document, then follow its result here."))
                        .foregroundStyle(BasirPalette.secondaryText)
                    PrimaryActionButton(title: l10n.t("تحويل جديد", "New conversion"), systemImage: "plus") { showComposer = true }
                }.glassSurface()
                NavigationLink { JobQueueView() } label: {
                    Label(l10n.t("متابعة المهام: \(viewModel.pendingJobCount)", "Track tasks: \(viewModel.pendingJobCount)"), systemImage: "list.bullet.rectangle")
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                }.glassSurface()
                if let job = viewModel.barJob {
                    Button { viewModel.selectJob(job.id) } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(l10n.t("المهمة الحالية", "Current task")).font(.headline)
                            Text(job.sourceName).lineLimit(2)
                            Text(JobStep.spokenStatus(for: job.progress, l10n: l10n)).font(.subheadline)
                                .foregroundStyle(BasirPalette.secondaryText)
                        }
                    }.buttonStyle(.plain).glassSurface()
                }
                if let item = library.items.first {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeading(title: l10n.t("آخر نتيجة محفوظة", "Latest saved result"))
                        Text(item.displayName).font(.headline)
                        AdaptiveStack {
                            CardActionButton(title: l10n.t("فتح", "Open"), systemImage: "doc.text") { latestPreview = item.url }
                            CardActionButton(title: l10n.t("مشاركة", "Share"), systemImage: "square.and.arrow.up") { latestShare = item.url }
                        }
                    }.glassSurface(accent: BasirPalette.success)
                }
                DisclosureGroup(l10n.t("أدوات إضافية", "More tools")) { BasirToolsSection() }
                    .glassSurface()
            }.appScreenContent(bottomPadding: 28)
        }
        .background { AuroraBackground() }
        .navigationTitle(l10n.t("الرئيسية", "Home"))
        .onAppear { library.refresh() }
        .sheet(isPresented: Binding(get: { latestPreview != nil }, set: { if !$0 { latestPreview = nil } })) {
            if let url = latestPreview { QuickLookPreview(url: url) }
        }
        .sheet(isPresented: Binding(get: { latestShare != nil }, set: { if !$0 { latestShare = nil } })) {
            if let url = latestShare { ActivityShareView(urls: [url]) }
        }
    }
}
