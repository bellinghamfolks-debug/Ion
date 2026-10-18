import AVFoundation
import CryptoKit
import Foundation
import UIKit

/// A video to describe: one from the album (already copied into Basir) or a
/// YouTube link.
enum VideoInput: Equatable, Sendable {
    case file(URL, title: String)
    case youtube(String)

    var title: String {
        switch self {
        case .file(_, let title): return title
        case .youtube: return ""
        }
    }
}

/// Makes an album video small enough to send quickly: the description needs
/// to see scenes and read on-screen text, not every pixel. An hour becomes
/// about 200–300 MB instead of several gigabytes.
enum VideoCompressor {
    static let maximumSeconds = 3600
    /// Lengths are rounded and credits run long: a minute and a half over is accepted.
    static let toleranceSeconds = 90
    static let maximumBytes: Int64 = 390 * 1024 * 1024

    enum Failure: Error, Equatable {
        case tooLong(seconds: Int)
        case unreadable
        case tooLarge
    }

    static func duration(of url: URL) async -> Int? {
        let asset = AVURLAsset(url: url)
        guard let time = try? await asset.load(.duration), time.isNumeric else { return nil }
        let seconds = CMTimeGetSeconds(time)
        return seconds.isFinite && seconds > 0 ? Int(seconds.rounded(.up)) : nil
    }

    static func isAllowed(seconds: Int) -> Bool { seconds <= maximumSeconds + toleranceSeconds }

    /// The video re-encoded small, in a temporary file, with its length.
    static func prepare(_ source: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> (URL, Int) {
        guard let seconds = await duration(of: source) else { throw Failure.unreadable }
        guard isAllowed(seconds: seconds) else { throw Failure.tooLong(seconds: seconds) }
        let asset = AVURLAsset(url: source)
        // Smaller for long videos, so an hour stays well under the server's limit.
        let presets = seconds > 1200 ? [AVAssetExportPreset640x480, AVAssetExportPresetLowQuality]
                                     : [AVAssetExportPreset960x540, AVAssetExportPreset640x480, AVAssetExportPresetLowQuality]
        for preset in presets {
            try Task.checkCancellation()
            guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { continue }
            let output = FileManager.default.temporaryDirectory
                .appendingPathComponent("basir-video-\(UUID().uuidString).mp4")
            session.outputURL = output
            session.outputFileType = .mp4
            session.shouldOptimizeForNetworkUse = true
            let ticker = Task {
                while !Task.isCancelled {
                    progress(Double(session.progress))
                    try? await Task.sleep(nanoseconds: 300_000_000)
                }
            }
            await session.export()
            ticker.cancel()
            if session.status == .completed,
               let size = (try? FileManager.default.attributesOfItem(atPath: output.path)[.size] as? NSNumber)?.int64Value {
                if size <= maximumBytes {
                    progress(1)
                    return (output, seconds)
                }
                try? FileManager.default.removeItem(at: output)
            } else {
                try? FileManager.default.removeItem(at: output)
                if Task.isCancelled { throw CancellationError() }
            }
        }
        throw Failure.tooLarge
    }
}

/// Descriptions kept on the phone, newest first. Opening one again is
/// instant and works offline; questions still go to the server.
enum VideoLibrary {
    struct Entry: Codable, Equatable, Identifiable, Sendable {
        var id: String
        var title: String
        var youtubeURL: String?
        var serverJobID: String?
        var createdAt: Date
        var durationSeconds: Int
        /// The small copy of an album video, kept for "Watch with description".
        var hasLocalVideo: Bool? = nil
    }

    private static let indexName = "index.json"

    static var folder: URL? { directory }

    private static var directory: URL? {
        guard let root = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                      appropriateFor: nil, create: true) else { return nil }
        let folder = root.appendingPathComponent("Videos", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func entries() -> [Entry] {
        guard let url = directory?.appendingPathComponent(indexName), let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return ((try? decoder.decode([Entry].self, from: data)) ?? []).sorted { $0.createdAt > $1.createdAt }
    }

    /// Where the small copy of an album video is kept.
    static func mediaURL(for id: String) -> URL? {
        directory?.appendingPathComponent("\(id).mp4")
    }

    static func description(for id: String) -> VideoDescription? {
        guard let url = directory?.appendingPathComponent("\(id).json"), let data = try? Data(contentsOf: url) else { return nil }
        return try? VideoDescription.decode(data)
    }

    static func save(_ description: VideoDescription, entry: Entry) {
        guard let folder = directory, let data = try? description.encoded() else { return }
        try? data.write(to: folder.appendingPathComponent("\(entry.id).json"), options: [.atomic, .completeFileProtectionUnlessOpen])
        var all = entries().filter { $0.id != entry.id }
        all.insert(entry, at: 0)
        write(all)
    }

    static func remove(_ id: String) {
        guard let folder = directory else { return }
        try? FileManager.default.removeItem(at: folder.appendingPathComponent("\(id).json"))
        try? FileManager.default.removeItem(at: folder.appendingPathComponent("\(id).mp4"))
        write(entries().filter { $0.id != id })
    }

    private static func write(_ entries: [Entry]) {
        guard let url = directory?.appendingPathComponent(indexName) else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(entries) { try? data.write(to: url, options: .atomic) }
    }
}

/// The video being described, kept on the phone so the work survives Basir
/// being closed or restarted by iOS: when Basir comes back it picks up where
/// it stopped (preparing, sending, or following the server's job).
struct VideoPending: Codable, Equatable {
    var key: String
    var title: String
    var youtubeURL: String?
    /// The chosen album video, copied into Basir, until it is made small.
    var originalName: String?
    var seconds: Int?
    /// The small copy is ready at `VideoLibrary.mediaURL(for: key)`.
    var compressed = false
    var jobID: String?
    var startedAt = Date()
    /// The person also asked for the dialogue in other languages to be
    /// translated (optional: missing in videos started before it existed).
    var translate: Bool? = nil

    private static let storageKey = "video_pending_v1"

    static func load() -> VideoPending? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(VideoPending.self, from: data)
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.storageKey) }
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: storageKey) }
}

/// Keeps video work alive while the screen is closed: opening the tool again
/// shows the progress, or the finished description.
@MainActor
final class VideoCenter {
    static let shared = VideoCenter()
    let runner = VideoRunner()
    /// Whether the video screen is showing, so Basir does not open it twice.
    var screenVisible = false
    private static let unseenKey = "video_unseen_result"

    /// A description finished while the person was away.
    var hasUnseenResult: Bool {
        get { UserDefaults.standard.bool(forKey: Self.unseenKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.unseenKey) }
    }

    /// Whether to open the video screen when Basir comes back.
    var shouldShowOnReturn: Bool { !screenVisible && (VideoPending.load() != nil || hasUnseenResult) }
}

/// Describes one video: prepares it on the phone, sends it, follows the
/// server job (also while Basir is in the background) and keeps the result.
@MainActor
final class VideoRunner: ObservableObject {
    enum Phase: Equatable {
        case idle
        case preparing(Double)
        case uploading(Double)
        case working(detail: String, done: Int, total: Int)
        case finished(String)            // library entry id
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var title = ""
    private var task: Task<Void, Never>?
    private var configuration: ServerConfiguration?

    /// Stopped because Basir left the foreground; resumed when it comes back.
    private struct Interrupted: Error {}

    var isBusy: Bool {
        switch phase {
        case .preparing, .uploading, .working: return true
        default: return false
        }
    }

    func reset() {
        if !isBusy { phase = .idle }
    }

    /// Stops the work here and on the server, and forgets it.
    func cancel() {
        task?.cancel()
        task = nil
        if let pending = VideoPending.load() {
            if let configuration, pending.jobID != nil {
                Task { _ = try? await ProxyClient(configuration: configuration).cancelServerTask(requestID: pending.key) }
            }
            Self.discardFiles(of: pending)
            VideoPending.clear()
        }
        phase = .idle
    }

    func start(_ input: VideoInput, translate: Bool = false, configuration: ServerConfiguration, l10n: L10n) {
        cancel()
        guard configuration.isConfigured else {
            phase = .failed(DocumentAssistant.message(for: BasirError.notConfigured, l10n: l10n))
            return
        }
        do {
            var pending: VideoPending
            // Asked with translation, the same video is a different description.
            let suffix = translate ? "-dialogue" : ""
            switch input {
            case .file(let url, let name):
                // Kept in Basir's own storage (not the temporary folder iOS may empty).
                guard let folder = VideoLibrary.folder else { throw VideoCompressor.Failure.unreadable }
                let original = "original-\(UUID().uuidString).\(url.pathExtension.isEmpty ? "mov" : url.pathExtension)"
                try FileManager.default.moveItem(at: url, to: folder.appendingPathComponent(original))
                let key = "video-" + String(try Self.fingerprint(file: folder.appendingPathComponent(original)).prefix(48)) + suffix
                pending = VideoPending(key: key, title: name, originalName: original)
            case .youtube(let link):
                pending = VideoPending(key: "video-" + String(Self.fingerprint(text: link).prefix(48)) + suffix, title: "",
                                       youtubeURL: link)
            }
            pending.translate = translate
            pending.save()
            run(pending, configuration: configuration, l10n: l10n)
        } catch {
            phase = .failed(Self.message(for: error, l10n: l10n))
        }
    }

    /// Picks up a description that was under way when Basir stopped.
    func resumeIfNeeded(configuration: ServerConfiguration, l10n: L10n) {
        guard task == nil, configuration.isConfigured, let pending = VideoPending.load() else { return }
        run(pending, configuration: configuration, l10n: l10n)
    }

    private func run(_ pending: VideoPending, configuration: ServerConfiguration, l10n: L10n) {
        self.configuration = configuration
        title = pending.title
        task = Task { [weak self] in
            await self?.work(pending, configuration: configuration, l10n: l10n)
            self?.task = nil
        }
    }

    private func work(_ start: VideoPending, configuration: ServerConfiguration, l10n: L10n) async {
        let background = UIApplication.shared.beginBackgroundTask(withName: "Basir video")
        defer { UIApplication.shared.endBackgroundTask(background) }
        var pending = start
        var request: URL?
        defer { if let request { try? FileManager.default.removeItem(at: request) } }
        do {
            let client = ProxyClient(configuration: configuration)
            // 1. Make the album video small, straight into Basir's storage.
            if pending.youtubeURL == nil, !pending.compressed {
                guard let name = pending.originalName, let folder = VideoLibrary.folder,
                      let keep = VideoLibrary.mediaURL(for: pending.key) else { throw VideoCompressor.Failure.unreadable }
                let original = folder.appendingPathComponent(name)
                guard FileManager.default.fileExists(atPath: original.path) else { throw VideoCompressor.Failure.unreadable }
                phase = .preparing(0)
                announce(l10n.t("جارٍ تجهيز الفيديو.", "Preparing the video."))
                let made: (URL, Int)
                do {
                    made = try await VideoCompressor.prepare(original) { value in
                        Task { @MainActor [weak self] in
                            if case .preparing = self?.phase { self?.phase = .preparing(value) }
                        }
                    }
                } catch let failure as VideoCompressor.Failure where failure == .tooLarge && !Self.isActive {
                    // iOS stops making videos small while Basir is in the background.
                    throw Interrupted()
                }
                try? FileManager.default.removeItem(at: keep)
                try FileManager.default.moveItem(at: made.0, to: keep)
                try? FileManager.default.removeItem(at: original)
                pending.compressed = true
                pending.seconds = made.1
                pending.originalName = nil
                pending.save()
            }
            try Task.checkCancellation()
            // 2. Send it (the server recognises the same request and resumes its job).
            let shownTitle = pending.title.isEmpty ? l10n.t("فيديو", "Video") : pending.title
            if pending.jobID == nil {
                let source: URL, contentType: String
                if let link = pending.youtubeURL {
                    let file = FileManager.default.temporaryDirectory.appendingPathComponent("basir-video-\(UUID().uuidString).json")
                    try JSONSerialization.data(withJSONObject: ["youtube_url": link]).write(to: file, options: .atomic)
                    request = file
                    source = file
                    contentType = "application/json"
                } else {
                    guard let keep = VideoLibrary.mediaURL(for: pending.key) else { throw VideoCompressor.Failure.unreadable }
                    source = keep
                    contentType = "video/mp4"
                    announce(l10n.t("جارٍ إرسال الفيديو.", "Sending the video."))
                }
                phase = .uploading(0)
                do {
                    pending.jobID = try await client.startVideoJob(
                        source: source, contentType: contentType, seconds: pending.seconds, requestID: pending.key,
                        title: pending.title, language: l10n.isArabic ? "ar" : "en",
                        translateDialogue: pending.translate ?? false) { value in
                        Task { @MainActor [weak self] in
                            if case .uploading = self?.phase { self?.phase = .uploading(value) }
                        }
                    }
                } catch where !(error is CancellationError) && !Self.isActive {
                    throw Interrupted()
                }
                pending.save()
                let notificationID = Self.notificationID(pending.key)
                if let jobID = pending.jobID {
                    JobWatcher.shared.watch(id: notificationID, serverJobID: jobID, work: .video,
                                            title: l10n.t("وصف: \(shownTitle)", "Description: \(shownTitle)"), arabic: l10n.isArabic)
                    if let clientJobID = UUID(uuidString: notificationID) {
                        PushRegistrar.shared.serverJobCreated(clientJobID: clientJobID, serverJobID: jobID,
                                                              configuration: configuration, language: l10n.isArabic ? "ar" : "en")
                    }
                }
                announce(l10n.t("وصل الفيديو. بصير يشاهده الآن. يمكنك الانتقال إلى تطبيق آخر، وسيصلك إشعار عند الانتهاء.",
                                "The video arrived. Basir is watching it now. You can switch to another app; you'll be notified when it's done."))
            }
            guard let jobID = pending.jobID else { throw BasirError.invalidResponse("") }
            // 3. Follow the server's job, also after Basir was closed and opened again.
            phase = .working(detail: l10n.t("بصير يشاهد الفيديو", "Basir is watching the video"), done: 0, total: 0)
            let description = try await follow(jobID: jobID, requestKey: pending.key, client: client, l10n: l10n)
            var entry = VideoLibrary.Entry(id: pending.key, title: description.title.isEmpty ? shownTitle : description.title,
                                           youtubeURL: pending.youtubeURL, serverJobID: jobID, createdAt: Date(),
                                           durationSeconds: description.durationSeconds)
            // The small copy stays on the phone, so the video can be watched with its description.
            if pending.youtubeURL == nil, let keep = VideoLibrary.mediaURL(for: pending.key),
               FileManager.default.fileExists(atPath: keep.path) {
                entry.hasLocalVideo = true
            }
            VideoLibrary.save(description, entry: entry)
            VideoPending.clear()
            // The description is now on the phone; the server copy goes, as the
            // privacy setting asks (on by default). Questions then answer from
            // the description, and a YouTube video can still be watched again.
            let deleteCopy = UserDefaults.standard.object(forKey: "privacy_delete_server_copy") as? Bool ?? true
            if deleteCopy { try? await client.deleteServerTask(requestID: pending.key) }
            let notificationID = Self.notificationID(pending.key)
            JobWatcher.shared.stop(id: notificationID)
            if !Self.isActive {
                VideoCenter.shared.hasUnseenResult = true
                JobNotifier.show(JobNotifier.finished(task: .video, title: entry.title, partial: description.isPartial,
                                                      arabic: l10n.isArabic), id: notificationID)
            } else {
                JobNotifier.remove(notificationID)
            }
            phase = .finished(entry.id)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            announce(l10n.t("وصف الفيديو جاهز.", "The video description is ready."))
        } catch is CancellationError {
            phase = .idle
        } catch is Interrupted {
            // Kept as it is; Basir carries on from here when it comes back.
        } catch {
            if pending.jobID != nil, Self.isNetwork(error), !Self.isActive {
                // The job still runs on the server: keep following it when Basir comes back.
                return
            }
            Self.discardFiles(of: pending)
            VideoPending.clear()
            let message = Self.message(for: error, l10n: l10n)
            phase = .failed(message)
            announce(message)
        }
    }

    private func follow(jobID: String, requestKey: String, client: ProxyClient, l10n: L10n) async throws -> VideoDescription {
        var misses = 0
        var lastAnnounced = -1
        while true {
            try Task.checkCancellation()
            let progress: SummaryJobProgress
            do {
                progress = try await client.summaryJobProgress(jobID: jobID, requestID: requestKey)
                misses = 0
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // The connection drops while iOS suspends Basir; the job goes on.
                misses += 1
                if misses >= 60 { throw error }
                try await Task.sleep(nanoseconds: 5_000_000_000)
                continue
            }
            if progress.isFinished {
                return try VideoDescription.decode(try await client.jobSummary(jobID: jobID, requestID: requestKey))
            }
            if progress.isFailed { throw BasirError.conversionFailed(progress.error ?? "") }
            // Steps: the overview, one per ten minutes of video, then writing.
            let parts = max(1, progress.total - 2)
            let detail: String
            if progress.current < 1 {
                detail = l10n.t("بصير يشاهد الفيديو كاملًا", "Basir is watching the whole video")
            } else if progress.current <= parts {
                detail = l10n.t("جارٍ وصف المشاهد، الجزء \(progress.current) من \(parts)",
                                "Describing the scenes, part \(progress.current) of \(parts)")
            } else {
                detail = l10n.t("جارٍ كتابة الوصف", "Writing the description")
            }
            phase = .working(detail: detail, done: progress.current, total: progress.total)
            let percent = progress.total > 0 ? progress.current * 100 / progress.total : 0
            if percent / 25 != lastAnnounced, progress.total > 2 {
                lastAnnounced = percent / 25
                announce(l10n.t("وصف الفيديو: \(percent) بالمئة", "Video description: \(percent) percent"))
            }
            try await Task.sleep(nanoseconds: 4_000_000_000)
        }
    }

    // MARK: Helpers

    private static var isActive: Bool { UIApplication.shared.applicationState == .active }

    private static func isNetwork(_ error: Error) -> Bool {
        (error as? URLError) != nil || (error as NSError).domain == NSURLErrorDomain
    }

    /// The files of a description that will not finish.
    private static func discardFiles(of pending: VideoPending) {
        if let name = pending.originalName, let folder = VideoLibrary.folder {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
        if VideoLibrary.description(for: pending.key) == nil, let media = VideoLibrary.mediaURL(for: pending.key) {
            try? FileManager.default.removeItem(at: media)
        }
    }

    static func fingerprint(text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// The same album video always gets the same key (its size and first
    /// megabytes), so asking again resumes the server job instead of paying twice.
    static func fingerprint(file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        hasher.update(data: try handle.read(upToCount: 4 * 1024 * 1024) ?? Data())
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.int64Value ?? 0
        hasher.update(data: Data("\(size)".utf8))
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func notificationID(_ key: String) -> String {
        let hex = Array(fingerprint(text: key).prefix(32).uppercased())
        let parts = [0..<8, 8..<12, 12..<16, 16..<20, 20..<32].map { String(hex[$0]) }
        return parts.joined(separator: "-")
    }

    static func message(for error: Error, l10n: L10n) -> String {
        switch error {
        case VideoCompressor.Failure.tooLong:
            return l10n.t("الفيديو أطول من ساعة. اختر فيديو مدته ساعة أو أقل.",
                          "The video is longer than an hour. Choose one that is an hour or shorter.")
        case VideoCompressor.Failure.unreadable:
            return l10n.t("تعذّر فتح هذا الفيديو. جرّب فيديو آخر.", "This video could not be opened. Try another one.")
        case VideoCompressor.Failure.tooLarge:
            return l10n.t("تعذّر تصغير الفيديو بما يكفي لإرساله. جرّب فيديو أقصر.",
                          "The video could not be made small enough to send. Try a shorter one.")
        case BasirError.conversionFailed(let reason) where reason.lowercased().contains("longer than one hour"):
            return l10n.t("الفيديو أطول من ساعة. اختر فيديو مدته ساعة أو أقل.",
                          "The video is longer than an hour. Choose one that is an hour or shorter.")
        case BasirError.conversionFailed(let reason) where reason.lowercased().contains("public"):
            return l10n.t("تعذّر فتح الفيديو. إذا كان رابط YouTube، تأكد أن الفيديو عام وليس خاصًا أو مقيّدًا.",
                          "The video could not be opened. If it's a YouTube link, check that the video is public, not private or restricted.")
        default:
            return DocumentAssistant.message(for: error, l10n: l10n)
        }
    }

    private func announce(_ text: String) {
        UIAccessibility.post(notification: .announcement, argument: text)
    }
}
