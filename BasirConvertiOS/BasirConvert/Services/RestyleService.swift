import Foundation
import CryptoKit
import UIKit

/// What the app asks the server to bring back to a natural voice.
struct RestyleRequestBody: Encodable, Equatable {
    var title: String
    var language = "auto"
    var text = ""
    /// A Word or text file, base64; the server keeps its headings and paragraphs.
    var documentBase64 = ""
    var documentName = ""
    /// The author's own writing, from before any machine editing.
    var styleSample = ""
    /// "light" or "full".
    var strength = "full"
    var notes = ""

    enum CodingKeys: String, CodingKey {
        case title, language, text, strength, notes
        case documentBase64 = "document_base64"
        case documentName = "document_name"
        case styleSample = "style_sample"
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    /// The same request always has the same key, so the server picks its job back up.
    static func requestKey(_ data: Data) -> String {
        "restyle-" + SHA256.hash(data: data).prefix(24).map { String(format: "%02x", $0) }.joined()
    }

    /// The one notification about this request, in UUID form (as the server's push uses).
    static func notificationID(_ data: Data) -> String {
        let hex = Array(SHA256.hash(data: data).map { String(format: "%02X", $0) }.joined().prefix(32))
        let parts = [0..<8, 8..<12, 12..<16, 16..<20, 20..<32].map { String(hex[$0]) }
        return parts.joined(separator: "-")
    }
}

/// Results kept on the phone: the JSON (for reading and comparing) next to
/// the Word file saved in My Files.
enum RestyleStore {
    struct Entry: Codable, Equatable, Identifiable {
        var id: String
        var title: String
        var createdAt: Date
        var words: Int
        var wordFile: String?
    }

    private static let pendingKey = "restyle_pending_job"
    private static let indexName = "index.json"

    static var directory: URL? {
        guard let root = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                      appropriateFor: nil, create: true) else { return nil }
        let folder = root.appendingPathComponent("Restyled", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func entries() -> [Entry] {
        guard let url = directory?.appendingPathComponent(indexName), let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return ((try? decoder.decode([Entry].self, from: data)) ?? []).sorted { $0.createdAt > $1.createdAt }
    }

    static func save(_ result: RestyleResult, entry: Entry) {
        guard let folder = directory, let data = try? result.encoded() else { return }
        try? data.write(to: folder.appendingPathComponent("\(entry.id).json"), options: [.atomic, .completeFileProtectionUnlessOpen])
        var all = entries().filter { $0.id != entry.id }
        all.insert(entry, at: 0)
        write(all)
    }

    static func result(for id: String) -> RestyleResult? {
        guard let url = directory?.appendingPathComponent("\(id).json"), let data = try? Data(contentsOf: url) else { return nil }
        return try? RestyleResult.decode(data)
    }

    static func delete(_ entry: Entry) {
        if let url = directory?.appendingPathComponent("\(entry.id).json") { try? FileManager.default.removeItem(at: url) }
        write(entries().filter { $0.id != entry.id })
    }

    private static func write(_ entries: [Entry]) {
        guard let url = directory?.appendingPathComponent(indexName) else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(entries) { try? data.write(to: url, options: .atomic) }
    }

    // A job under way survives Basir being closed: its request is kept until it ends.
    struct Pending: Codable, Equatable {
        var requestKey: String
        var notificationID: String
        var title: String
        var jobID: String?
        var body: Data
    }

    static func pending() -> Pending? {
        UserDefaults.standard.data(forKey: pendingKey).flatMap { try? JSONDecoder().decode(Pending.self, from: $0) }
    }

    static func setPending(_ value: Pending?) {
        if let value, let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: pendingKey)
        } else {
            UserDefaults.standard.removeObject(forKey: pendingKey)
        }
    }
}

/// Runs one natural-style job for the life of the app: closing the screen
/// never stops it, and after a restart it is picked up again on the server.
@MainActor
final class RestyleRunner: ObservableObject {
    static let shared = RestyleRunner()

    enum Phase: Equatable {
        case idle
        case working(detail: String, done: Int, total: Int)
        case finished(String)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    private var task: Task<Void, Never>?

    var isBusy: Bool { if case .working = phase { return true } else { return false } }

    func start(_ body: RestyleRequestBody, configuration: ServerConfiguration, l10n: L10n) {
        guard configuration.isConfigured else {
            phase = .failed(DocumentAssistant.message(for: BasirError.notConfigured, l10n: l10n))
            return
        }
        guard let data = try? body.encoded() else { return }
        let pending = RestyleStore.Pending(requestKey: RestyleRequestBody.requestKey(data),
                                           notificationID: RestyleRequestBody.notificationID(data),
                                           title: body.title, jobID: nil, body: data)
        RestyleStore.setPending(pending)
        run(pending, configuration: configuration, l10n: l10n)
    }

    func resumeIfNeeded(configuration: ServerConfiguration, l10n: L10n) {
        guard task == nil, configuration.isConfigured, let pending = RestyleStore.pending() else { return }
        run(pending, configuration: configuration, l10n: l10n)
    }

    func cancel(configuration: ServerConfiguration) {
        task?.cancel()
        task = nil
        if let pending = RestyleStore.pending() {
            if pending.jobID != nil {
                Task { _ = try? await ProxyClient(configuration: configuration).cancelServerTask(requestID: pending.requestKey) }
            }
            JobWatcher.shared.stop(id: pending.notificationID)
            RestyleStore.setPending(nil)
        }
        phase = .idle
    }

    func reset() {
        if case .working = phase { return }
        phase = .idle
    }

    private func run(_ pending: RestyleStore.Pending, configuration: ServerConfiguration, l10n: L10n) {
        phase = .working(detail: l10n.t("جارٍ إرسال النص", "Sending the text"), done: 0, total: 0)
        task = Task { [weak self] in
            await self?.work(pending, configuration: configuration, l10n: l10n)
            self?.task = nil
        }
    }

    private func work(_ start: RestyleStore.Pending, configuration: ServerConfiguration, l10n: L10n) async {
        let background = UIApplication.shared.beginBackgroundTask(withName: "Basir style")
        defer { UIApplication.shared.endBackgroundTask(background) }
        var pending = start
        let title = Self.title(pending.title, l10n: l10n)
        do {
            let client = ProxyClient(configuration: configuration)
            if pending.jobID == nil {
                pending.jobID = try await client.startRestyleJob(body: pending.body, requestID: pending.requestKey,
                                                                 title: pending.title, language: l10n.isArabic ? "ar" : "en",
                                                                 choice: "accurate")
                RestyleStore.setPending(pending)
            }
            guard let jobID = pending.jobID else { throw BasirError.invalidResponse("") }
            JobWatcher.shared.watch(id: pending.notificationID, serverJobID: jobID, work: .restyle, title: title,
                                    arabic: l10n.isArabic)
            if let clientJobID = UUID(uuidString: pending.notificationID) {
                PushRegistrar.shared.serverJobCreated(clientJobID: clientJobID, serverJobID: jobID,
                                                      configuration: configuration, language: l10n.isArabic ? "ar" : "en")
            }
            announce(l10n.t("وصل النص. يقرؤه بصير كاملًا ثم يحرره. يمكنك الانتقال إلى تطبيق آخر، وسيصلك إشعار عند الانتهاء.",
                            "The text arrived. Basir reads all of it, then edits it. You can switch apps; you'll be notified when it's done."))
            var lastAnnounced = -1
            var misses = 0
            while true {
                try Task.checkCancellation()
                let progress: SummaryJobProgress
                do {
                    progress = try await client.summaryJobProgress(jobID: jobID, requestID: pending.requestKey)
                    misses = 0
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    misses += 1
                    if misses >= 60 { throw error }
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    continue
                }
                if progress.isFinished { break }
                if progress.isFailed { throw BasirError.conversionFailed(progress.error ?? "") }
                let percent = progress.total > 0 ? progress.current * 100 / progress.total : 0
                phase = .working(detail: Self.stage(progress, percent: percent, l10n: l10n),
                                 done: progress.current, total: progress.total)
                if percent / 25 != lastAnnounced, progress.total > 2 {
                    lastAnnounced = percent / 25
                    announce(l10n.t("تحرير الأسلوب: \(percent) بالمئة", "Style editing: \(percent) percent"))
                }
                try await Task.sleep(nanoseconds: 4_000_000_000)
            }
            let result = try RestyleResult.decode(try await client.jobSummary(jobID: jobID, requestID: pending.requestKey))
            let word = try? await client.jobResult(jobID: jobID, requestID: pending.requestKey)
            let id = pending.requestKey
            var savedName: String?
            if let word, let folder = try? FileAccess.outputDirectory() {
                let base = FileAccess.sanitizeFilename(result.title.isEmpty ? pending.title : result.title)
                let name = (base.isEmpty ? l10n.t("نص بصير", "Basir text") : base) + l10n.t(" - بأسلوب طبيعي", " - natural style")
                var target = folder.appendingPathComponent(name + ".docx")
                var counter = 2
                while FileManager.default.fileExists(atPath: target.path) {
                    target = folder.appendingPathComponent("\(name) \(counter).docx")
                    counter += 1
                }
                if (try? word.write(to: target, options: [.atomic, .completeFileProtectionUnlessOpen])) != nil {
                    savedName = target.lastPathComponent
                }
            }
            RestyleStore.save(result, entry: RestyleStore.Entry(id: id, title: result.title.isEmpty ? title : result.title,
                                                                createdAt: Date(), words: result.report.before.words,
                                                                wordFile: savedName))
            RestyleStore.setPending(nil)
            // The text is now on the phone; the server copy goes, as the privacy setting asks (on by default).
            let deleteCopy = UserDefaults.standard.object(forKey: "privacy_delete_server_copy") as? Bool ?? true
            if deleteCopy { try? await client.deleteServerTask(requestID: pending.requestKey) }
            JobWatcher.shared.stop(id: pending.notificationID)
            phase = .finished(id)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            announce(l10n.t("النص بأسلوب طبيعي جاهز.", "The text in a natural voice is ready."))
            if UIApplication.shared.applicationState != .active {
                JobNotifier.show(JobNotifier.finished(task: .restyle, title: title, partial: result.isPartial,
                                                      arabic: l10n.isArabic), id: pending.notificationID)
            } else {
                JobNotifier.remove(pending.notificationID)
            }
        } catch is CancellationError {
            if case .working = phase { phase = .idle }
        } catch {
            let message = Self.message(for: error, l10n: l10n)
            if case BasirError.conversionFailed = error { RestyleStore.setPending(nil) }
            phase = .failed(message)
            announce(message)
            JobWatcher.shared.stop(id: pending.notificationID)
            if UIApplication.shared.applicationState != .active {
                JobNotifier.show(JobNotifier.failed(title: title, reason: message, arabic: l10n.isArabic),
                                 id: pending.notificationID)
            }
        }
    }

    /// Reading the whole text, then drafting every part, then the second editor's review.
    static func stage(_ progress: SummaryJobProgress, percent: Int, l10n: L10n) -> String {
        let parts = max(1, (progress.total - 1) / 2)
        if progress.current <= 0 || progress.total <= 1 {
            return l10n.t("يقرأ بصير النص كاملًا", "Basir is reading the whole text")
        }
        if progress.current <= parts {
            return l10n.t("التحرير: \(percent)٪ (يكتب المسودة)", "Editing: \(percent)% (drafting)")
        }
        return l10n.t("التحرير: \(percent)٪ (يراجع المسودة على الأصل)", "Editing: \(percent)% (reviewing against the original)")
    }

    static func title(_ name: String, l10n: L10n) -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? l10n.t("أسلوب طبيعي", "Natural style") : l10n.t("أسلوب طبيعي: \(name)", "Natural style: \(name)")
    }

    static func message(for error: Error, l10n: L10n) -> String {
        if let error = error as? BasirError, case .conversionFailed(let reason) = error, !reason.isEmpty {
            if reason.contains("busy") {
                return l10n.t("الخدمة مشغولة الآن. حاول بعد دقائق.", "The service is busy. Try again in a few minutes.")
            }
            if reason.contains("no text") {
                return l10n.t("لم يجد بصير نصًا في هذا الملف.", "Basir found no text in this file.")
            }
            if reason.contains("could not be opened") {
                return l10n.t("تعذّر فتح الملف. أرسل ملف Word أو ملفًا نصيًا.", "The file could not be opened. Send a Word or text file.")
            }
        }
        return DocumentAssistant.message(for: error, l10n: l10n)
    }

    private func announce(_ text: String) {
        UIAccessibility.post(notification: .announcement, argument: text)
    }
}
