import Foundation
import CryptoKit
import UIKit

/// Summaries kept on the phone (ت15): next to their Word file in My Files
/// (renamed and deleted with it), or by the text's fingerprint for documents
/// that are not in My Files (instant read, several files, shared files).
/// Opening a summary again is instant and works offline.
enum SummaryStore {
    private struct Saved: Codable {
        var variants: [String: Data] = [:]
        var latest: String = ""
    }

    static let directoryName = "Summaries"
    private static let pendingKey = "summary_pending_jobs"

    static func conversionVariant(language: String) -> String { "\(language)|auto|plain" }

    static func url(forOutput output: URL) -> URL {
        output.deletingPathExtension().appendingPathExtension("summary.json")
    }

    static func url(forKey key: String) -> URL? {
        guard let root = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                      appropriateFor: nil, create: true) else { return nil }
        let directory = root.appendingPathComponent(directoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("\(key).json")
    }

    static func fingerprint(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Read and write

    static func save(_ summary: DocumentSummary, variant: String, forOutput output: URL) {
        save(summary, variant: variant, at: url(forOutput: output))
    }

    static func save(_ summary: DocumentSummary, variant: String, key: String) {
        guard let target = url(forKey: key) else { return }
        save(summary, variant: variant, at: target)
    }

    static func load(variant: String, forOutput output: URL) -> DocumentSummary? {
        load(variant: variant, at: url(forOutput: output))
    }

    static func load(variant: String, key: String) -> DocumentSummary? {
        url(forKey: key).flatMap { load(variant: variant, at: $0) }
    }

    /// The most recent summary of a file in My Files, whatever its options.
    static func latest(forOutput output: URL) -> DocumentSummary? {
        guard let saved = read(url(forOutput: output)) else { return nil }
        return saved.variants[saved.latest].flatMap { try? DocumentSummary.decode($0) }
    }

    static func hasSummary(forOutput output: URL) -> Bool {
        FileManager.default.fileExists(atPath: url(forOutput: output).path)
    }

    private static func save(_ summary: DocumentSummary, variant: String, at target: URL) {
        guard let data = try? summary.encoded() else { return }
        var saved = read(target) ?? Saved()
        saved.variants[variant] = data
        saved.latest = variant
        guard let encoded = try? JSONEncoder().encode(saved) else { return }
        try? encoded.write(to: target, options: [.atomic, .completeFileProtectionUnlessOpen])
    }

    private static func load(variant: String, at target: URL) -> DocumentSummary? {
        read(target)?.variants[variant].flatMap { try? DocumentSummary.decode($0) }
    }

    private static func read(_ target: URL) -> Saved? {
        guard let data = try? Data(contentsOf: target) else { return nil }
        return try? JSONDecoder().decode(Saved.self, from: data)
    }

    // MARK: Background jobs in progress (ت4)

    static func pendingJob(for requestKey: String) -> String? {
        (UserDefaults.standard.dictionary(forKey: pendingKey) as? [String: String])?[requestKey]
    }

    static func setPendingJob(_ jobID: String?, for requestKey: String) {
        var jobs = (UserDefaults.standard.dictionary(forKey: pendingKey) as? [String: String]) ?? [:]
        jobs[requestKey] = jobID
        UserDefaults.standard.set(jobs, forKey: pendingKey)
    }
}

/// Where a summary is kept once made.
enum SummaryHome: Equatable, Sendable {
    case output(URL)
    case key(String)

    var id: String {
        switch self {
        case .output(let url): return "output:" + url.standardizedFileURL.path
        case .key(let key): return "key:" + key
        }
    }
}

/// Keeps each document's summary work alive for the life of the app, so
/// closing the summary screen never stops it: opening the screen again shows
/// the progress, or the finished summary.
@MainActor
final class SummaryCenter {
    static let shared = SummaryCenter()
    private var runners: [String: SummaryRunner] = [:]

    func runner(for home: SummaryHome) -> SummaryRunner {
        if let existing = runners[home.id] { return existing }
        let runner = SummaryRunner()
        runners[home.id] = runner
        return runner
    }
}

/// Makes one summary: at once for ordinary documents, as a background job
/// for long ones (a book, several long files), with progress the screen and
/// VoiceOver can follow. A job survives the app being closed: asking again
/// picks the same job back up on the server.
@MainActor
final class SummaryRunner: ObservableObject {
    enum Phase: Equatable {
        case idle
        case working(detail: String, done: Int, total: Int)
        case finished
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var summary: DocumentSummary?
    private var task: Task<Void, Never>?

    /// Documents up to this size are summarized in one request; longer ones
    /// go straight to the server job, which survives Basir being closed.
    static let directLimit = 60_000

    func showSaved(_ summary: DocumentSummary) {
        self.summary = summary
        phase = .finished
    }

    func cancel() {
        task?.cancel()
        task = nil
        if case .working = phase { phase = .idle }
    }

    func run(_ body: SummaryRequestBody, home: SummaryHome, configuration: ServerConfiguration, l10n: L10n) {
        cancel()
        if let saved = Self.saved(body, home: home) {
            showSaved(saved)
            return
        }
        guard configuration.isConfigured else {
            phase = .failed(DocumentAssistant.message(for: BasirError.notConfigured, l10n: l10n))
            return
        }
        phase = .working(detail: l10n.t("جارٍ إعداد الملخص", "Preparing the summary"), done: 0, total: 0)
        announce(l10n.t("جارٍ إعداد الملخص.", "Preparing the summary."))
        task = Task { [weak self] in
            await self?.work(body, home: home, configuration: configuration, l10n: l10n)
        }
    }

    private func work(_ body: SummaryRequestBody, home: SummaryHome, configuration: ServerConfiguration,
                      l10n: L10n) async {
        do {
            let data = try body.encoded()
            let client = ProxyClient(configuration: configuration)
            var result: DocumentSummary?
            // A job already running for this request (Basir was closed while it
            // worked) is picked up again instead of starting over.
            let resuming = SummaryStore.pendingJob(for: Self.requestKey(data)) != nil
                || ServerTaskCenter.shared.task(Self.requestKey(data))?.isActive == true
            if body.totalCharacters <= Self.directLimit, !resuming {
                do {
                    result = try DocumentSummary.decode(try await withBackgroundTime("Basir summary") {
                        try await client.summarize(body: data)
                    })
                } catch is CancellationError {
                    throw CancellationError()
                } catch BasirError.authenticationFailed {
                    throw BasirError.authenticationFailed
                } catch BasirError.notConfigured {
                    throw BasirError.notConfigured
                } catch {
                    // Too long, cut off when Basir went to the background, or a
                    // passing failure: the server job finishes it either way.
                    if Task.isCancelled { throw CancellationError() }
                    result = nil
                }
            }
            if result == nil {
                result = try await runJob(data: data, body: body, client: client, configuration: configuration,
                                          l10n: l10n, home: home)
            }
            guard let made = result, !Task.isCancelled else { return }
            Self.store(made, body: body, home: home)
            summary = made
            phase = .finished
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            announce(l10n.t("الملخص جاهز.", "The summary is ready."))
            // A long summary's notification is the task center's; a short one has none.
        } catch is CancellationError {
            phase = .idle
        } catch {
            let message = Self.message(for: error, l10n: l10n)
            phase = .failed(message)
            announce(message)
            // A long summary that failed stays in Tasks, where it can be tried again.
        }
    }

    /// A long summary runs as a server task kept by ServerTaskCenter: in the
    /// Tasks tab, on disk, and followed to the end even if this screen closes
    /// or iOS closes Basir; the summary is then saved where this screen finds it.
    private func runJob(data: Data, body: SummaryRequestBody, client: ProxyClient,
                        configuration: ServerConfiguration, l10n: L10n, home: SummaryHome) async throws -> DocumentSummary {
        let requestKey = Self.requestKey(data)
        let homeKey: String
        switch home {
        case .output(let url): homeKey = "output:" + url.lastPathComponent
        case .key(let key): homeKey = "key:" + key
        }
        let center = ServerTaskCenter.shared
        if center.task(requestKey)?.isActive != true {
            center.submit(kind: .summary, id: requestKey, notificationID: Self.notificationID(data),
                          title: Self.title(body, l10n: l10n), body: data, language: body.language, choice: body.choice,
                          summaryHome: homeKey, summaryVariant: body.variantKey,
                          jobID: SummaryStore.pendingJob(for: requestKey), configuration: configuration, l10n: l10n)
        }
        let result = try await center.outcome(of: requestKey) { task in
            self.phase = .working(detail: task.detail.isEmpty ? l10n.t("جارٍ إعداد الملخص", "Preparing the summary") : task.detail,
                                  done: task.done, total: task.total)
        }
        return try DocumentSummary.decode(result)
    }

    // MARK: Helpers

    /// The same request always gets the same key, so the server resumes its job.
    static func requestKey(_ data: Data) -> String {
        "summary-" + String(SummaryStore.fingerprint(String(decoding: data, as: UTF8.self)).prefix(48))
    }

    /// A stable task identifier in UUID form for this request: the one
    /// notification about it, here and in the server's push, uses it.
    static func notificationID(_ data: Data) -> String {
        let hex = Array(SummaryStore.fingerprint(String(decoding: data, as: UTF8.self)).prefix(32).uppercased())
        guard hex.count == 32 else { return requestKey(data) }
        let parts = [0..<8, 8..<12, 12..<16, 16..<20, 20..<32].map { String(hex[$0]) }
        return parts.joined(separator: "-")
    }

    static func title(_ body: SummaryRequestBody, l10n: L10n) -> String {
        let name = body.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? l10n.t("ملخص بصير", "Basir summary") : l10n.t("ملخص: \(name)", "Summary: \(name)")
    }

    static func saved(_ body: SummaryRequestBody, home: SummaryHome) -> DocumentSummary? {
        switch home {
        case .output(let url): return SummaryStore.load(variant: body.variantKey, forOutput: url)
        case .key(let key): return SummaryStore.load(variant: body.variantKey, key: key)
        }
    }

    static func store(_ summary: DocumentSummary, body: SummaryRequestBody, home: SummaryHome) {
        switch home {
        case .output(let url): SummaryStore.save(summary, variant: body.variantKey, forOutput: url)
        case .key(let key): SummaryStore.save(summary, variant: body.variantKey, key: key)
        }
    }

    static func message(for error: Error, l10n: L10n) -> String {
        if let error = error as? BasirError, case .conversionFailed(let reason) = error, !reason.isEmpty,
           !reason.hasPrefix("Server HTTP") {
            if reason.contains("busy") {
                return l10n.t("الخدمة مشغولة الآن. حاول إعداد الملخص بعد دقائق.", "The service is busy. Try the summary again in a few minutes.")
            }
            if reason.contains("no text") || reason.contains("No content") {
                return l10n.t("لم يجد بصير نصًا يمكن تلخيصه في هذا المستند.", "Basir found no text to summarize in this document.")
            }
        }
        return DocumentAssistant.message(for: error, l10n: l10n)
    }

    private func announce(_ text: String) {
        UIAccessibility.post(notification: .announcement, argument: text)
    }
}
