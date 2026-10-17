import Foundation

/// "Watch with description": what Basir says while the video plays, and when.
///
/// Each scene's description is said when the scene starts, with a new
/// chapter's title before it and the text that appears on screen around
/// then after it. The video keeps playing, turned down, under the
/// description (further down while someone is speaking), or pauses for each
/// description when the person chooses.
struct DescriptionCue: Equatable, Sendable {
    let time: Int
    let text: String
    /// Someone speaks within this many seconds of the cue: the video goes lower.
    let nearSpeech: Bool
}

enum AudioDescription {
    /// Seconds around a cue in which speech counts as "talking now".
    static let speechWindow = 12
    /// On-screen text this close to a scene is said with it.
    static let textWindow = 4

    static func cues(_ video: VideoDescription, arabic: Bool) -> [DescriptionCue] {
        var items: [(time: Int, text: String)] = []
        var chapterStarts = Dictionary(video.chapters.map { ($0.start, $0.title) }, uniquingKeysWith: { a, _ in a })
        var texts = video.onScreenText
        for scene in video.scenes.sorted(by: { $0.start < $1.start }) {
            var parts: [String] = []
            // A chapter starting at (or just before) this scene is announced with it.
            if let key = chapterStarts.keys.filter({ $0 <= scene.start && scene.start - $0 <= 30 }).min(by: { scene.start - $0 < scene.start - $1 }),
               let title = chapterStarts.removeValue(forKey: key) {
                parts.append(arabic ? "الفصل: \(title)." : "Chapter: \(title).")
            }
            parts.append(scene.description)
            let near = texts.filter { abs($0.time - scene.start) <= textWindow || ($0.time >= scene.start && $0.time <= min(scene.end, scene.start + textWindow)) }
            if !near.isEmpty {
                let quoted = near.map { "«\($0.text)»" }.joined(separator: arabic ? "، " : ", ")
                parts.append(arabic ? "مكتوب على الشاشة: \(quoted)." : "On screen: \(quoted).")
                texts.removeAll { item in near.contains(item) }
            }
            items.append((scene.start, parts.joined(separator: " ")))
        }
        for text in texts {
            items.append((text.time, arabic ? "مكتوب على الشاشة: «\(text.text)»." : "On screen: “\(text.text)”."))
        }
        for (start, title) in chapterStarts {
            items.append((start, arabic ? "الفصل: \(title)." : "Chapter: \(title)."))
        }
        let speech = video.speech.map(\.time)
        return items.sorted { $0.time < $1.time }.map { item in
            DescriptionCue(time: item.time, text: item.text,
                           nearSpeech: speech.contains { abs($0 - item.time) <= speechWindow })
        }
    }

    /// The first cue still to come at `time` (seconds into the video).
    static func nextIndex(at time: Double, in cues: [DescriptionCue]) -> Int {
        cues.firstIndex { Double($0.time) >= time - 0.5 } ?? cues.count
    }

    /// The cue being described at `time`: the last one that has started.
    static func currentIndex(at time: Double, in cues: [DescriptionCue]) -> Int? {
        cues.lastIndex { Double($0.time) <= time + 0.5 }
    }
}
