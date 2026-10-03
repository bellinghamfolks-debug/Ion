import Foundation
import UIKit

/// Connects the device's APNs token (and each Live Activity's push token) to
/// the server job, so the Basir server can report progress, completion, and
/// failure even while iOS has suspended the app.
@MainActor
final class PushRegistrar {
    static let shared = PushRegistrar()

    private struct ServerJob {
        let serverJobID: String
        let configuration: ServerConfiguration
        let language: String
    }

    private(set) var deviceToken: String?
    private var serverJobs: [UUID: ServerJob] = [:]
    private var liveActivityTokens: [UUID: String] = [:]
    /// Jobs whose progress the server now reports; local progress
    /// notifications are skipped for them so nothing is shown twice.
    private(set) var remoteProgressJobs: Set<UUID> = []

    private init() {}

    func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    func didReceiveDeviceToken(_ data: Data) {
        let token = Self.hex(data)
        guard token != deviceToken else { return }
        deviceToken = token
        DiagnosticLogger.recordGlobal("PUSH device token received environment=\(Self.apsEnvironment)")
        serverJobs.keys.forEach(send)
    }

    func didFailToRegister(_ error: Error) {
        DiagnosticLogger.recordGlobal("PUSH registration unavailable description=\(error.localizedDescription)")
    }

    func serverJobCreated(clientJobID: UUID, serverJobID: String, configuration: ServerConfiguration, language: String) {
        serverJobs[clientJobID] = ServerJob(serverJobID: serverJobID, configuration: configuration, language: language)
        send(clientJobID)
    }

    func liveActivityTokenChanged(clientJobID: UUID, token: Data) {
        liveActivityTokens[clientJobID] = Self.hex(token)
        send(clientJobID)
    }

    func jobFinished(_ clientJobID: UUID) {
        serverJobs.removeValue(forKey: clientJobID)
        liveActivityTokens.removeValue(forKey: clientJobID)
        remoteProgressJobs.remove(clientJobID)
    }

    private func send(_ clientJobID: UUID) {
        guard let job = serverJobs[clientJobID] else { return }
        let device = deviceToken
        let activity = liveActivityTokens[clientJobID]
        guard device != nil || activity != nil else { return }
        let body = ProxyClient.PushRegistrationBody(
            clientJobID: clientJobID.uuidString,
            deviceToken: device,
            liveActivityToken: activity,
            environment: Self.apsEnvironment,
            language: job.language
        )
        Task { [weak self] in
            do {
                let enabled = try await ProxyClient(configuration: job.configuration)
                    .registerPush(serverJobID: job.serverJobID, body: body)
                DiagnosticLogger.recordGlobal("PUSH registered serverJob=\(job.serverJobID) enabled=\(enabled) liveActivity=\(activity != nil)")
                if enabled, device != nil { self?.remoteProgressJobs.insert(clientJobID) }
            } catch {
                // Older servers or a disabled key: local notifications keep working.
                DiagnosticLogger.recordGlobal("PUSH register failed description=\(error.localizedDescription)")
            }
        }
    }

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    /// "sandbox" for development-signed builds, otherwise "production". The
    /// server also switches automatically if the guess is wrong.
    static let apsEnvironment: String = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .isoLatin1),
              let start = text.range(of: "<?xml"),
              let end = text.range(of: "</plist>"),
              let plistData = String(text[start.lowerBound..<end.upperBound]).data(using: .isoLatin1),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any],
              let environment = entitlements["aps-environment"] as? String else { return "production" }
        return environment == "development" ? "sandbox" : "production"
    }()
}
