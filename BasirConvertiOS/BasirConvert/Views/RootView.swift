import SwiftUI
import UIKit

private enum AppTab: Hashable {
    case new
    case files
    case tasks
}

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var l10n: L10n
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var outputLibrary: OutputLibraryStore
    @EnvironmentObject private var intents: IntentRouter
    @State private var selectedTab: AppTab = .new
    @State private var operation: OperationKind = .convert
    @AppStorage("onboarding_completed_v3_1") private var onboardingCompleted = false

    private var isUnitTestHost: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            tab { TaskComposerView(operation: $operation) }
                .tabItem { Label(l10n.t("جديد", "New"), systemImage: "plus.circle.fill") }
                .tag(AppTab.new)

            tab { ResultLibraryView() }
                .tabItem { Label(l10n.t("ملفاتي", "My files"), systemImage: "folder.fill") }
                .tag(AppTab.files)

            tab { JobQueueView() }
                .tabItem { Label(l10n.t("المهام", "Tasks"), systemImage: "list.bullet.rectangle") }
                .badge(viewModel.pendingJobCount)
                .tag(AppTab.tasks)
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
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            applyTheme()
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
            l10n.t("كيف تريد معالجة الملفات؟", "What would you like to do with these files?"),
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
                    viewModel.routeExternalImport(to: .convert, l10n: l10n)
                }
            }
            if operations.contains(.translate) {
                Button(l10n.t("ترجمة المستندات", "Translate documents")) {
                    selectedTab = .new
                    viewModel.routeExternalImport(to: .translate, l10n: l10n)
                }
            }
            Button(l10n.t("إلغاء", "Cancel"), role: .cancel) { viewModel.cancelExternalImport() }
        } message: {
            let count = viewModel.externalImportBatch?.urls.count ?? 1
            Text(l10n.t("الملفات المستلمة: \(count). اختر التحويل أو الترجمة.",
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
        }
    }

    private func handleIntents() {
        if intents.pendingAction != nil { selectedTab = .new }
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
        ToolbarItem(placement: .navigationBarTrailing) {
            Button { viewModel.isSettingsPresented = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(BasirPalette.accent)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel(l10n.t("الإعدادات", "Settings"))
        }
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
