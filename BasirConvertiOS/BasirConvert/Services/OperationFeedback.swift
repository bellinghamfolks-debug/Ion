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

    static func notifyProgress(title: String, body: String, jobID: UUID, current: Int, total: Int) {
        guard total > 1, current > 0, current < total else { return }
        let percentage = Int((Double(current) / Double(total) * 100).rounded(.down))
        let bucket = percentage >= 75 ? 75 : (percentage >= 50 ? 50 : (percentage >= 25 ? 25 : 0))
        guard bucket > 0, progressBuckets[jobID, default: 0] < bucket else { return }
        progressBuckets[jobID] = bucket
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.userInfo = ["job_id": jobID.uuidString]
        let request = UNNotificationRequest(identifier: "basir-progress-\(jobID.uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    static func notifyCompletion(title: String, body: String, jobID: UUID) {
        progressBuckets.removeValue(forKey: jobID)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["basir-progress-\(jobID.uuidString)"])
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["job_id": jobID.uuidString]
        let request = UNNotificationRequest(identifier: "basir-\(jobID.uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    static func notifyFailure(title: String, body: String, jobID: UUID) {
        progressBuckets.removeValue(forKey: jobID)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["basir-progress-\(jobID.uuidString)"])
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["job_id": jobID.uuidString]
        let request = UNNotificationRequest(identifier: "basir-failed-\(jobID.uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    enum Event { case progress, paused, completed, failed }
}

