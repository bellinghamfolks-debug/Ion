import Combine
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

/// The natural-style screen's view of its task. The work itself is done by
/// ServerTaskCenter, which keeps the task on disk and in the Tasks tab and
/// follows it to the end whatever happens to the screen or to Basir.
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
    private var currentID: String?
    private var watching: AnyCancellable?

    var isBusy: Bool { if case .working = phase { return true } else { return false } }

    private init() {
        watching = ServerTaskCenter.shared.$tasks.sink { [weak self] tasks in
            Task { @MainActor in self?.reflect(tasks) }
        }
    }

    func start(_ body: RestyleRequestBody, configuration: ServerConfiguration, l10n: L10n) {
        guard configuration.isConfigured else {
            phase = .failed(DocumentAssistant.message(for: BasirError.notConfigured, l10n: l10n))
            return
        }
        guard let data = try? body.encoded() else { return }
        let id = RestyleRequestBody.requestKey(data)
        currentID = id
        ServerTaskCenter.shared.submit(kind: .restyle, id: id, notificationID: RestyleRequestBody.notificationID(data),
                                       title: Self.title(body.title, l10n: l10n), body: data,
                                       language: l10n.isArabic ? "ar" : "en", choice: "accurate",
                                       configuration: configuration, l10n: l10n)
        announce(l10n.t("بدأت المهمة، وتجدها في «المهام». يقرأ بصير النص كاملًا ثم يحرره، ويمكنك الانتقال إلى تطبيق آخر أو إغلاق بصير، وسيكملها حتى النهاية.",
                        "The task has started; you'll find it in Tasks. Basir reads the whole text, then edits it. You can switch apps or close Basir; it will be finished."))
    }

    func resumeIfNeeded(configuration: ServerConfiguration, l10n: L10n) {
        ServerTaskCenter.shared.resumeAll(configuration: configuration, l10n: l10n)
        if currentID == nil {
            currentID = ServerTaskCenter.shared.tasks.last { $0.kind == .restyle && $0.isActive }?.id
        }
        reflect(ServerTaskCenter.shared.tasks)
    }

    /// The screen shows this task (opened from the Tasks tab).
    func focus(_ id: String) {
        currentID = id
        reflect(ServerTaskCenter.shared.tasks)
    }

    func cancel(configuration: ServerConfiguration) {
        if let currentID { ServerTaskCenter.shared.cancel(currentID, configuration: configuration) }
        phase = .idle
    }

    func reset() {
        if case .working = phase { return }
        phase = .idle
    }

    private func reflect(_ tasks: [ServerTask]) {
        guard let currentID, let task = tasks.first(where: { $0.id == currentID }) else { return }
        let next: Phase
        switch task.state {
        case .sending, .working: next = .working(detail: task.detail, done: task.done, total: task.total)
        case .finished: next = .finished(task.id)
        case .failed: next = .failed(task.error.map { Self.message(for: BasirError.conversionFailed($0), l10n: nil) } ?? "")
        case .cancelled: next = .idle
        }
        if next != phase { phase = next }
    }

    /// Saves a finished text: the Word file in My Files, the JSON for reading and comparing.
    static func save(_ result: RestyleResult, word: Data?, id: String, title: String, l10n: L10n?) {
        var savedName: String?
        if let word, let folder = try? FileAccess.outputDirectory() {
            let base = FileAccess.sanitizeFilename(result.title.isEmpty ? title : result.title)
            let name = (base.isEmpty ? (l10n?.t("نص بصير", "Basir text") ?? "نص بصير") : base)
                + (l10n?.t(" - بأسلوب طبيعي", " - natural style") ?? " - بأسلوب طبيعي")
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
    }

    static func title(_ name: String, l10n: L10n) -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? l10n.t("أسلوب طبيعي", "Natural style") : l10n.t("أسلوب طبيعي: \(name)", "Natural style: \(name)")
    }

    static func stage(_ progress: SummaryJobProgress, percent: Int, l10n: L10n) -> String {
        ServerTaskCenter.shared.stage(kind: .restyle, done: progress.current, total: progress.total)
    }

    static func message(for error: Error, l10n: L10n?) -> String {
        let t = { (ar: String, en: String) in l10n?.t(ar, en) ?? ar }
        if let error = error as? BasirError, case .conversionFailed(let reason) = error, !reason.isEmpty {
            if reason.contains("busy") {
                return t("الخدمة مشغولة الآن. حاول بعد دقائق.", "The service is busy. Try again in a few minutes.")
            }
            if reason.contains("no text") {
                return t("لم يجد بصير نصًا في هذا الملف.", "Basir found no text in this file.")
            }
            if reason.contains("could not be opened") {
                return t("تعذّر فتح الملف. أرسل ملف Word أو ملفًا نصيًا.", "The file could not be opened. Send a Word or text file.")
            }
            if reason.contains("several attempts") {
                return t("تعذّر إكمال المهمة بعد عدة محاولات. أعد المحاولة من «المهام».",
                         "The task could not be completed after several attempts. Try again from Tasks.")
            }
            return reason
        }
        if let l10n { return DocumentAssistant.message(for: error, l10n: l10n) }
        return t("تعذّر إكمال المهمة.", "The task could not be completed.")
    }

    private func announce(_ text: String) {
        UIAccessibility.post(notification: .announcement, argument: text)
    }
}
