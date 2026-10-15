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
    /// go straight to the background path (the server agrees: 150,000).
    static let directLimit = 140_000

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
        announce(l10n.t("جارٍ إعداد الملخص. سأخبرك عند اكتماله.", "Preparing the summary. I will tell you when it is ready."))
        task = Task { [weak self] in
            await self?.work(body, home: home, configuration: configuration, l10n: l10n)
        }
    }

    private func work(_ body: SummaryRequestBody, home: SummaryHome, configuration: ServerConfiguration,
                      l10n: L10n) async {
        let background = UIApplication.shared.beginBackgroundTask(withName: "Basir summary")
        defer { UIApplication.shared.endBackgroundTask(background) }
        do {
            let data = try body.encoded()
            let client = ProxyClient(configuration: configuration)
            var result: DocumentSummary?
            if body.totalCharacters <= Self.directLimit {
                do {
                    result = try DocumentSummary.decode(try await client.summarize(body: data))
                } catch BasirError.invalidResponse(let reason) where reason == ProxyClient.summaryUseJob {
                    result = nil
                }
            }
            if result == nil {
                result = try await runJob(data: data, body: body, client: client, configuration: configuration,
                                          l10n: l10n)
            }
            guard let made = result, !Task.isCancelled else { return }
            Self.store(made, body: body, home: home)
            summary = made
            phase = .finished
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            announce(l10n.t("الملخص جاهز.", "The summary is ready."))
        } catch is CancellationError {
            phase = .idle
        } catch {
            let message = Self.message(for: error, l10n: l10n)
            phase = .failed(message)
            announce(message)
        }
    }

    private func runJob(data: Data, body: SummaryRequestBody, client: ProxyClient,
                        configuration: ServerConfiguration, l10n: L10n) async throws -> DocumentSummary {
        let requestKey = "summary-" + String(SummaryStore.fingerprint(String(decoding: data, as: UTF8.self)).prefix(48))
        let jobID: String
        if let pending = SummaryStore.pendingJob(for: requestKey) {
            jobID = pending
        } else {
            phase = .working(detail: l10n.t("جارٍ إرسال المستند", "Sending the document"), done: 0, total: 0)
            jobID = try await client.startSummaryJob(body: data, requestID: requestKey, title: body.title,
                                                     language: body.language, choice: body.choice)
            SummaryStore.setPendingJob(jobID, for: requestKey)
        }
        // The server tells the person when it is ready, even if iOS suspends Basir.
        PushRegistrar.shared.serverJobCreated(clientJobID: UUID(), serverJobID: jobID, configuration: configuration,
                                              language: l10n.isArabic ? "ar" : "en")
        var lastAnnounced = -1
        while true {
            try Task.checkCancellation()
            let progress = try await client.summaryJobProgress(jobID: jobID, requestID: requestKey)
            if progress.isFinished {
                let summary = try DocumentSummary.decode(try await client.jobSummary(jobID: jobID, requestID: requestKey))
                SummaryStore.setPendingJob(nil, for: requestKey)
                // The summary is now on the phone; the server copy goes, as the
                // privacy setting asks (on by default).
                let deleteCopy = UserDefaults.standard.object(forKey: "privacy_delete_server_copy") as? Bool ?? true
                if deleteCopy { try? await client.deleteServerTask(requestID: requestKey) }
                return summary
            }
            if progress.isFailed {
                SummaryStore.setPendingJob(nil, for: requestKey)
                throw BasirError.conversionFailed(progress.error ?? "")
            }
            let reading = progress.total > 1 && progress.current < progress.total - 1
            let detail = reading
                ? l10n.t("جارٍ قراءة المستند، الجزء \(progress.current) من \(progress.total - 1)",
                         "Reading the document, part \(progress.current) of \(progress.total - 1)")
                : l10n.t("جارٍ كتابة الملخص", "Writing the summary")
            phase = .working(detail: detail, done: progress.current, total: progress.total)
            let percent = progress.total > 0 ? progress.current * 100 / progress.total : 0
            if percent / 25 != lastAnnounced, progress.total > 2 {
                lastAnnounced = percent / 25
                announce(l10n.t("الملخص: \(percent) بالمئة", "Summary: \(percent) percent"))
            }
            try await Task.sleep(nanoseconds: 3_000_000_000)
        }
    }

    // MARK: Helpers

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
