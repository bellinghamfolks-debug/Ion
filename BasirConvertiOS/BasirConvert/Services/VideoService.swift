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
    }

    private static let indexName = "index.json"

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
        write(entries().filter { $0.id != id })
    }

    private static func write(_ entries: [Entry]) {
        guard let url = directory?.appendingPathComponent(indexName) else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(entries) { try? data.write(to: url, options: .atomic) }
    }
}

/// Keeps video work alive while the screen is closed: opening the tool again
/// shows the progress, or the finished description.
@MainActor
final class VideoCenter {
    static let shared = VideoCenter()
    let runner = VideoRunner()
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
    private var active: (key: String, configuration: ServerConfiguration)?

    var isBusy: Bool {
        switch phase {
        case .preparing, .uploading, .working: return true
        default: return false
        }
    }

    func reset() {
        if !isBusy { phase = .idle }
    }

    /// Stops the work here and on the server.
    func cancel() {
        task?.cancel()
        task = nil
        if let active {
            Task { _ = try? await ProxyClient(configuration: active.configuration).cancelServerTask(requestID: active.key) }
        }
        active = nil
        phase = .idle
    }

    func start(_ input: VideoInput, configuration: ServerConfiguration, l10n: L10n) {
        cancel()
        guard configuration.isConfigured else {
            phase = .failed(DocumentAssistant.message(for: BasirError.notConfigured, l10n: l10n))
            return
        }
        title = input.title
        active = nil
        task = Task { [weak self] in await self?.work(input, configuration: configuration, l10n: l10n) }
    }

    private func work(_ input: VideoInput, configuration: ServerConfiguration, l10n: L10n) async {
        let background = UIApplication.shared.beginBackgroundTask(withName: "Basir video")
        defer { UIApplication.shared.endBackgroundTask(background) }
        var prepared: URL?
        defer { if let prepared { try? FileManager.default.removeItem(at: prepared) } }
        do {
            let client = ProxyClient(configuration: configuration)
            let source: URL, contentType: String, seconds: Int?, youtube: String?, requestKey: String
            switch input {
            case .file(let url, _):
                phase = .preparing(0)
                announce(l10n.t("جارٍ تجهيز الفيديو.", "Preparing the video."))
                let made = try await VideoCompressor.prepare(url) { value in
                    Task { @MainActor [weak self] in
                        if case .preparing = self?.phase { self?.phase = .preparing(value) }
                    }
                }
                prepared = made.0
                source = made.0
                contentType = "video/mp4"
                seconds = made.1
                youtube = nil
                requestKey = "video-" + String(try Self.fingerprint(file: url).prefix(48))
            case .youtube(let link):
                let request = try JSONSerialization.data(withJSONObject: ["youtube_url": link])
                let file = FileManager.default.temporaryDirectory.appendingPathComponent("basir-video-\(UUID().uuidString).json")
                try request.write(to: file, options: .atomic)
                prepared = file
                source = file
                contentType = "application/json"
                seconds = nil
                youtube = link
                requestKey = "video-" + String(Self.fingerprint(text: link).prefix(48))
            }
            try Task.checkCancellation()
            active = (requestKey, configuration)
            phase = .uploading(0)
            if youtube == nil { announce(l10n.t("جارٍ إرسال الفيديو.", "Sending the video.")) }
            let shownTitle = title.isEmpty ? l10n.t("فيديو", "Video") : title
            let jobID = try await client.startVideoJob(
                source: source, contentType: contentType, seconds: seconds, requestID: requestKey, title: title,
                language: l10n.isArabic ? "ar" : "en") { value in
                Task { @MainActor [weak self] in
                    if case .uploading = self?.phase { self?.phase = .uploading(value) }
                }
            }
            let notificationID = Self.notificationID(requestKey)
            JobWatcher.shared.watch(id: notificationID, serverJobID: jobID, work: .video,
                                    title: l10n.t("وصف: \(shownTitle)", "Description: \(shownTitle)"), arabic: l10n.isArabic)
            if let clientJobID = UUID(uuidString: notificationID) {
                PushRegistrar.shared.serverJobCreated(clientJobID: clientJobID, serverJobID: jobID,
                                                      configuration: configuration, language: l10n.isArabic ? "ar" : "en")
            }
            phase = .working(detail: l10n.t("بصير يشاهد الفيديو", "Basir is watching the video"), done: 0, total: 0)
            announce(l10n.t("وصل الفيديو. بصير يشاهده الآن. يمكنك الانتقال إلى تطبيق آخر، وسيصلك إشعار عند الانتهاء.",
                            "The video arrived. Basir is watching it now. You can switch to another app; you'll be notified when it's done."))
            let description = try await follow(jobID: jobID, requestKey: requestKey, client: client, l10n: l10n)
            let entry = VideoLibrary.Entry(id: requestKey, title: description.title.isEmpty ? shownTitle : description.title,
                                           youtubeURL: youtube, serverJobID: jobID, createdAt: Date(),
                                           durationSeconds: description.durationSeconds)
            VideoLibrary.save(description, entry: entry)
            active = nil
            // The description is now on the phone; the server copy goes, as the
            // privacy setting asks (on by default). Questions then answer from
            // the description, and a YouTube video can still be watched again.
            let deleteCopy = UserDefaults.standard.object(forKey: "privacy_delete_server_copy") as? Bool ?? true
            if deleteCopy { try? await client.deleteServerTask(requestID: requestKey) }
            JobWatcher.shared.stop(id: notificationID)
            if UIApplication.shared.applicationState != .active {
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
        } catch {
            active = nil
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
