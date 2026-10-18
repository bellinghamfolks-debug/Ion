import Foundation

/// A video described for listening, as the server returns it
/// (GET /api/jobs/{id}/summary for a video job): what it is, its chapters
/// with their times, the scenes as they happen, the text on screen and who
/// says what. Times are seconds from the start of the video.
/// What the person asks Basir for: the description, the dialogue translated,
/// or both. The server makes only what was asked for.
enum VideoScope: String, Codable, CaseIterable, Identifiable, Sendable {
    case describe, both, translate
    var id: String { rawValue }
    /// The job's mode on the server.
    var serverMode: String {
        switch self {
        case .describe: return "video"
        case .both: return "video_dialogue"
        case .translate: return "video_translate"
        }
    }
    /// Part of the request key: the same video asked for differently is a different job.
    var keySuffix: String {
        switch self {
        case .describe: return ""
        case .both: return "-dialogue"
        case .translate: return "-translate"
        }
    }
    var describes: Bool { self != .translate }
    var translates: Bool { self != .describe }
}

struct VideoDescription: Codable, Equatable, Sendable {
    struct Chapter: Codable, Equatable, Identifiable, Sendable {
        var start: Int
        var title: String
        var description: String = ""
        var id: Int { start }
    }

    struct Scene: Codable, Equatable, Identifiable, Sendable {
        var start: Int
        var end: Int
        var description: String
        var id: String { "\(start)|\(description.prefix(24))" }
    }

    struct ScreenText: Codable, Equatable, Identifiable, Sendable {
        var time: Int
        var text: String
        var id: String { "\(time)|\(text)" }
    }

    struct Speech: Codable, Equatable, Identifiable, Sendable {
        var time: Int
        var speaker: String = ""
        var summary: String
        var id: String { "\(time)|\(summary.prefix(24))" }
    }

    /// A line spoken in another language, translated, timed to be said as it is spoken.
    struct DialogueLine: Codable, Equatable, Identifiable, Sendable {
        var start: Int
        var end: Int
        var speaker: String = ""
        var language: String = ""
        var translation: String
        var id: String { "\(start)|\(translation.prefix(24))" }
    }

    var language: String = "ar"
    var source: String = "upload"
    var title: String = ""
    var kind: String = ""
    var oneLine: String = ""
    var summary: String = ""
    var durationSeconds: Int = 0
    var setting: String = ""
    var people: [String] = []
    var spokenLanguage: String = ""
    var hasSpeech: Bool = true
    var chapters: [Chapter] = []
    var scenes: [Scene] = []
    var onScreenText: [ScreenText] = []
    var speech: [Speech] = []
    /// Missing in descriptions made before translation existed.
    var dialogue: [DialogueLine]? = nil
    var hasDialogue: Bool { !(dialogue ?? []).isEmpty }
    /// Scenes or text to describe (a translation-only result has none).
    var hasDescription: Bool { !scenes.isEmpty || !onScreenText.isEmpty }
    var segmentsDescribed: Int = 0
    var segmentsTotal: Int = 0
    var notes: [String] = []

    static func decode(_ data: Data) throws -> VideoDescription {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(VideoDescription.self, from: data)
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return try encoder.encode(self)
    }

    /// Whether part of the video could not be described.
    var isPartial: Bool { segmentsTotal > 0 && segmentsDescribed < segmentsTotal }

    /// The scenes of one chapter: from its start to the next chapter's.
    func scenes(in chapter: Chapter) -> [Scene] {
        let next = chapters.first { $0.start > chapter.start }?.start ?? Int.max
        return scenes.filter { $0.start >= chapter.start && $0.start < next }
    }

    /// 3:05, or 1:02:05 past the hour.
    static func clock(_ seconds: Int) -> String {
        let total = max(0, seconds)
        let hours = total / 3600, minutes = (total % 3600) / 60, secs = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%d:%02d", minutes, secs)
    }

    /// How a time is said: "الدقيقة 3 والثانية 5" reads better aloud than "3:05".
    static func spokenTime(_ seconds: Int, arabic: Bool) -> String {
        let total = max(0, seconds)
        let hours = total / 3600, minutes = (total % 3600) / 60, secs = total % 60
        if arabic {
            var parts: [String] = []
            if hours > 0 { parts.append("الساعة \(hours)") }
            parts.append("الدقيقة \(minutes)")
            if secs > 0 { parts.append("الثانية \(secs)") }
            return parts.joined(separator: " و")
        }
        var parts: [String] = []
        if hours > 0 { parts.append("hour \(hours)") }
        parts.append("minute \(minutes)")
        if secs > 0 { parts.append("second \(secs)") }
        return parts.joined(separator: ", ")
    }
}

/// YouTube links Basir accepts, in the forms people paste and share.
enum YouTubeLink {
    /// The canonical watch URL, or nil for anything that is not one YouTube video.
    static func watchURL(from text: String) -> String? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // A shared message often has words around the link.
        if let found = value.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map(String.init).first(where: { $0.lowercased().contains("youtu") }) {
            value = found
        }
        guard !value.isEmpty else { return nil }
        if !value.contains("://") { value = "https://" + value }
        guard let components = URLComponents(string: value), var host = components.host?.lowercased() else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        if host.hasPrefix("m.") { host.removeFirst(2) }
        let parts = components.path.split(separator: "/").map(String.init)
        var id = ""
        if host == "youtu.be" {
            id = parts.first ?? ""
        } else if ["youtube.com", "music.youtube.com", "youtube-nocookie.com"].contains(host) {
            if parts.first == "watch" {
                id = components.queryItems?.first(where: { $0.name == "v" })?.value ?? ""
            } else if parts.count >= 2, ["shorts", "live", "embed", "v"].contains(parts[0]) {
                id = parts[1]
            }
        }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
        guard id.count == 11, id.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return "https://www.youtube.com/watch?v=\(id)"
    }
}

/// The description as reader blocks, so the in-app reader reads it from start
/// to end with headings to jump between parts.
enum VideoReaderBlocks {
    static func blocks(_ video: VideoDescription, arabic: Bool) -> [ReaderBlock] {
        var blocks: [ReaderBlock] = []
        func add(_ kind: ReaderBlock.Kind, _ text: String) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            blocks.append(ReaderBlock(id: blocks.count, kind: kind, text: trimmed))
        }
        let t = { (ar: String, en: String) in arabic ? ar : en }
        add(.heading(1), video.title.isEmpty ? t("وصف الفيديو", "Video description") : video.title)
        add(.paragraph, video.oneLine)
        add(.paragraph, t("المدة: ", "Length: ") + VideoDescription.clock(video.durationSeconds))
        if !video.summary.isEmpty {
            add(.heading(2), t("الملخص", "Summary"))
            add(.paragraph, video.summary)
        }
        if !video.people.isEmpty {
            add(.heading(2), t("الأشخاص", "People"))
            video.people.forEach { add(.listItem(ordered: false, level: 0), $0) }
        }
        if video.chapters.isEmpty {
            if !video.scenes.isEmpty { add(.heading(2), t("المشاهد", "Scenes")) }
            video.scenes.forEach { add(.paragraph, "\(VideoDescription.clock($0.start)): \($0.description)") }
        } else {
            for chapter in video.chapters {
                add(.heading(2), "\(VideoDescription.clock(chapter.start)) \(chapter.title)")
                add(.paragraph, chapter.description)
                video.scenes(in: chapter).forEach { add(.paragraph, "\(VideoDescription.clock($0.start)): \($0.description)") }
            }
        }
        if !video.onScreenText.isEmpty {
            add(.heading(2), t("النصوص على الشاشة", "Text on screen"))
            video.onScreenText.forEach { add(.paragraph, "\(VideoDescription.clock($0.time)): «\($0.text)»") }
        }
        if let dialogue = video.dialogue, !dialogue.isEmpty {
            add(.heading(2), t("الحوار مترجمًا", "Dialogue, translated"))
            dialogue.forEach {
                let who = $0.speaker.isEmpty ? "" : "\($0.speaker): "
                add(.paragraph, "\(VideoDescription.clock($0.start)): \(who)\($0.translation)")
            }
        }
        if !video.speech.isEmpty {
            add(.heading(2), t("الكلام", "Speech"))
            video.speech.forEach {
                let who = $0.speaker.isEmpty ? "" : "\($0.speaker): "
                add(.paragraph, "\(VideoDescription.clock($0.time)): \(who)\($0.summary)")
            }
        }
        return blocks
    }
}
