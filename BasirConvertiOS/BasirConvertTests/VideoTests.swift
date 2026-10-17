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

    func testCuesSayTheChapterTheSceneAndTheTextOnScreenAtTheSceneStart() throws {
        let video = try VideoDescription.decode(Data(serverJSON.utf8))
        let cues = AudioDescription.cues(video, arabic: true)
        XCTAssertEqual(cues.map(\.time), [10, 710])
        XCTAssertEqual(cues[0].text, "الفصل: المكونات. أرز في وعاء مكتوب على الشاشة: «كبسة لحم».")
        XCTAssertTrue(cues[1].text.hasPrefix("الفصل: الطبخ."))
        // Someone speaks at 0:30, within reach of the first cue: the video pauses for it.
        XCTAssertTrue(cues[0].nearSpeech)
        XCTAssertFalse(cues[1].nearSpeech)
    }

    func testFindingTheNextAndCurrentCue() throws {
        let cues = AudioDescription.cues(try VideoDescription.decode(Data(serverJSON.utf8)), arabic: false)
        XCTAssertEqual(AudioDescription.nextIndex(at: 0, in: cues), 0)
        XCTAssertEqual(AudioDescription.nextIndex(at: 100, in: cues), 1)
        XCTAssertEqual(AudioDescription.nextIndex(at: 800, in: cues), 2)
        XCTAssertNil(AudioDescription.currentIndex(at: 5, in: cues))
        XCTAssertEqual(AudioDescription.currentIndex(at: 720, in: cues), 1)
    }
}
