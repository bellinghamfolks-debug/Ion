import Foundation
import UIKit

/// What happens when the connection drops or iOS limits background time:
/// reconnecting, waiting for the network, and resuming the queue.
extension AppViewModel {
    func networkDidChange(_ snapshot: NetworkSnapshot) {
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
    func resumeQueueFromBackground() async {
        DiagnosticLogger.recordGlobal("BACKGROUND wake pending=\(pendingJobCount)")
        resumeInterruptedJobsIfNeeded()
        while !Task.isCancelled, hasBackgroundWorkInFlight {
            try? await Task.sleep(for: .seconds(1))
        }
        DiagnosticLogger.recordGlobal("BACKGROUND wake finished pending=\(pendingJobCount)")
    }

    var hasBackgroundWorkInFlight: Bool {
        jobTask != nil
            || !transportReconnectTasks.isEmpty
            || jobs.contains(where: { $0.status == .running })
    }

    func suspendForSystemBackgroundLimit(jobID: UUID) {
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
        // iOS stopping Basir is not a pause: the server keeps converting and
        // JobWatcher reports its quarters and its end. Only two things are
        // worth a notice here, each shown once (JobNotifier never repeats or
        // goes backwards).
        let id = jobID.uuidString
        let title = jobs[index].sourceName
        let arabic = l10n?.isArabic ?? true
        switch phase {
        case .serverWorking:
            return
        case .serverFinished:
            JobNotifier.show(JobNotifier.ready(task: .conversion, title: title, arabic: arabic), id: id, openJob: jobID)
        case .uploading:
            JobNotifier.show(JobNotifier.uploadNeedsApp(title: title, percent: percent, arabic: arabic),
                             id: id, openJob: jobID)
        }
    }

    /// Called when a background task iOS granted is about to expire.
    func suspendRunningJobForBackgroundExpiry() {
        guard let running = activeJob else { return }
        suspendForSystemBackgroundLimit(jobID: running.id)
    }

    func handleTransportCancellation(jobID: UUID, logger: DiagnosticLogger) {
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
        rateEstimator.restart(jobID: jobID, current: jobs[index].progress.current, at: Date())
        let delaySeconds = JobQueuePolicy.reconnectDelay(attempt: attempt)
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
                "انقطع الاتصال مؤقتًا. جارٍ إعادة الاتصال لمتابعة المهمة الحالية؛ تقدمك محفوظ.",
                "The connection was briefly interrupted. Reconnecting to your current task. Your progress is saved."
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
}
