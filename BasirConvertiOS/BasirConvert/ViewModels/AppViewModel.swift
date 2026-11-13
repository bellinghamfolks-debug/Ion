import Foundation
import UIKit
import Combine
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
    @Published var queuePaused = UserDefaults.standard.bool(forKey: "basir_queue_paused") {
        didSet { UserDefaults.standard.set(queuePaused, forKey: "basir_queue_paused") }
    }
    @Published var jobs: [BasirJob] = []
    @Published var selectedJobID: UUID?
    @Published private(set) var status: JobStatus = .idle
    @Published private(set) var progress = ConversionProgress(
        current: 0, total: 0, stage: .preparing, detail: nil
    )
    @Published private(set) var sourceName = ""
    @Published private(set) var resultURL: URL?
    @Published private(set) var diagnosticURL: URL?
    @Published private(set) var errorMessage: String?
    @Published var externalImportCandidate: ExternalImportCandidate?
    @Published var externalImportBatch: ExternalImportBatch?
    @Published var routedExternalDocument: RoutedExternalDocument?
    @Published var routedExternalBatch: RoutedExternalBatch?
    @Published var externalImportError: String?
    @Published var isJobPresented = false
    @Published var isSettingsPresented = false

    // Members without `private` are shared with the AppViewModel+*.swift
    // extensions; views use only the published state and the public methods.
    private var importReservations = Set<String>()
    private let engine = ConversionEngine()
    private let jobStore = PersistentJobStore()
    let backgroundExecution = BackgroundExecution.shared
    var jobTask: Task<Void, Never>?
    var externalImportTask: Task<Void, Never>?
    private var lastAnnouncedStage: ConversionStage?
    private var lastAnnouncedStep: JobStep?
    private let liveActivity = JobLiveActivityController()
    private var lastAnnouncedProgress: [UUID: (current: Int, total: Int)] = [:]
    var pauseRequested = false
    /// One-time notices, so iOS waking and stopping the app repeatedly in
    /// the background never repeats them.
    var cancellationTasks: [UUID: Task<Void, Never>] = [:]
    var networkPauseRequested = false
    private var networkCancellable: AnyCancellable?
    var networkLossTask: Task<Void, Never>?
    var transportReconnectTasks: [UUID: Task<Void, Never>] = [:]
    var transportReconnectAttempts: [UUID: Int] = [:]
    var rateEstimator = ProgressRateEstimator()
    var activeLogger: DiagnosticLogger?
    var lastConfiguration: ServerConfiguration?
    weak var settings: SettingsStore?
    weak var l10n: L10n?
    private weak var outputLibrary: OutputLibraryStore?

    var isRunning: Bool { status == .running }
    var activeJob: BasirJob? { jobs.first(where: { $0.status == .running }) }
    var selectedJob: BasirJob? {
        guard let selectedJobID else { return activeJob ?? jobs.first }
        return jobs.first(where: { $0.id == selectedJobID })
    }
    /// The job shown in the compact bar above the tab bar.
    var barJob: BasirJob? { JobQueuePolicy.barJob(in: jobs) }
    var pendingJobCount: Int { JobQueuePolicy.pendingCount(in: jobs) }
    var elapsedTime: TimeInterval {
        guard let started = selectedJob?.startedAt else { return 0 }
        return max(0, (selectedJob?.completedAt ?? Date()).timeIntervalSince(started))
    }
    var estimatedRemaining: TimeInterval? {
        guard let job = selectedJob else { return nil }
        return rateEstimator.remaining(jobID: job.id, current: progress.current, total: progress.total)
    }

    init(restoringSavedJobs: Bool = true) {
        guard restoringSavedJobs else { return }
        Task { [weak self] in
            guard let self else { return }
            let loaded = await jobStore.load()
            // Completed and cancelled tasks from an earlier launch have
            // nothing left to show: a completed task's Word file is in My
            // Files. Drop the task and its copy of the source, and keep any
            // result.
            let completed = loaded.filter(JobQueuePolicy.isOver)
            for job in completed { await jobStore.removeFiles(for: job, keepingResult: true) }
            let restored = loaded.filter { !JobQueuePolicy.isOver($0) }
            // Before any task starts, drop transfers an earlier launch left
            // behind; nothing waits for them and they slow new transfers.
            await BackgroundTransferCoordinator.shared.cancelTransfersFromEarlierLaunch()
            jobs = restored
            // Older clients paused only the phone. Reconcile manual pauses
            // even when attach ran before the task store finished loading.
            for index in jobs.indices where jobs[index].status == .paused
                && jobs[index].automaticResumePending != true && jobs[index].serverCancelPending == nil {
                jobs[index].serverCancelPending = true
            }
            persist()
            resendPendingCancellations()
            selectedJobID = JobQueuePolicy.initialSelection(in: restored)
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
        JobWatcher.shared.onFinished = { [weak self] entry, status, _ in
            // The server finished while Basir was away: fetch and save the
            // result now, in the short time iOS gives this wake-up.
            guard entry.work == .conversion, status == "completed" || status == "partial" else { return }
            self?.resumeInterruptedJobsIfNeeded()
        }
        JobWatcher.shared.isStillActive = { [weak self] entry in
            // Summaries are followed by their own screen and end on the server.
            guard entry.work == .conversion, let appJobID = entry.appJobID else { return true }
            guard let self else { return true }
            guard let job = self.jobs.first(where: { $0.id == appJobID }) else { return false }
            return job.status == .running || JobQueuePolicy.mayStillRunOnServer.contains(job.status)
        }
        JobWatcher.shared.prune()
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
        // The task appears in the compact bar instead of covering the screen.
        UIAccessibility.post(
            notification: .announcement,
            argument: l10n.t("تمت إضافة المهمة. يمكنك متابعة تقدمها من الشريط أسفل الشاشة أو من تبويب «المهام».",
                             "Task added. Follow its status in the bar at the bottom or in the Tasks tab.")
        )
        Task { [weak self] in
            guard let self else { return }
            var newJobs: [BasirJob] = []
            var reserved: [String] = []
            defer { reserved.forEach { self.importReservations.remove($0) } }
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
                    let checksum = try await Task.detached { try DocumentInspector.sha256(prepared.0) }.value
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.sortedKeys]
                    let reservation = checksum + ":" + (try encoder.encode(options)).base64EncodedString()
                    guard importReservations.insert(reservation).inserted else {
                        try? FileManager.default.removeItem(at: prepared.0.deletingLastPathComponent())
                        externalImportError = l10n.t("يجري بالفعل تجهيز هذا الملف بالإعدادات نفسها؛ لم يُكرّر الطلب.", "This file is already being prepared with the same settings; no duplicate request was created.")
                        continue
                    }
                    reserved.append(reservation)
                    let duplicates = (jobs + newJobs).filter { JobQueuePolicy.pending.contains($0.status) && $0.options == options && $0.sourceMetadata?.byteCount == prepared.1.byteCount }
                    let duplicate = try await Task.detached {
                        guard !duplicates.isEmpty else { return false }
                        let hash = try DocumentInspector.sha256(prepared.0)
                        return duplicates.contains { (try? DocumentInspector.sha256($0.sourceURL)) == hash }
                    }.value
                    if duplicate {
                        try? FileManager.default.removeItem(at: prepared.0.deletingLastPathComponent())
                        externalImportError = l10n.t("الملف نفسه بالإعدادات نفسها موجود في قائمة المهام. لم يُرسل طلب إضافي.", "This file with the same settings is already queued. No extra request was sent.")
                        continue
                    }
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

    func toggleQueue() {
        queuePaused.toggle()
        if !queuePaused { processNextIfPossible() }
    }

    func prioritize(_ id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }), jobs[index].status != .running else { return }
        let job = jobs.remove(at: index)
        jobs.insert(job, at: 0)
        persist()
        if !queuePaused { processNextIfPossible() }
    }

    func selectJob(_ id: UUID) {
        guard jobs.contains(where: { $0.id == id }) else { return }
        selectedJobID = id
        syncFacade()
        isJobPresented = true
    }

    func pause() {
        guard let index = activeIndex else { return }
        let jobID = jobs[index].id
        activeLogger?.record("USER pause requested")
        pauseRequested = true
        networkPauseRequested = false
        jobs[index].status = .paused
        jobs[index].automaticResumePending = false
        // Stop paid server work through its durable cancellation barrier.
        // Keep the request ID and checkpoints for an explicit resume.
        jobs[index].serverCancelPending = true
        jobs[index].errorMessage = l10n?.t(
            "جارٍ طلب الإيقاف على الخادم. قد تُحتسب الطلبات التي بدأت بالفعل؛ لم يُؤكَّد التوقف بعد.",
            "Requesting a server stop. Requests already in progress may be charged; stopping is not confirmed yet."
        )
        jobs[index].progress = progressReplacingStage(jobs[index].progress, .paused)
        jobs[index].updatedAt = Date()
        persist()
        syncFacade()
        jobTask?.cancel()
        JobWatcher.shared.stop(id: jobID.uuidString)
        JobNotifier.remove(jobID.uuidString)
        PushRegistrar.shared.jobFinished(jobID)
        sendServerCancellation(jobID: jobID)
        OperationFeedback.play(.paused, theme: settings?.soundTheme ?? .gentle)
    }

    func resume(jobID: UUID? = nil) {
        let id = jobID ?? selectedJobID
        guard let id, let index = jobs.firstIndex(where: { $0.id == id }),
              JobQueuePolicy.resumable.contains(jobs[index].status) else { return }
        // Restarting before the server confirmed the cancellation could let
        // the late cancellation stop the new run. Wait for the confirmation.
        if jobs[index].serverCancelPending == true {
            if let l10n {
                UIAccessibility.post(notification: .announcement, argument: l10n.t(
                    "جارٍ تأكيد توقف المعالجة على الخادم. انتظر قليلًا ثم أعد المحاولة.",
                    "The server stop is being confirmed. Please wait a moment, then try again."))
            }
            sendServerCancellation(jobID: id)
            return
        }
        guard jobTask == nil else { return }
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
    func retryFailedItems() {
        guard let job = selectedJob, !job.failedItems.isEmpty,
              let configuration = settings?.configuration, let l10n else { return }
        guard job.sourceURL.pathExtension.lowercased() == "pdf", job.failedItems.contains(where: { $0 > 0 }) else { resume(); return }
        do {
            let data = try JSONEncoder().encode(job.options)
            var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            json["pageSelection"] = Set(job.failedItems.filter { $0 > 0 }).sorted().map(String.init).joined(separator: ",")
            let options = try JSONDecoder().decode(ConversionOptions.self, from: JSONSerialization.data(withJSONObject: json))
            start(pickerURL: job.sourceURL, options: options, configuration: configuration, l10n: l10n)
        } catch { externalImportError = Self.localized(error, l10n: l10n) }
    }

    func cancel() {
        let index = activeIndex
            ?? selectedJobID.flatMap { id in jobs.firstIndex(where: { $0.id == id }) }
        guard let index, JobQueuePolicy.cancellable.contains(jobs[index].status) else { return }
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
            "جارٍ إلغاء المهمة على خادم بصير…",
            "Cancelling the task on Basir’s server…"
        )
        jobs[index].updatedAt = Date()
        persist()
        syncFacade()
        if wasRunning { jobTask?.cancel() }
        JobNotifier.remove(jobID.uuidString)
        JobWatcher.shared.stop(id: jobID.uuidString)
        PushRegistrar.shared.jobFinished(jobID)
        sendServerCancellation(jobID: jobID)
        processNextIfPossible()
    }

    func removeJob(_ id: UUID, deleteResult: Bool = false) {
        guard let index = jobs.firstIndex(where: { $0.id == id }), jobs[index].status != .running else { return }
        let removed = jobs.remove(at: index)
        // Removing a task that may still be converting on the server (paused,
        // queued, waiting, or with an unconfirmed cancellation) stops it there.
        if JobQueuePolicy.mayStillRunOnServer.contains(removed.status) || removed.serverCancelPending == true,
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
        // A deleted task is not followed and not announced any more.
        JobWatcher.shared.stop(id: id.uuidString)
        JobNotifier.remove(id.uuidString)
        Task { await jobStore.removeFiles(for: removed, keepingResult: !deleteResult) }
        if selectedJobID == id { selectedJobID = jobs.first?.id }
        persist()
        syncFacade()
    }

    func moveJobs(from offsets: IndexSet, to destination: Int) {
        jobs.move(fromOffsets: offsets, toOffset: destination)
        persist()
    }

    /// Reorders the tasks the Tasks list shows (completed ones are hidden).
    func moveListedJobs(from offsets: IndexSet, to destination: Int) {
        var listed = JobQueuePolicy.listed(jobs)
        listed.move(fromOffsets: offsets, toOffset: destination)
        jobs = JobQueuePolicy.reordered(jobs, listedOrder: listed.map(\.id))
        persist()
    }

    func dismissJob() { isJobPresented = false }

    var activeIndex: Int? { jobs.firstIndex(where: { $0.status == .running }) }

    func processNextIfPossible(preferredJobID: UUID? = nil) {
        guard jobTask == nil, !queuePaused,
              let settings,
              let l10n else { return }
        guard let index = JobQueuePolicy.nextIndex(in: jobs, preferred: preferredJobID) else { return }
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
                "تعذر بدء المهمة. أعد فتح بصير ثم حاول مرة أخرى.",
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
                    serverJobCreated: { [language = l10n.language.rawValue, title = snapshot.sourceName] serverJobID in
                        Task { @MainActor in
                            if let index = self.jobs.firstIndex(where: { $0.id == jobID }) {
                                self.jobs[index].remoteJobID = serverJobID
                                self.persist()
                                guard self.jobs[index].status == .running else {
                                    if self.jobs[index].serverCancelPending == true {
                                        self.sendServerCancellation(jobID: jobID)
                                    }
                                    return
                                }
                            }
                            // Followed in the background from now on, with or without push.
                            JobWatcher.shared.watch(id: jobID.uuidString, serverJobID: serverJobID,
                                                    work: .conversion, title: title,
                                                    arabic: language == "ar", appJobID: jobID)
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
                let audited = await Task.detached {
                    DocumentConsistencyAudit.review(source: source, output: output, options: snapshot.options, report: outcome.quality)
                }.value
                try Task.checkCancellation()
                guard let finishedIndex = jobs.firstIndex(where: { $0.id == jobID }), jobs[finishedIndex].status == .running else { return }
                jobs[finishedIndex].resultPath = output.path
                jobs[finishedIndex].failedItems = outcome.failedItems
                jobs[finishedIndex].skippedBlankItems = outcome.skippedBlankItems
                jobs[finishedIndex].executedModel = outcome.executedModel
                jobs[finishedIndex].qualityReport = audited
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
                JobWatcher.shared.stop(id: jobID.uuidString)
                if UIApplication.shared.applicationState == .active {
                    // Basir is open and says so itself; clear the old notice.
                    JobNotifier.remove(jobID.uuidString)
                } else {
                    JobNotifier.show(JobNotifier.finished(task: .conversion, title: output.lastPathComponent,
                                                          partial: !outcome.failedItems.isEmpty,
                                                          arabic: l10n.isArabic),
                                     id: jobID.uuidString, openJob: jobID)
                }
                UIAccessibility.post(
                    notification: .announcement,
                    argument: outcome.failedItems.isEmpty
                        ? l10n.t("اكتملت المهمة. ملف Word محفوظ في «ملفاتي».", "Task complete. Your Word file is in My Files.")
                        : l10n.t("اكتملت المهمة جزئيًا. عدد العناصر المكتملة: \(outcome.succeededItems). عدد العناصر التي تحتاج إلى إعادة المحاولة: \(outcome.failedItems.count).",
                                 "A partial result is ready. Completed items: \(outcome.succeededItems). Items to retry: \(outcome.failedItems.count).")
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

    private func apply(_ update: ConversionProgress, to jobID: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }), jobs[index].status == .running else { return }
        jobs[index].progress = JobQueuePolicy.merged(previous: jobs[index].progress, update: update)
        activeLogger?.recordProgress(update)
        let now = Date()
        jobs[index].updatedAt = now
        let effective = jobs[index].progress
        rateEstimator.record(jobID: jobID, current: effective.current, at: now)
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
                if JobQueuePolicy.shouldAnnounce(current: update.current, total: update.total), let l10n {
                    UIAccessibility.post(notification: .announcement,
                                         argument: JobStep.spokenStatus(for: effective, l10n: l10n))
                }
            }
        }
        // Progress is on screen while Basir is open; the watcher remembers it
        // for the one notice shown when Basir is left.
        JobWatcher.shared.noteProgress(id: jobID.uuidString, percent: JobStep.overallPercent(for: effective),
                                       uploading: [.preparing, .uploading].contains(effective.stage))
        if update.current > 0, update.current % 10 == 0 {
            OperationFeedback.play(.progress, theme: settings?.soundTheme ?? .off)
        }
    }

    func handleCancellation(jobID: UUID, logger: DiagnosticLogger) {
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
        if let job = jobs.first(where: { $0.id == jobID }),
           (job.status == .paused && job.automaticResumePending != true) || job.status == .cancelled {
            // A late HTTP/storage error from the cancelled local producer
            // must not overwrite the person's pause or its pending stop.
            completeCurrentTaskAndContinue(allowNext: false)
            return
        }
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
        if !Self.isNetworkWaitError(error), let l10n {
            JobWatcher.shared.stop(id: jobID.uuidString)
            if UIApplication.shared.applicationState == .active {
                JobNotifier.remove(jobID.uuidString)
            } else {
                let title = jobs.first(where: { $0.id == jobID })?.sourceName ?? l10n.t("بصير", "Basir")
                JobNotifier.show(JobNotifier.failed(title: title, reason: Self.localized(error, l10n: l10n),
                                                    arabic: l10n.isArabic),
                                 id: jobID.uuidString, openJob: jobID)
            }
        }
        PushRegistrar.shared.jobFinished(jobID)
        completeCurrentTaskAndContinue(allowNext: false)
    }

    func completeCurrentTaskAndContinue(allowNext: Bool = true) {
        backgroundExecution.end()
        if let selectedJobID { lastAnnouncedProgress.removeValue(forKey: selectedJobID) }
        jobTask = nil
        pauseRequested = false
        networkPauseRequested = false
        activeLogger = nil
        if allowNext { processNextIfPossible() }
    }

    func persist() {
        let snapshot = jobs
        if let l10n { liveActivity.sync(jobs: snapshot, l10n: l10n) }
        Task { try? await jobStore.save(snapshot) }
    }

    func syncFacade() {
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

    func progressReplacingStage(_ progress: ConversionProgress, _ stage: ConversionStage) -> ConversionProgress {
        progress.replacingStage(stage)
    }

    static func localized(_ error: Error, l10n: L10n) -> String {
        ErrorLocalizer.message(for: error, l10n: l10n)
    }

    static func isNetworkWaitError(_ error: Error) -> Bool {
        ErrorLocalizer.isNetworkWait(error)
    }
}
