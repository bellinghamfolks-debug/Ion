import Foundation

/// The queue's decisions, kept free of UI and networking so they can be
/// tested directly: which task runs next, which one the compact bar shows,
/// how progress may move, and how long to wait before trying again.
enum JobQueuePolicy {
    static let runnable: Set<JobStatus> = [.queued, .waitingForNetwork]
    static let pending: Set<JobStatus> = [.queued, .waitingForNetwork, .paused, .running]
    static let resumable: Set<JobStatus> = [.paused, .failed, .cancelled, .waitingForNetwork, .partial]
    static let cancellable: Set<JobStatus> = [.running, .queued, .waitingForNetwork, .paused, .failed, .partial]
    /// Removing a task in these states also stops it on the server.
    static let mayStillRunOnServer: Set<JobStatus> = [.paused, .queued, .waitingForNetwork]

    /// The task to start: the preferred one when it is runnable, otherwise
    /// the first runnable task in the person's order.
    static func nextIndex(in jobs: [BasirJob], preferred: UUID? = nil) -> Int? {
        if let preferred,
           let index = jobs.firstIndex(where: { $0.id == preferred && runnable.contains($0.status) }) {
            return index
        }
        return jobs.firstIndex(where: { runnable.contains($0.status) })
    }

    /// The task shown in the compact bar above the tab bar.
    static func barJob(in jobs: [BasirJob]) -> BasirJob? {
        jobs.first(where: { $0.status == .running })
            ?? jobs.first(where: { [.queued, .waitingForNetwork, .paused].contains($0.status) })
    }

    static func pendingCount(in jobs: [BasirJob]) -> Int {
        jobs.filter { pending.contains($0.status) }.count
    }

    /// The task selected after launch: unfinished work first.
    static func initialSelection(in jobs: [BasirJob]) -> UUID? {
        jobs.first(where: { [.paused, .waitingForNetwork, .queued].contains($0.status) })?.id ?? jobs.first?.id
    }

    /// Page progress never moves backwards while the server processes a
    /// file: a late or partial report keeps the higher count.
    static func merged(previous: ConversionProgress, update: ConversionProgress) -> ConversionProgress {
        guard update.stage == .processing,
              previous.current > 0,
              update.total == 0 || update.current < previous.current else { return update }
        return ConversionProgress(
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
    }

    /// Seconds before reconnecting after the transport dropped: 1, 2, 4, then 8.
    static func reconnectDelay(attempt: Int) -> Int {
        min(8, 1 << min(max(attempt, 1) - 1, 3))
    }

    /// Seconds before asking the server again to confirm a cancellation.
    static func cancellationRetryDelay(attempt: Int) -> Int {
        min(60, 2 << min(max(attempt, 0), 5))
    }

    /// Spoken progress every fifth item, plus the first and the last.
    static func shouldAnnounce(current: Int, total: Int) -> Bool {
        total > 0 && (current == 1 || current == total || current % 5 == 0)
    }
}

/// Pages per second, smoothed, for the "time remaining" estimate.
struct ProgressRateEstimator {
    private(set) var rates: [UUID: Double] = [:]
    private var samples: [UUID: (current: Int, date: Date)] = [:]

    mutating func record(jobID: UUID, current: Int, at now: Date) {
        guard current > 0 else { return }
        if let sample = samples[jobID], current > sample.current {
            let seconds = now.timeIntervalSince(sample.date)
            if seconds >= 0.15 {
                let instantaneous = Double(current - sample.current) / seconds
                if instantaneous > 0.005 && instantaneous < 30 {
                    rates[jobID] = rates[jobID].map { $0 * 0.68 + instantaneous * 0.32 } ?? instantaneous
                }
            }
        }
        if samples[jobID]?.current != current {
            samples[jobID] = (current, now)
        }
    }

    /// Restarts the clock without changing the rate (after a reconnect, the
    /// time spent offline is not processing time).
    mutating func restart(jobID: UUID, current: Int, at now: Date) {
        samples[jobID] = (current, now)
    }

    func remaining(jobID: UUID, current: Int, total: Int) -> TimeInterval? {
        guard total > current, let rate = rates[jobID], rate > 0.005 else { return nil }
        return Double(total - current) / rate
    }
}
