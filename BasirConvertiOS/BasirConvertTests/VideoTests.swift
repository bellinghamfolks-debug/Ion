import XCTest
@testable import BasirConvert

final class VideoTests: XCTestCase {
    private let watch = "https://www.youtube.com/watch?v=dQw4w9WgXcQ"

    func testEveryFormOfYouTubeLinkBecomesOneWatchURL() {
        for link in [watch, "youtu.be/dQw4w9WgXcQ", "https://youtu.be/dQw4w9WgXcQ?si=abc&t=30",
                     "https://m.youtube.com/watch?v=dQw4w9WgXcQ&list=PL1", "https://www.youtube.com/shorts/dQw4w9WgXcQ",
                     "https://youtube.com/live/dQw4w9WgXcQ", "شاهد هذا https://youtu.be/dQw4w9WgXcQ رائع"] {
            XCTAssertEqual(YouTubeLink.watchURL(from: link), watch, link)
        }
    }

    func testOtherLinksAreRefused() {
        for link in ["https://vimeo.com/123", "https://www.youtube.com/@channel", "https://youtube.com/playlist?list=PL1",
                     "https://evil.example/watch?v=dQw4w9WgXcQ", "", "youtube.com/watch?v=short"] {
            XCTAssertNil(YouTubeLink.watchURL(from: link), link)
        }
    }

    private let serverJSON = """
    {"language":"ar","source":"youtube","title":"درس الطبخ","kind":"وصفة","one_line":"طاهٍ يحضّر الكبسة.",
     "summary":"يغسل الأرز ثم يطبخ اللحم.","duration_seconds":1500,"setting":"مطبخ","people":["رجل بمريلة"],
     "spoken_language":"العربية","has_speech":true,
     "chapters":[{"start":0,"title":"المكونات","description":"يعرض المكونات."},{"start":700,"title":"الطبخ","description":""}],
     "scenes":[{"start":10,"end":60,"description":"أرز في وعاء"},{"start":710,"end":760,"description":"لحم في قدر"}],
     "on_screen_text":[{"time":20,"text":"كبسة لحم"}],
     "speech":[{"time":30,"speaker":"الطاهي","summary":"يشرح المقادير."}],
     "segments_described":3,"segments_total":3,"notes":[]}
    """

    func testTheServerDescriptionDecodesAndScenesFallUnderTheirChapters() throws {
        let video = try VideoDescription.decode(Data(serverJSON.utf8))
        XCTAssertEqual(video.oneLine, "طاهٍ يحضّر الكبسة.")
        XCTAssertEqual(video.durationSeconds, 1500)
        XCTAssertEqual(video.scenes(in: video.chapters[0]).map(\.start), [10])
        XCTAssertEqual(video.scenes(in: video.chapters[1]).map(\.start), [710])
        XCTAssertFalse(video.isPartial)
        // Kept on the phone and read back the same.
        XCTAssertEqual(try VideoDescription.decode(video.encoded()), video)
    }

    func testTimesAreWrittenAndSpoken() {
        XCTAssertEqual(VideoDescription.clock(185), "3:05")
        XCTAssertEqual(VideoDescription.clock(3725), "1:02:05")
        XCTAssertEqual(VideoDescription.spokenTime(185, arabic: true), "الدقيقة 3 والثانية 5")
        XCTAssertEqual(VideoDescription.spokenTime(120, arabic: false), "minute 2")
    }

    func testTheReaderGetsHeadingsForEachChapter() throws {
        let video = try VideoDescription.decode(Data(serverJSON.utf8))
        let blocks = VideoReaderBlocks.blocks(video, arabic: true)
        let headings = blocks.filter(\.isHeading).map(\.text)
        XCTAssertEqual(headings.first, "درس الطبخ")
        XCTAssertTrue(headings.contains("0:00 المكونات"))
        XCTAssertTrue(headings.contains("11:40 الطبخ"))
        XCTAssertTrue(blocks.contains { $0.text == "0:20: «كبسة لحم»" })
    }

    func testAnHourAndAMinuteIsAcceptedButNotTwo() {
        XCTAssertTrue(VideoCompressor.isAllowed(seconds: 3600 + 60))
        XCTAssertFalse(VideoCompressor.isAllowed(seconds: 7200))
    }

    func testNotificationsSpeakOfTheVideo() {
        XCTAssertTrue(JobNotifier.ready(task: .video, title: "t", arabic: true).body.contains("وصف الفيديو جاهز"))
        XCTAssertTrue(JobNotifier.working(task: .video, title: "t", percent: 40, uploading: false, arabic: true)
            .body.contains("جارٍ وصف الفيديو"))
    }

    func testCuesSayTheChapterWithTheSceneAndTheTextOnScreenAtItsOwnTime() throws {
        let video = try VideoDescription.decode(Data(serverJSON.utf8))
        let cues = AudioDescription.cues(video, arabic: true)
        XCTAssertEqual(cues.map(\.time), [10, 20, 710])
        XCTAssertEqual(cues[0].text, "الفصل: المكونات. أرز في وعاء")
        XCTAssertEqual(cues[1].text, "مكتوب على الشاشة: «كبسة لحم».")
        XCTAssertTrue(cues[2].text.hasPrefix("الفصل: الطبخ."))
        // Someone speaks at 0:30: the video goes lower under the cue at 0:20.
        XCTAssertEqual(cues.map(\.nearSpeech), [false, true, false])
    }

    func testFindingTheNextAndCurrentCue() throws {
        let cues = AudioDescription.cues(try VideoDescription.decode(Data(serverJSON.utf8)), arabic: false)
        XCTAssertEqual(AudioDescription.nextIndex(at: 0, in: cues), 0)
        XCTAssertEqual(AudioDescription.nextIndex(at: 100, in: cues), 2)
        XCTAssertEqual(AudioDescription.nextIndex(at: 800, in: cues), 3)
        XCTAssertNil(AudioDescription.currentIndex(at: 5, in: cues))
        XCTAssertEqual(AudioDescription.currentIndex(at: 720, in: cues), 2)
    }

    private var dialogueJSON: String {
        serverJSON.replacingOccurrences(of: "\"notes\":[]}", with: """
        "notes":[],
         "dialogue":[{"start":12,"end":15,"speaker":"المذيعة","language":"en","translation":"مرحبًا بكم."},
                     {"start":5,"end":8,"speaker":"المذيعة","language":"en","translation":"أهلًا."},
                     {"start":16,"end":14,"speaker":"الضيف","language":"en","translation":"شكرًا لاستضافتي."},
                     {"start":20,"end":23,"speaker":"","language":"fr","translation":"إلى اللقاء."}]}
        """)
    }

    func testADescriptionMadeBeforeTranslationHasNoDialogue() throws {
        let video = try VideoDescription.decode(Data(serverJSON.utf8))
        XCTAssertNil(video.dialogue)
        XCTAssertTrue(AudioDescription.dialogueCues(video).isEmpty)
        XCTAssertFalse(VideoReaderBlocks.blocks(video, arabic: true).contains { $0.text == "الحوار مترجمًا" })
    }

    func testTranslatedLinesNameTheSpeakerOnlyWhenItChanges() throws {
        let video = try VideoDescription.decode(Data(dialogueJSON.utf8))
        let lines = AudioDescription.dialogueCues(video)
        XCTAssertEqual(lines.map(\.start), [5, 12, 16, 20])
        XCTAssertEqual(lines.map(\.text), ["المذيعة: أهلًا.", "مرحبًا بكم.", "الضيف: شكرًا لاستضافتي.", "إلى اللقاء."])
        // A line that ends before it starts ends where it starts.
        XCTAssertEqual(lines[2].end, 16)
        XCTAssertEqual(try VideoDescription.decode(video.encoded()), video)
        let blocks = VideoReaderBlocks.blocks(video, arabic: true)
        XCTAssertTrue(blocks.contains { $0.isHeading && $0.text == "الحوار مترجمًا" })
        XCTAssertTrue(blocks.contains { $0.text == "0:16: الضيف: شكرًا لاستضافتي." })
    }

    func testALineIsStillSaidJustAfterItEndsButNotLater() throws {
        let lines = AudioDescription.dialogueCues(try VideoDescription.decode(Data(dialogueJSON.utf8)))
        XCTAssertEqual(AudioDescription.nextDialogue(at: 0, in: lines), 0)
        XCTAssertEqual(AudioDescription.nextDialogue(at: 10, in: lines), 0)   // ended at 8, within the grace
        XCTAssertEqual(AudioDescription.nextDialogue(at: 11, in: lines), 1)
        XCTAssertEqual(AudioDescription.nextDialogue(at: 30, in: lines), 4)
    }

    func testDescriptionsAreFittedIntoThePausesBetweenLines() {
        let short = "باب يُفتح."
        let long = String(repeating: "رجل يمشي في شارع مزدحم. ", count: 4)
        XCTAssertTrue(AudioDescription.fitsBefore(short, now: 10, nextLineStart: nil))
        XCTAssertTrue(AudioDescription.fitsBefore(short, now: 10, nextLineStart: 12))
        XCTAssertFalse(AudioDescription.fitsBefore(long, now: 10, nextLineStart: 12))
        XCTAssertTrue(AudioDescription.fitsBefore(long, now: 10, nextLineStart: 30))
        // A line already under way does not hold the description back.
        XCTAssertTrue(AudioDescription.fitsBefore(long, now: 10, nextLineStart: 9))
    }

    func testAVideoUnderWayIsKeptAcrossARestart() {
        VideoPending.clear()
        var pending = VideoPending(key: "video-abc", title: "رحلة", originalName: "original-1.mov")
        pending.save()
        XCTAssertEqual(VideoPending.load(), pending)
        pending.compressed = true
        pending.jobID = String(repeating: "a", count: 32)
        pending.save()
        XCTAssertEqual(VideoPending.load()?.jobID, pending.jobID)
        VideoPending.clear()
        XCTAssertNil(VideoPending.load())
    }
}
