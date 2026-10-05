import Foundation
import UIKit
import AudioToolbox
import UserNotifications

@MainActor
enum OperationFeedback {
    static func play(_ event: Event, theme: SoundTheme) {
        guard theme != .off else { return }
        switch theme {
        case .off:
            break
        case .gentle:
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(event == .failed ? .error : (event == .completed ? .success : .warning))
        case .clear:
            AudioServicesPlaySystemSound(event == .completed ? 1025 : (event == .failed ? 1073 : 1104))
        case .tactile:
            let generator = UIImpactFeedbackGenerator(style: event == .progress ? .light : .heavy)
            generator.impactOccurred()
        }
    }

    static func selectionChanged() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }

    static func warningImpact() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.warning)
    }

    static func requestNotificationPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    private static var progressBuckets: [UUID: Int] = [:]

    private static func progressIdentifier(_ jobID: UUID) -> String { "basir-progress-\(jobID.uuidString)" }

    /// One notification per task that keeps updating in place (same
    /// identifier). Every 10% it is refreshed silently in Notification Center;
    /// at 20, 50 and 80% it is shown as a banner. Each update replaces the
    /// previous one, so the list never fills with stale percentages.
    static func notifyProgress(title: String, body: String, jobID: UUID, percent: Int) {
        guard let decision = progressDecision(previousBucket: progressBuckets[jobID, default: 0],
                                              percent: percent) else { return }
        progressBuckets[jobID] = decision.bucket
        let showsBanner = decision.showsBanner
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.threadIdentifier = "basir-job-\(jobID.uuidString)"
        content.userInfo = ["job_id": jobID.uuidString]
        content.interruptionLevel = showsBanner ? .active : .passive
        content.relevanceScore = Double(decision.bucket) / 100
        let request = UNNotificationRequest(identifier: progressIdentifier(jobID), content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Pure decision used by notifyProgress: report each new 10% step, and show
    /// a banner whenever 20, 50 or 80% is reached or jumped over.
    nonisolated static func progressDecision(previousBucket: Int, percent: Int) -> (bucket: Int, showsBanner: Bool)? {
        guard percent > 0, percent < 100 else { return nil }
        let bucket = (percent / 10) * 10
        guard bucket > 0, previousBucket < bucket else { return nil }
        let showsBanner = [20, 50, 80].contains { $0 > previousBucket && $0 <= bucket }
        return (bucket, showsBanner)
    }

    /// Replaces the progress notification when iOS stops background
    /// monitoring, so the last thing the person sees is accurate.
    static func notifyBackgroundPause(title: String, body: String, jobID: UUID) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.threadIdentifier = "basir-job-\(jobID.uuidString)"
        content.userInfo = ["job_id": jobID.uuidString]
        content.interruptionLevel = .active
        let request = UNNotificationRequest(identifier: progressIdentifier(jobID), content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// The result is finished on the server but not yet on the iPhone. Uses
    /// the same identifier as the server's "ready" push and the final
    /// completion notice, so the three replace each other.
    static func notifyResultWaiting(title: String, body: String, jobID: UUID) {
        progressBuckets.removeValue(forKey: jobID)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [progressIdentifier(jobID)])
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.threadIdentifier = "basir-job-\(jobID.uuidString)"
        content.userInfo = ["job_id": jobID.uuidString]
        content.interruptionLevel = .active
        let request = UNNotificationRequest(identifier: "basir-\(jobID.uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    static func notifyCompletion(title: String, body: String, jobID: UUID) {
        progressBuckets.removeValue(forKey: jobID)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [progressIdentifier(jobID)])
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["job_id": jobID.uuidString]
        content.threadIdentifier = "basir-job-\(jobID.uuidString)"
        content.interruptionLevel = .active
        let request = UNNotificationRequest(identifier: "basir-\(jobID.uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    static func notifyFailure(title: String, body: String, jobID: UUID) {
        progressBuckets.removeValue(forKey: jobID)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [progressIdentifier(jobID)])
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["job_id": jobID.uuidString]
        content.threadIdentifier = "basir-job-\(jobID.uuidString)"
        content.interruptionLevel = .active
        let request = UNNotificationRequest(identifier: "basir-failed-\(jobID.uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    enum Event { case progress, paused, completed, failed }
}

