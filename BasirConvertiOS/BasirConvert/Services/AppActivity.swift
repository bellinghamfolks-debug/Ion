import Foundation
import Darwin

/// Fixed operational identifiers only. No document text, titles or credentials.
enum AppActivity {
    static let enabledKey = "basir_collection_enabled"
    static let metadataKey = "basir_collection_metadata_only"
    private static let queueKey = "basir_activity_queue_v1"
    private static let lock = NSLock()
    private static var flushing = false
    static var enabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
    static var metadataOnly: Bool { UserDefaults.standard.object(forKey: metadataKey) as? Bool ?? false }

    static func headers() -> [String: String] {
        let defaults = UserDefaults.standard
        lock.lock()
        let installation = defaults.string(forKey: "basir_installation_id") ?? UUID().uuidString
        defaults.set(installation, forKey: "basir_installation_id")
        lock.unlock()
        var info = utsname()
        uname(&info)
        let model = withUnsafeBytes(of: &info.machine) { bytes in
            String(cString: bytes.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return ["X-Basir-Collection": enabled ? "on" : "off", "X-Basir-Content": metadataOnly ? "exclude" : "include",
                "X-Basir-Installation": installation, "X-Basir-Device-Model": model,
                "X-Basir-OS-Version": "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
                "X-Basir-App-Build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"]
    }

    static func record(screen: String, action: String) {
        guard enabled else { return }
        let safe = { (value: String) in String(value.filter { $0.isASCII && ($0.isLetter || $0.isNumber || "_.-".contains($0)) }.prefix(80)) }
        let event = ["event_id": UUID().uuidString, "screen": safe(screen), "action": safe(action),
                     "occurred_at": ISO8601DateFormatter().string(from: Date())]
        lock.lock(); defer { lock.unlock() }
        var events = UserDefaults.standard.array(forKey: queueKey) as? [[String: String]] ?? []
        events.append(event)
        if events.count > 1000 { events.removeFirst(events.count - 1000) }
        UserDefaults.standard.set(events, forKey: queueKey)
    }

    static func discardPending() {
        lock.lock(); defer { lock.unlock() }
        UserDefaults.standard.removeObject(forKey: queueKey)
    }

    @MainActor
    static func flush(configuration: ServerConfiguration) async {
        guard enabled, configuration.isConfigured else { return }
        let events = takeBatch()
        guard !events.isEmpty else { return }
        var accepted = 0
        defer { finishBatch(events: events, accepted: accepted) }
        do { accepted = try await ProxyClient(configuration: configuration).sendActivity(events) }
        catch { /* Keep for retry after connectivity returns. */ }
    }

    private static func takeBatch() -> [[String: String]] {
        lock.lock(); defer { lock.unlock() }
        guard !flushing else { return [] }
        let events = Array((UserDefaults.standard.array(forKey: queueKey) as? [[String: String]] ?? []).prefix(50))
        if !events.isEmpty { flushing = true }
        return events
    }

    private static func finishBatch(events batch: [[String: String]], accepted: Int) {
        lock.lock(); defer { lock.unlock() }
        let acknowledged = Set(batch.prefix(max(0, min(accepted, batch.count))).compactMap { $0["event_id"] })
        var events = UserDefaults.standard.array(forKey: queueKey) as? [[String: String]] ?? []
        events.removeAll { acknowledged.contains($0["event_id"] ?? "") }
        UserDefaults.standard.set(events, forKey: queueKey)
        flushing = false
    }
}
