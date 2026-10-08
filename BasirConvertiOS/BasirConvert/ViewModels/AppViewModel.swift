import Foundation
import UIKit
import Combine
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var jobs: [BasirJob] = []
    @Published private(set) var selectedJobID: UUID?
    @Published private(set) var status: JobStatus = .idle
    @Published private(set) var progress = ConversionProgress(
        current: 0, total: 0, stage: .preparing, detail: nil
    )
    @Published private(set) var sourceName = ""
    @Published private(set) var resultURL: URL?
    @Published private(set) var diagnosticURL: URL?
    @Published private(set) var errorMessage: String?
    @Published private(set) var externalImportCandidate: ExternalImportCandidate?
    @Published private(set) var externalImportBatch: ExternalImportBatch?
    @Published private(set) var routedExternalDocument: RoutedExternalDocument?
    @Published private(set) var routedExternalBatch: RoutedExternalBatch?
    @Published private(set) var externalImportError: String?
    @Published var isJobPresented = false
    @Published var isSettingsPresented = false

    private let engine = ConversionEngine()
    private let jobStore = PersistentJobStore()
    private let backgroundExecution = BackgroundExecution.shared
    private var jobTask: Task<Void, Never>?
    private var externalImportTask: Task<Void, Never>?
    private var lastAnnouncedStage: ConversionStage?
    private var lastAnnouncedStep: JobStep?
    private let liveActivity = JobLiveActivityController()
    private var lastAnnouncedProgress: [UUID: (current: Int, total: Int)] = [:]
    private var pauseRequested = false
    /// One-time notices, so iOS waking and stopping the app repeatedly in
    /// the background never repeats them.
    private var readyNoticeSent: Set<UUID> = []
    private var cancellationTasks: [UUID: Task<Void, Never>] = [:]
    private var uploadPauseNoticeSent: Set<UUID> = []
    private var networkPauseRequested = false
    private var networkCancellable: AnyCancellable?
    private var networkLossTask: Task<Void, Never>?
    private var transportReconnectTasks: [UUID: Task<Void, Never>] = [:]
    private var transportReconnectAttempts: [UUID: Int] = [:]
    private var progressRateEMA: [UUID: Double] = [:]
    private var lastProgressSample: [UUID: (current: Int, date: Date)] = [:]
    private var activeLogger: DiagnosticLogger?
    private var lastConfiguration: ServerConfiguration?
    private weak var settings: SettingsStore?
    private weak var l10n: L10n?
    private weak var outputLibrary: OutputLibraryStore?

    var isRunning: Bool { status == .running }
    var activeJob: BasirJob? { jobs.first(where: { $0.status == .running }) }
    var selectedJob: BasirJob? {
        guard let selectedJobID else { return activeJob ?? jobs.first }
        return jobs.first(where: { $0.id == selectedJobID })
    }
    /// The job shown in the compact bar above the tab bar.
    var barJob: BasirJob? {
        activeJob ?? jobs.first(where: { [.queued, .waitingForNetwork, .paused].contains($0.status) })
    }
    var pendingJobCount: Int {
        jobs.filter { [.queued, .waitingForNetwork, .paused, .running].contains($0.status) }.count
    }
    var elapsedTime: TimeInterval {
        guard let started = selectedJob?.startedAt else { return 0 }
        return max(0, (selectedJob?.completedAt ?? Date()).timeIntervalSince(started))
    }
    var estimatedRemaining: TimeInterval? {
        guard let job = selectedJob,
              progress.total > progress.current,
              let pagesPerSecond = progressRateEMA[job.id],
              pagesPerSecond > 0.005 else { return nil }
        return Double(progress.total - progress.current) / pagesPerSecond
    }

    init() {
        Task { [weak self] in
            guard let self else { return }
            let restored = await jobStore.load()
            // Before any task starts, drop transfers an earlier launch left
            // behind; nothing waits for them and they slow new transfers.
            await BackgroundTransferCoordinator.shared.cancelTransfersFromEarlierLaunch()
            jobs = restored
            selectedJobID = restored.first(where: { [.paused, .waitingForNetwork, .queued].contains($0.status) })?.id
                ?? restored.first?.id
            syncFacade()
            if self.settings?.automaticResume == true { self.resumeInterruptedJobsIfNeeded() }
        }
    }

    func attach(settings: SettingsStore, l10n: L10n, outputLibrary: OutputLibraryStore) {
        self.settings = settings
        self.l10n = l10n
        self.outputLibrary = outputLibrary
        DiagnosticLogger.recordGlobal("APP attached notifications=\(settings.notificationsEnabled) automaticResume=\(settings.automaticResume) wifiOnly=\(settings.wifiOnly) allowLowData=\(settings.allowLowData)")
        lastConfiguration = settings.configuration
        outputLibrary.refresh()
        resendPendingCancellations()
        networkCancellable = NetworkMonitor.shared.$snapshot
            .removeDuplicates()
            .sink { [weak self] snapshot in
                Task { @MainActor in self?.networkDidChange(snapshot) }
            }
        backgroundExecution.processingHandler = { [weak self] in
            await self?.resumeQueueFromBackground()
        }
        backgroundExecution.expirationHandler = { [weak self] in
            self?.suspendRunningJobForBackgroundExpiry()
        }
        if settings.notificationsEnabled {
            Task {
                if await OperationFeedback.requestNotificationPermission() {
                    PushRegistrar.shared.registerForRemoteNotifications()
                }
            }
        }
        importSharedInbox()
        resumeInterruptedJobsIfNeeded()
        processNextIfPossible()
    }

    func importSharedInbox() {
        Task { [weak self] in
            do {
                let urls = try await Task.detached(priority: .utility) { try SharedInbox.takeAll() }.value
                guard !urls.isEmpty, let self, let l10n = self.l10n else { return }
                self.receiveAlreadyStagedExternalURLs(urls, l10n: l10n)
            } catch {
                DiagnosticLogger.recordGlobal("IMPORT shared-inbox failed type=\(String(reflecting: type(of: error))) description=\(error.localizedDescription)")
                self?.externalImportError = error.localizedDescription
            }
        }
    }

    func receiveExternalURL(_ url: URL, l10n: L10n) {
        receiveExternalURLs([url], l10n: l10n)
    }

    func receiveExternalURLs(_ urls: [URL], l10n: L10n) {
        guard !urls.isEmpty, urls.allSatisfy(\.isFileURL) else {
            externalImportError = l10n.t(
                "لا يستطيع بصير فتح هذا الرابط. أرسل ملفًا أو صورة.",
                "Basir cannot open this link. Send a file or image instead."
            )
            return
        }
        let supported = urls.filter { !SupportedInput.operations(for: $0).isEmpty }
        guard supported.count == urls.count else {
            externalImportError = l10n.t(
                "توجد صيغة غير مدعومة. أرسل PDF أو Word أو PowerPoint أو صورة أو تسجيلًا صوتيًا مدعومًا.",
                "One of the items is unsupported. Send PDF, Word, PowerPoint, a supported image, or an audio recording."
            )
            return
        }

        externalImportTask?.cancel()
        externalImportError = nil
        externalImportTask = Task { [weak self] in
            do {
                let staged = try await Task.detached(priority: .userInitiated) {
                    try supported.map { try FileAccess.stageExternalSource($0).source }
                }.value
                guard let self else { return }
                self.externalImportTask = nil
                self.receiveAlreadyStagedExternalURLs(staged, l10n: l10n)
            } catch is CancellationError {
                return
            } catch {
                DiagnosticLogger.recordGlobal("IMPORT staging failed type=\(String(reflecting: type(of: error))) description=\(error.localizedDescription)")
                self?.externalImportTask = nil
                self?.externalImportError = Self.localized(error, l10n: l10n)
            }
        }
    }

    private func receiveAlreadyStagedExternalURLs(_ urls: [URL], l10n: L10n) {
        guard !urls.isEmpty else { return }
        let operationSets = urls.map(SupportedInput.operations)
        let common = operationSets.dropFirst().reduce(operationSets[0]) { $0.intersection($1) }
        guard !common.isEmpty else {
            urls.forEach(discardExternalSource)
            externalImportError = l10n.t(
                "لا يمكن تنفيذ عملية واحدة على مجموعة الملفات المختارة.",
                "The selected files do not share one compatible operation."
            )
            return
        }
        if common.count == 1, let operation = common.first {
            route(stagedURLs: urls, to: operation, l10n: l10n)
        } else {
            externalImportBatch = ExternalImportBatch(id: UUID(), urls: urls, operations: common)
            UIAccessibility.post(
                notification: .announcement,
                argument: l10n.t(
                    "تم استلام \(urls.count) من العناصر. اختر التحويل أو الترجمة.",
                    "Received \(urls.count) items. Choose Convert or Translate."
                )
            )
        }
    }

    func routeExternalImport(to operation: OperationKind, l10n: L10n) {
        if let batch = externalImportBatch, batch.operations.contains(operation) {
            externalImportBatch = nil
            route(stagedURLs: batch.urls, to: operation, l10n: l10n)
            return
        }
        guard let candidate = externalImportCandidate,
              candidate.operations.contains(operation) else { return }
        externalImportCandidate = nil
        route(stagedURLs: [candidate.url], to: operation, l10n: l10n)
    }

    func cancelExternalImport() {
        externalImportTask?.cancel()
        externalImportTask = nil
        externalImportBatch?.urls.forEach(discardExternalSource)
        if let candidate = externalImportCandidate { discardExternalSource(candidate.url) }
        externalImportBatch = nil
        externalImportCandidate = nil
    }

    func consumeRoutedExternalDocument(id: UUID) {
        guard routedExternalDocument?.id == id else { return }
        routedExternalDocument = nil
    }

    func consumeRoutedExternalBatch(id: UUID) {
        guard routedExternalBatch?.id == id else { return }
        routedExternalBatch = nil
    }

    func discardExternalSource(_ url: URL) {
        FileAccess.removeExternalImportDirectory(url.deletingLastPathComponent())
    }

    func clearExternalImportError() { externalImportError = nil }

    func start(
        pickerURL: URL,
        options: ConversionOptions,
        configuration: ServerConfiguration,
        l10n: L10n
    ) {
        start(pickerURLs: [pickerURL], options: options, configuration: configuration, l10n: l10n)
    }

    func start(
        pickerURLs: [URL],
        options: ConversionOptions,
        configuration: ServerConfiguration,
        l10n: L10n
    ) {
        guard !pickerURLs.isEmpty else { return }
        guard configuration.isConfigured else {
            isSettingsPresented = true
            return
        }
        lastConfiguration = configuration
        // 3.1: the task appears in the compact bar instead of covering the screen.
        UIAccessibility.post(
            notification: .announcement,
            argument: l10n.t("بدأت المهمة. تابعها من الشريط أسفل الشاشة.",
                             "The task has started. Follow it in the bar at the bottom of the screen.")
        )
        Task { [weak self] in
            guard let self else { return }
            var newJobs: [BasirJob] = []
            for pickerURL in pickerURLs {
                do {
                    let id = UUID()
                    let prepared = try await Task.detached(priority: .userInitiated) {
                        let directory = try FileAccess.makePersistentJobDirectory(id: id)
                        let source = try FileAccess.materializeSecurityScoped(pickerURL, into: directory)
                        let metadata = try DocumentInspector.inspect(source)
                        let log = try FileAccess.diagnosticURL(for: source)
                        return (source, metadata, log)
                    }.value
                    let now = Date()
                    newJobs.append(BasirJob(
                        id: id,
                        sourcePath: prepared.0.path,
                        sourceName: prepared.0.lastPathComponent,
                        sourceMetadata: prepared.1,
                        options: options,
                        status: .queued,
                        progress: .init(current: 0, total: prepared.1.itemCount ?? 0,
                                        stage: .preparing, detail: nil),
                        resultPath: nil,
                        diagnosticPath: prepared.2.path,
                        errorMessage: nil,
                        failedItems: [],
                        skippedBlankItems: [],
                        requestID: UUID().uuidString,
                        createdAt: now,
                        updatedAt: now,
                        startedAt: nil,
                        completedAt: nil,
                        automaticResumePending: false,
                        executedModel: nil,
                        qualityReport: nil
                    ))
                    discardExternalSource(pickerURL)
                } catch {
                    DiagnosticLogger.recordGlobal("QUEUE source-prepare failed type=\(String(reflecting: type(of: error))) description=\(error.localizedDescription)")
                    externalImportError = Self.localized(error, l10n: l10n)
                }
            }
            guard !newJobs.isEmpty else { return }
            jobs.append(contentsOf: newJobs)
            selectedJobID = newJobs.first?.id
            persist()
            syncFacade()
            processNextIfPossible()
        }
    }

    func selectJob(_ id: UUID) {
        guard jobs.contains(where: { $0.id == id }) else { return }
        selectedJobID = id
        syncFacade()
        isJobPresented = true
    }

    func pause() {
        guard let index = activeIndex else { return }
        activeLogger?.record("USER pause requested")
        pauseRequested = true
        jobs[index].status = .paused
        jobs[index].automaticResumePending = false
        jobs[index].progress = progressReplacingStage(jobs[index].progress, .paused)
        jobs[index].updatedAt = Date()
        persist()
        syncFacade()
        jobTask?.cancel()
        OperationFeedback.play(.paused, theme: settings?.soundTheme ?? .gentle)
    }

    func resume(jobID: UUID? = nil) {
        let id = jobID ?? selectedJobID
        guard let id, let index = jobs.firstIndex(where: { $0.id == id }),
              [.paused, .failed, .cancelled, .waitingForNetwork, .partial].contains(jobs[index].status) else { return }
        // Restarting before the server confirmed the cancellation could let
        // the late cancellation stop the new run. Wait for the confirmation.
        if jobs[index].serverCancelPending == true {
            if let l10n {
                UIAccessibility.post(notification: .announcement, argument: l10n.t(
                    "انتظر حتى يؤكد الخادم الإلغاء، ثم أعد المحاولة.",
                    "Wait until the server confirms the cancellation, then try again."))
            }
            sendServerCancellation(jobID: id)
            return
        }
        jobs[index].status = .queued
        jobs[index].automaticResumePending = false
        jobs[index].errorMessage = nil
        jobs[index].completedAt = nil
        jobs[index].updatedAt = Date()
        persist()
        syncFacade()
        processNextIfPossible()
    }

    func retry() { resume() }
    func retryFailedItems() { resume() }

    func cancel() {
        let index = activeIndex
            ?? selectedJobID.flatMap { id in jobs.firstIndex(where: { $0.id == id }) }
        guard let index,
              [.running, .queued, .waitingForNetwork, .paused, .failed, .partial]
                .contains(jobs[index].status) else { return }
        let wasRunning = jobs[index].status == .running
        let jobID = jobs[index].id
        activeLogger?.record("USER cancel requested status=\(jobs[index].status.rawValue)")
        pauseRequested = false
        networkPauseRequested = false
        jobs[index].status = .cancelled
        // The task is only really cancelled once the server stops working on
        // it. Until the server confirms, say so, and keep asking.
        jobs[index].serverCancelPending = true
        jobs[index].errorMessage = l10n?.t(
            "جارٍ إيقاف المهمة على خادم بصير…",
            "Stopping the task on the Basir server…"
        )
        jobs[index].updatedAt = Date()
        persist()
        syncFacade()
        if wasRunning { jobTask?.cancel() }
        OperationFeedback.clearProgress(jobID)
        PushRegistrar.shared.jobFinished(jobID)
        sendServerCancellation(jobID: jobID)
        processNextIfPossible()
    }

    /// Sends the cancellation to the server until it is confirmed, with
    /// growing pauses between attempts. Survives relaunches through
    /// `serverCancelPending`, which `attach` and reconnection pick up again.
    private func sendServerCancellation(jobID: UUID) {
        guard cancellationTasks[jobID] == nil else { return }
        cancellationTasks[jobID] = Task { [weak self] in
            var attempt = 0
            while let model = self,
                  let job = model.jobs.first(where: { $0.id == jobID }),
                  job.serverCancelPending == true,
                  !Task.isCancelled {
                guard let configuration = model.serverConfiguration else { break }
                do {
                    let outcome = try await ProxyClient(configuration: configuration)
                        .cancelServerTask(requestID: job.requestID)
                    model.serverCancellationConfirmed(jobID: jobID, outcome: outcome)
                    break
                } catch is CancellationError {
                    break
                } catch {
                    DiagnosticLogger.recordGlobal("CANCEL not confirmed appJob=\(jobID.uuidString) attempt=\(attempt) description=\(error.localizedDescription)")
                    model.serverCancellationWaiting(jobID: jobID)
                    attempt += 1
                    try? await Task.sleep(for: .seconds(min(60, 2 << min(attempt, 5))))
                }
            }
            self?.cancellationTasks[jobID] = nil
        }
    }

    private var serverConfiguration: ServerConfiguration? {
        if let configuration = settings?.configuration, configuration.isConfigured { return configuration }
        return lastConfiguration
    }

    private func serverCancellationConfirmed(jobID: UUID, outcome: ServerCancellation) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        jobs[index].serverCancelPending = nil
        let message: String
        switch outcome {
        case .cancelled:
            message = l10n?.t(
                "أُلغيت المهمة وتوقف خادم بصير عن العمل عليها. بقي المصدر محفوظًا ويمكنك إعادة المحاولة.",
                "The task was cancelled and the Basir server stopped working on it. The source is kept so you can retry."
            ) ?? ""
        case .neverReachedServer:
            message = l10n?.t(
                "أُلغيت المهمة قبل أن تصل إلى الخادم. بقي المصدر محفوظًا ويمكنك إعادة المحاولة.",
                "The task was cancelled before it reached the server. The source is kept so you can retry."
            ) ?? ""
        case .alreadyFinished:
            message = l10n?.t(
                "كانت المهمة قد اكتملت على الخادم قبل وصول الإلغاء. اختر «إعادة المحاولة» لتنزيل النتيجة دون تحويل جديد.",
                "The task had already finished on the server before the cancellation arrived. Choose Try again to download the result without converting again."
            ) ?? ""
        }
        jobs[index].errorMessage = message
        jobs[index].updatedAt = Date()
        DiagnosticLogger.recordGlobal("CANCEL confirmed appJob=\(jobID.uuidString) outcome=\(outcome)")
        persist()
        syncFacade()
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    private func serverCancellationWaiting(jobID: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        jobs[index].errorMessage = l10n?.t(
            "لم يصل الإلغاء إلى الخادم بعد بسبب الاتصال. سيُرسل تلقائيًا حتى يتأكد.",
            "The cancellation has not reached the server yet because of the connection. It is sent again automatically until confirmed."
        )
        persist()
        syncFacade()
    }

    /// Cancellations left unconfirmed by an earlier launch or a lost
    /// connection are sent again.
    private func resendPendingCancellations() {
        for job in jobs where job.serverCancelPending == true {
            sendServerCancellation(jobID: job.id)
        }
    }

    func removeJob(_ id: UUID, deleteResult: Bool = false) {
        guard let index = jobs.firstIndex(where: { $0.id == id }), jobs[index].status != .running else { return }
        let removed = jobs.remove(at: index)
        // Removing a task that may still be converting on the server (paused,
        // queued, waiting, or with an unconfirmed cancellation) stops it there.
        if [.paused, .queued, .waitingForNetwork].contains(removed.status) || removed.serverCancelPending == true,
           let configuration = serverConfiguration {
            let requestID = removed.requestID
            Task.detached {
                for attempt in 0..<6 {
                    if (try? await ProxyClient(configuration: configuration).cancelServerTask(requestID: requestID)) != nil { return }
                    try? await Task.sleep(for: .seconds(2 << attempt))
                }
            }
        }
        cancellationTasks[id]?.cancel()
        cancellationTasks[id] = nil
        Task { await jobStore.removeFiles(for: removed, keepingResult: !deleteResult) }
        if selectedJobID == id { selectedJobID = jobs.first?.id }
        persist()
        syncFacade()
    }

    func moveJobs(from offsets: IndexSet, to destination: Int) {
        jobs.move(fromOffsets: offsets, toOffset: destination)
        persist()
    }

    func dismissJob() { isJobPresented = false }

    private var activeIndex: Int? { jobs.firstIndex(where: { $0.status == .running }) }

    private func processNextIfPossible(preferredJobID: UUID? = nil) {
        guard jobTask == nil,
              let settings,
              let l10n else { return }
        let preferredIndex = preferredJobID.flatMap { preferred in
            jobs.firstIndex(where: {
                $0.id == preferred && [.queued, .waitingForNetwork].contains($0.status)
            })
        }
        guard let index = preferredIndex
                ?? jobs.firstIndex(where: { [.queued, .waitingForNetwork].contains($0.status) }) else { return }
        do {
            try NetworkMonitor.shared.validate(settings: settings)
        } catch {
            jobs[index].status = .waitingForNetwork
            jobs[index].progress = progressReplacingStage(jobs[index].progress, .waitingForNetwork)
            jobs[index].errorMessage = Self.localized(error, l10n: l10n)
            selectedJobID = jobs[index].id
            persist()
            syncFacade()
            backgroundExecution.schedule()
            return
        }

        let configuration = settings.configuration.isConfigured
            ? settings.configuration : lastConfiguration
        guard let configuration, configuration.isConfigured else {
            jobs[index].status = .paused
            jobs[index].errorMessage = l10n.t(
                "تعذر بدء المهمة حاليًا. أغلق التطبيق وافتحه ثم حاول مرة أخرى.",
                "The task cannot start right now. Reopen the app and try again."
            )
            selectedJobID = jobs[index].id
            persist()
            syncFacade()
            return
        }

        pauseRequested = false
        networkPauseRequested = false
        jobs[index].status = .running
        jobs[index].startedAt = jobs[index].startedAt ?? Date()
        jobs[index].updatedAt = Date()
        jobs[index].errorMessage = nil
        jobs[index].progress = progressReplacingStage(jobs[index].progress, .preparing)
        let jobID = jobs[index].id
        selectedJobID = jobID
        persist()
        syncFacade()
        backgroundExecution.begin { [weak self] in self?.suspendForSystemBackgroundLimit(jobID: jobID) }
        backgroundExecution.schedule()

        jobTask = Task { [weak self] in
            guard let self, let snapshot = jobs.first(where: { $0.id == jobID }) else { return }
            let source = snapshot.sourceURL
            let output: URL
            do {
                output = try snapshot.resultURL ?? FileAccess.outputURL(for: source, options: snapshot.options)
            } catch {
                finish(jobID: jobID, error: error, logger: nil, output: nil)
                return
            }
            let logger = DiagnosticLogger(
                sourceName: snapshot.sourceName,
                options: snapshot.options,
                destinationURL: snapshot.diagnosticURL
            )
            activeLogger = logger
            logger.record("JOB appJob=\(jobID.uuidString) clientRequest=\(snapshot.requestID) status=running")
            if let metadata = snapshot.sourceMetadata {
                logger.record("SOURCE contentType=\(metadata.contentType) bytes=\(metadata.byteCount) items=\(metadata.itemCount ?? -1) pixels=\(metadata.pixelWidth ?? -1)x\(metadata.pixelHeight ?? -1) checksumPrefix=\((metadata.checksum ?? "none").prefix(16))")
            }
            logger.recordNetwork(NetworkMonitor.shared.snapshot, reason: "job-start")
            let checkpoint = source.deletingLastPathComponent().appendingPathComponent("Checkpoints", isDirectory: true)
            do {
                let outcome = try await engine.convert(
                    sourceURL: source,
                    outputURL: output,
                    options: snapshot.options,
                    configuration: configuration,
                    requestID: snapshot.requestID,
                    progress: { [weak self] update in
                        Task { @MainActor in self?.apply(update, to: jobID) }
                    },
                    logger: logger,
                    checkpointDirectory: checkpoint,
                    serverJobCreated: { [language = l10n.language.rawValue] serverJobID in
                        Task { @MainActor in
                            PushRegistrar.shared.serverJobCreated(
                                clientJobID: jobID, serverJobID: serverJobID,
                                configuration: configuration, language: language
                            )
                        }
                    }
                )
                try Task.checkCancellation()
                logger.record("SUCCESS output=\(output.lastPathComponent)")
                if let diagnostic = snapshot.diagnosticURL { try? logger.write(to: diagnostic) }
                guard let finishedIndex = jobs.firstIndex(where: { $0.id == jobID }) else { return }
                jobs[finishedIndex].resultPath = output.path
                jobs[finishedIndex].failedItems = outcome.failedItems
                jobs[finishedIndex].skippedBlankItems = outcome.skippedBlankItems
                jobs[finishedIndex].executedModel = outcome.executedModel
                jobs[finishedIndex].qualityReport = outcome.quality
                jobs[finishedIndex].status = outcome.failedItems.isEmpty ? .completed : .partial
                jobs[finishedIndex].completedAt = Date()
                jobs[finishedIndex].updatedAt = Date()
                jobs[finishedIndex].progress = ConversionProgress(
                    current: max(1, jobs[finishedIndex].progress.total),
                    total: max(1, jobs[finishedIndex].progress.total),
                    stage: .done,
                    detail: outcome.failedItems.isEmpty ? nil : "fallback: \(outcome.failedItems.count)",
                    succeeded: outcome.succeededItems,
                    failed: outcome.failedItems.count,
                    skipped: outcome.skippedBlankItems.count
                )
                outputLibrary?.writeMetadata(for: output, job: jobs[finishedIndex])
                persist()
                syncFacade()
                if settings.deleteServerCopy, outcome.failedItems.isEmpty {
                    // A partial result keeps its server copy so failed pages can be retried.
                    let requestID = snapshot.requestID
                    Task.detached { try? await ProxyClient(configuration: configuration).deleteServerTask(requestID: requestID) }
                }
                OperationFeedback.play(.completed, theme: settings.soundTheme)
                if settings.notificationsEnabled {
                    OperationFeedback.notifyCompletion(
                        title: l10n.t("اكتملت مهمة بصير", "Basir task completed"),
                        body: output.lastPathComponent,
                        jobID: jobID
                    )
                }
                UIAccessibility.post(
                    notification: .announcement,
                    argument: outcome.failedItems.isEmpty
                        ? l10n.t("اكتملت العملية وأصبح ملف Word جاهزًا.", "The Word file is ready.")
                        : l10n.t("اكتملت النتيجة جزئيًا. نجح \(outcome.succeededItems) وفشل \(outcome.failedItems.count).",
                                 "A partial result is ready. \(outcome.succeededItems) succeeded and \(outcome.failedItems.count) failed.")
                )
                PushRegistrar.shared.jobFinished(jobID)
                completeCurrentTaskAndContinue()
            } catch is CancellationError {
                handleCancellation(jobID: jobID, logger: logger)
            } catch let urlError as URLError where urlError.code == .cancelled {
                handleTransportCancellation(jobID: jobID, logger: logger)
            } catch {
                finish(jobID: jobID, error: error, logger: logger, output: output)
            }
        }
    }

    private func suspendForSystemBackgroundLimit(jobID: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }), jobs[index].status == .running else { return }
        // Read where the task really is before marking it paused.
        let workingStage = jobs[index].progress.stage
        let percent = JobStep.overallPercent(for: jobs[index].progress)
        let phase = BackgroundPausePhase(stage: workingStage)
        pauseRequested = true
        jobs[index].status = .paused
        jobs[index].automaticResumePending = true
        jobs[index].progress = progressReplacingStage(jobs[index].progress, .paused)
        jobs[index].errorMessage = l10n.map { phase.statusMessage(l10n: $0) }
        jobs[index].updatedAt = Date()
        persist()
        syncFacade()
        jobTask?.cancel()
        DiagnosticLogger.recordGlobal("BACKGROUND limit reached appJob=\(jobID.uuidString) stage=\(workingStage.rawValue) percent=\(percent)")
        // Ask iOS to wake the app again soon, and tell the person what is
        // really happening instead of leaving a stale percentage.
        backgroundExecution.schedule(earliest: Date(timeIntervalSinceNow: 60))
        // No notification for this. iOS stopping the app is not a pause: the
        // server keeps converting and reports progress and completion by
        // push. A "stopped" notice every time iOS reclaims background time
        // was exactly the false alarm people saw every few minutes.
        guard settings?.notificationsEnabled == true, let l10n else { return }
        let pushActive = PushRegistrar.shared.remoteProgressJobs.contains(jobID)
        switch phase {
        case .serverWorking:
            return
        case .serverFinished:
            // Without server push, say once that the file is ready.
            guard !pushActive, !readyNoticeSent.contains(jobID) else { return }
            readyNoticeSent.insert(jobID)
            OperationFeedback.notifyResultWaiting(
                title: jobs[index].sourceName,
                body: phase.notificationBody(percent: percent, l10n: l10n),
                jobID: jobID
            )
        case .uploading:
            // The upload really does wait for the app. Say so once per task.
            guard !uploadPauseNoticeSent.contains(jobID) else { return }
            uploadPauseNoticeSent.insert(jobID)
            OperationFeedback.notifyBackgroundPause(
                title: jobs[index].sourceName,
                body: phase.notificationBody(percent: percent, l10n: l10n),
                jobID: jobID
            )
        }
    }

    /// Called when a background task iOS granted is about to expire.
    private func suspendRunningJobForBackgroundExpiry() {
        guard let running = activeJob else { return }
        suspendForSystemBackgroundLimit(jobID: running.id)
    }

    private func apply(_ update: ConversionProgress, to jobID: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }), jobs[index].status == .running else { return }
        let previous = jobs[index].progress
        if update.stage == .processing,
           previous.current > 0,
           (update.total == 0 || update.current < previous.current) {
            jobs[index].progress = ConversionProgress(
                current: previous.current,
                total: max(previous.total, update.total),
                stage: .processing,
                detail: update.detail ?? previous.detail,
                transferredBytes: update.transferredBytes,
                totalBytes: update.totalBytes,
                succeeded: max(previous.succeeded, update.succeeded),
                failed: max(previous.failed, update.failed),
                skipped: previous.skipped
            )
        } else {
            jobs[index].progress = update
        }
        activeLogger?.recordProgress(update)
        let now = Date()
        jobs[index].updatedAt = now
        let effective = jobs[index].progress
        if effective.current > 0 {
            if let sample = lastProgressSample[jobID], effective.current > sample.current {
                let seconds = now.timeIntervalSince(sample.date)
                if seconds >= 0.15 {
                    let instantaneous = Double(effective.current - sample.current) / seconds
                    if instantaneous > 0.005 && instantaneous < 30 {
                        if let previousRate = progressRateEMA[jobID] {
                            progressRateEMA[jobID] = previousRate * 0.68 + instantaneous * 0.32
                        } else {
                            progressRateEMA[jobID] = instantaneous
                        }
                    }
                }
            }
            if lastProgressSample[jobID]?.current != effective.current {
                lastProgressSample[jobID] = (effective.current, now)
            }
        }
        persist()
        if selectedJobID == jobID { syncFacade() }
        let step = JobStep.current(for: effective)
        if lastAnnouncedStep != step {
            lastAnnouncedStep = step
            lastAnnouncedStage = update.stage
            if let l10n {
                UIAccessibility.post(notification: .announcement,
                                     argument: JobStep.spokenStatus(for: effective, l10n: l10n))
            }
        } else if update.total > 0 {
            let previous = lastAnnouncedProgress[jobID]
            let changed = previous?.current != update.current || previous?.total != update.total
            if changed {
                lastAnnouncedProgress[jobID] = (update.current, update.total)
                if (update.current == 1 || update.current == update.total || update.current % 5 == 0),
                   let l10n {
                    UIAccessibility.post(notification: .announcement,
                                         argument: JobStep.spokenStatus(for: effective, l10n: l10n))
                }
            }
        }
        // Once the server reports this job's progress by push, the app stops
        // sending its own progress notifications so nothing appears twice.
        if settings?.notificationsEnabled == true, !PushRegistrar.shared.remoteProgressJobs.contains(jobID), let l10n {
            OperationFeedback.notifyProgress(
                title: jobs[index].sourceName,
                body: JobStep.spokenStatus(for: effective, l10n: l10n),
                jobID: jobID,
                percent: JobStep.overallPercent(for: effective)
            )
        }
        if update.current > 0, update.current % 10 == 0 {
            OperationFeedback.play(.progress, theme: settings?.soundTheme ?? .off)
        }
    }

    private func handleTransportCancellation(jobID: UUID, logger: DiagnosticLogger) {
        if pauseRequested || networkPauseRequested {
            handleCancellation(jobID: jobID, logger: logger)
            return
        }
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else {
            completeCurrentTaskAndContinue(allowNext: false)
            return
        }

        let attempt = min((transportReconnectAttempts[jobID] ?? 0) + 1, 6)
        transportReconnectAttempts[jobID] = attempt
        lastProgressSample[jobID] = (jobs[index].progress.current, Date())
        let delaySeconds = min(8, 1 << min(attempt - 1, 3))
        logger.record(
            "TRANSPORT_INTERRUPTED_RECONNECT attempt=\(attempt) delay=\(delaySeconds)s "
            + "progress=\(jobs[index].progress.current)/\(jobs[index].progress.total)"
        )

        jobs[index].status = .queued
        jobs[index].automaticResumePending = true
        jobs[index].progress = ConversionProgress(
            current: jobs[index].progress.current,
            total: jobs[index].progress.total,
            stage: .processing,
            detail: l10n?.t(
                "انقطعت متابعة الاتصال لحظيًا. جارٍ إعادة الاتصال بنفس مهمة الخادم دون فقد التقدم.",
                "Connection monitoring was interrupted. Reconnecting to the same server task without losing progress."
            ),
            transferredBytes: jobs[index].progress.transferredBytes,
            totalBytes: jobs[index].progress.totalBytes,
            succeeded: jobs[index].progress.succeeded,
            failed: jobs[index].progress.failed,
            skipped: jobs[index].progress.skipped
        )
        jobs[index].errorMessage = nil
        jobs[index].updatedAt = Date()
        selectedJobID = jobID
        if let diagnostic = jobs[index].diagnosticURL { try? logger.write(to: diagnostic) }
        persist()
        syncFacade()

        completeCurrentTaskAndContinue(allowNext: false)
        transportReconnectTasks[jobID]?.cancel()
        transportReconnectTasks[jobID] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delaySeconds))
            guard !Task.isCancelled, let self else { return }
            self.transportReconnectTasks[jobID] = nil
            guard let retryIndex = self.jobs.firstIndex(where: { $0.id == jobID }),
                  self.jobs[retryIndex].status == .queued,
                  self.jobs[retryIndex].automaticResumePending == true else { return }
            self.jobs[retryIndex].automaticResumePending = false
            self.jobs[retryIndex].updatedAt = Date()
            self.persist()
            self.syncFacade()
            self.processNextIfPossible(preferredJobID: jobID)
        }
    }

    private func handleCancellation(jobID: UUID, logger: DiagnosticLogger) {
        logger.record(networkPauseRequested ? "WAITING_NETWORK" : (pauseRequested ? "PAUSED" : "CANCELLED"))
        if let index = jobs.firstIndex(where: { $0.id == jobID }) {
            if networkPauseRequested {
                jobs[index].status = .waitingForNetwork
                jobs[index].progress = progressReplacingStage(jobs[index].progress, .waitingForNetwork)
            } else if pauseRequested {
                jobs[index].status = .paused
                jobs[index].progress = progressReplacingStage(jobs[index].progress, .paused)
            } else if jobs[index].status == .running {
                jobs[index].status = .cancelled
            }
            jobs[index].updatedAt = Date()
            if let diagnostic = jobs[index].diagnosticURL { try? logger.write(to: diagnostic) }
        }
        persist()
        syncFacade()
        completeCurrentTaskAndContinue(allowNext: !pauseRequested && !networkPauseRequested)
    }

    private func finish(jobID: UUID, error: Error, logger: DiagnosticLogger?, output: URL?) {
        if let urlError = error as? URLError, urlError.code == .cancelled, let logger {
            handleTransportCancellation(jobID: jobID, logger: logger)
            return
        }
        logger?.recordError(error, context: "job-finish")
        DiagnosticLogger.recordGlobal("JOB failed appJob=\(jobID.uuidString) type=\(String(reflecting: type(of: error))) description=\(error.localizedDescription)")
        if let index = jobs.firstIndex(where: { $0.id == jobID }) {
            if let diagnostic = jobs[index].diagnosticURL { try? logger?.write(to: diagnostic) }
            if Self.isNetworkWaitError(error) {
                jobs[index].status = .waitingForNetwork
                jobs[index].progress = progressReplacingStage(jobs[index].progress, .waitingForNetwork)
            } else {
                jobs[index].status = .failed
            }
            jobs[index].errorMessage = l10n.map { Self.localized(error, l10n: $0) } ?? error.localizedDescription
            jobs[index].updatedAt = Date()
            if let output, FileManager.default.fileExists(atPath: output.path), jobs[index].status == .failed {
                try? FileManager.default.removeItem(at: output)
            }
        }
        persist()
        syncFacade()
        OperationFeedback.play(.failed, theme: settings?.soundTheme ?? .gentle)
        if settings?.notificationsEnabled == true,
           !Self.isNetworkWaitError(error),
           let l10n {
            OperationFeedback.notifyFailure(
                title: l10n.t("تعذرت مهمة بصير", "Basir task failed"),
                body: Self.localized(error, l10n: l10n),
                jobID: jobID
            )
        }
        PushRegistrar.shared.jobFinished(jobID)
        completeCurrentTaskAndContinue(allowNext: false)
    }

    private func completeCurrentTaskAndContinue(allowNext: Bool = true) {
        backgroundExecution.end()
        if let selectedJobID { lastAnnouncedProgress.removeValue(forKey: selectedJobID) }
        jobTask = nil
        pauseRequested = false
        networkPauseRequested = false
        activeLogger = nil
        if allowNext { processNextIfPossible() }
    }

    private func networkDidChange(_ snapshot: NetworkSnapshot) {
        DiagnosticLogger.recordGlobal("NETWORK connected=\(snapshot.isConnected) wifi=\(snapshot.usesWiFi) expensive=\(snapshot.isExpensive) constrained=\(snapshot.isConstrained)")
        activeLogger?.recordNetwork(snapshot, reason: "path-change")
        // NWPathMonitor can briefly report an unsatisfied path while iOS switches
        // interfaces or refreshes the route. Do not turn that transient signal into
        // a false "Waiting for network" state or cancel a healthy conversion.
        if snapshot.isConnected {
            networkLossTask?.cancel()
            networkLossTask = nil
            resendPendingCancellations()
            if settings?.automaticResume == true { processNextIfPossible() }
            return
        }

        guard activeIndex != nil else { return }
        networkLossTask?.cancel()
        networkLossTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let self else { return }
            guard !NetworkMonitor.shared.snapshot.isConnected, let index = self.activeIndex else { return }
            self.networkPauseRequested = true
            self.jobs[index].status = .waitingForNetwork
            self.jobs[index].progress = self.progressReplacingStage(self.jobs[index].progress, .waitingForNetwork)
            self.jobs[index].errorMessage = self.l10n.map { Self.localized(BasirError.networkUnavailable, l10n: $0) }
            self.persist()
            self.syncFacade()
            self.jobTask?.cancel()
        }
    }

    func resumeInterruptedJobsIfNeeded() {
        guard settings?.automaticResume == true else { return }
        var changed = false
        for index in jobs.indices where jobs[index].status == .paused && jobs[index].automaticResumePending == true {
            jobs[index].status = .queued
            jobs[index].automaticResumePending = false
            jobs[index].errorMessage = nil
            jobs[index].updatedAt = Date()
            changed = true
        }
        if changed { persist(); syncFacade() }
        processNextIfPossible()
    }

    /// Runs while iOS gives the app background time (refresh or processing
    /// task). It resumes interrupted work and keeps the task alive until the
    /// queue is idle, instead of returning at once and being suspended again.
    private func resumeQueueFromBackground() async {
        DiagnosticLogger.recordGlobal("BACKGROUND wake pending=\(pendingJobCount)")
        resumeInterruptedJobsIfNeeded()
        while !Task.isCancelled, hasBackgroundWorkInFlight {
            try? await Task.sleep(for: .seconds(1))
        }
        DiagnosticLogger.recordGlobal("BACKGROUND wake finished pending=\(pendingJobCount)")
    }

    private var hasBackgroundWorkInFlight: Bool {
        jobTask != nil
            || !transportReconnectTasks.isEmpty
            || jobs.contains(where: { $0.status == .running })
    }

    private func route(stagedURLs: [URL], to operation: OperationKind, l10n: L10n) {
        if let first = stagedURLs.first, stagedURLs.count == 1 {
            routedExternalDocument = RoutedExternalDocument(id: UUID(), url: first, operation: operation)
            routedExternalBatch = nil
        } else {
            routedExternalBatch = RoutedExternalBatch(id: UUID(), urls: stagedURLs, operation: operation)
            routedExternalDocument = nil
        }
        UIAccessibility.post(
            notification: .announcement,
            argument: operation == .convert
                ? l10n.t("تم تجهيز \(stagedURLs.count) للتحويل.", "Prepared \(stagedURLs.count) item(s) for conversion.")
                : l10n.t("تم تجهيز \(stagedURLs.count) للترجمة.", "Prepared \(stagedURLs.count) item(s) for translation.")
        )
    }

    private func persist() {
        let snapshot = jobs
        if let l10n { liveActivity.sync(jobs: snapshot, l10n: l10n) }
        Task { try? await jobStore.save(snapshot) }
    }

    private func syncFacade() {
        guard let job = selectedJob else {
            status = .idle
            progress = .init(current: 0, total: 0, stage: .preparing, detail: nil)
            sourceName = ""
            resultURL = nil
            diagnosticURL = nil
            errorMessage = nil
            return
        }
        status = job.status
        progress = job.progress
        sourceName = job.sourceName
        resultURL = job.resultURL
        diagnosticURL = job.diagnosticURL
        errorMessage = job.errorMessage
    }

    private func progressReplacingStage(_ progress: ConversionProgress, _ stage: ConversionStage) -> ConversionProgress {
        progress.replacingStage(stage)
    }

    private static func isNetworkWaitError(_ error: Error) -> Bool {
        if error is URLError { return true }
        guard let basir = error as? BasirError else { return false }
        switch basir {
        case .networkUnavailable, .wifiRequired, .constrainedNetwork:
            return true
        default:
            return false
        }
    }

    private static func localized(_ error: Error, l10n: L10n) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return l10n.t("لا يوجد اتصال بالإنترنت. ستستأنف المهمة عند عودة الشبكة.",
                              "There is no internet connection. The task will resume when the network returns.")
            case .timedOut:
                return l10n.t("انتهت مهلة الاتصال بالخدمة.", "The service connection timed out.")
            case .cannotFindHost, .dnsLookupFailed:
                return l10n.t("تعذر العثور على عنوان الخدمة.", "The service address could not be resolved.")
            case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate:
                return l10n.t("تعذر إنشاء اتصال مشفر موثوق بالخدمة.",
                              "A trusted encrypted connection to the service could not be established.")
            default:
                return l10n.t("تعذر الاتصال بالشبكة: \(urlError.localizedDescription)",
                              "Network error: \(urlError.localizedDescription)")
            }
        }
        guard let basir = error as? BasirError else {
            return l10n.t("تعذّرت العملية: \(error.localizedDescription)",
                          "The operation failed: \(error.localizedDescription)")
        }
        switch basir {
        case .notConfigured:
            return l10n.t("تعذر بدء المهمة حاليًا.",
                          "The task cannot start right now.")
        case .unsupportedFile:
            return l10n.t("نوع الملف غير مدعوم لهذه المهمة.", "This file type is not supported for this task.")
        case .invalidFileContent:
            return l10n.t("محتوى الملف لا يطابق نوعه، لذلك أوقفه التطبيق لحمايتك.",
                          "The file content does not match its type, so the app stopped for your protection.")
        case .emptyDocument:
            return l10n.t("لا يحتوي الملف على محتوى قابل للقراءة.", "The file contains no readable content.")
        case .noReadablePages:
            return l10n.t("تعذّر تحويل أي صفحة.", "No page could be converted.")
        case .invalidServerURL:
            return l10n.t("تعذر إنشاء اتصال آمن بالخدمة.",
                          "A secure service connection could not be created.")
        case .fileTooLarge:
            return l10n.t("حجم الملف أكبر من الحد المسموح وهو 200 ميجابايت.",
                          "The file is larger than the 200 MB limit.")
        case .networkUnavailable:
            return l10n.t("لا يوجد اتصال. ستبقى المهمة في الانتظار.",
                          "There is no connection. The task will remain queued.")
        case .wifiRequired:
            return l10n.t("هذه المهمة تنتظر شبكة Wi‑Fi حسب إعدادك.",
                          "This task is waiting for Wi-Fi, as requested in Settings.")
        case .constrainedNetwork:
            return l10n.t("وضع البيانات المنخفضة مفعّل، والمهمة تنتظر شبكة مناسبة.",
                          "Low Data Mode is active. The task is waiting for a suitable network.")
        case .authenticationFailed:
            return l10n.t("تعذر التحقق من الاتصال. حدّث التطبيق إذا استمرت المشكلة.",
                          "The connection could not be verified. Update the app if the problem continues.")
        case .rateLimited(let seconds):
            return seconds.map {
                l10n.t("الخدمة مشغولة. أعد المحاولة بعد \(Int($0)) ثانية.",
                       "The service is busy. Retry after \(Int($0)) seconds.")
            } ?? l10n.t("الخدمة مشغولة مؤقتًا.", "The service is temporarily busy.")
        case .invalidServerContentType:
            return l10n.t("وصل نوع ملف غير متوقع بدل Word.",
                          "An unexpected file type was returned instead of Word.")
        case .checksumMismatch:
            return l10n.t("فشل فحص سلامة الملف المنزّل.", "The downloaded file failed its integrity check.")
        case .passwordProtectedPDF:
            return l10n.t("ملف PDF محمي بكلمة مرور. افتحه واحفظ نسخة غير محمية أولًا.",
                          "The PDF is password protected. Open it and save an unlocked copy first.")
        case .invalidPageSelection:
            return l10n.t("نطاق الصفحات غير صالح. مثال صحيح: 1-20، 25، 30-40.",
                          "The page range is invalid. Example: 1-20, 25, 30-40.")
        case .invalidResponse:
            return l10n.t("وصل رد غير مكتمل من الخدمة.", "The service returned an incomplete result.")
        case .conversionFailed(let message):
            if message.contains("401") || message.contains("403") {
                return l10n.t("تعذر التحقق من بيانات الاتصال.", "The connection credentials were rejected.")
            }
            if message.contains("429") {
                return l10n.t("الخدمة مشغولة أو وصل الحساب إلى حده المؤقت.",
                              "The service is busy or the account reached a temporary limit.")
            }
            return l10n.t("تعذر إكمال العملية. يمكنك إعادة المحاولة من نفس النقطة.",
                          "The operation could not be completed. You can retry from the same checkpoint.")
        }
    }

}

/// Where a task was when iOS stopped the app in the background, which
/// decides what is true to tell the person.
enum BackgroundPausePhase: Equatable {
    /// The file had not finished uploading: nothing happens until Basir opens.
    case uploading
    /// The server has the file and is converting it without the app.
    case serverWorking
    /// The server finished; only saving the result to the iPhone remains.
    case serverFinished

    init(stage: ConversionStage) {
        switch stage {
        case .preparing, .waitingForNetwork, .uploading, .paused: self = .uploading
        case .processing, .finalising: self = .serverWorking
        case .downloading, .done: self = .serverFinished
        }
    }

    @MainActor
    func statusMessage(l10n: L10n) -> String {
        switch self {
        case .uploading:
            return l10n.t("توقف رفع الملف لأن iOS أوقف بصير في الخلفية. سيُكمل بصير الرفع عند فتحه.",
                          "The upload stopped because iOS paused Basir in the background. Basir finishes it when you open it.")
        case .serverWorking:
            return l10n.t("خادم بصير يواصل التحويل. سيتابع التطبيق ويُنزل الملف عند فتحه.",
                          "The Basir server keeps converting. The app checks back and downloads the file when you open it.")
        case .serverFinished:
            return l10n.t("ملف Word جاهز على خادم بصير. سيُنزَّل إلى جهازك عند فتح بصير.",
                          "The Word file is ready on the Basir server. It downloads to your iPhone when you open Basir.")
        }
    }

    @MainActor
    func notificationBody(percent: Int, l10n: L10n) -> String {
        switch self {
        case .uploading:
            return l10n.t("توقف الرفع عند \(percent)٪ لأن iOS أوقف بصير في الخلفية. افتح بصير لإكماله.",
                          "The upload stopped at \(percent)% because iOS paused Basir in the background. Open Basir to finish it.")
        case .serverWorking:
            return l10n.t("خادم بصير يواصل التحويل، \(percent)٪.",
                          "The Basir server keeps converting, \(percent)%.")
        case .serverFinished:
            return l10n.t("ملف Word جاهز. افتح بصير لحفظه على جهازك.",
                          "The Word file is ready. Open Basir to save it to your iPhone.")
        }
    }
}
