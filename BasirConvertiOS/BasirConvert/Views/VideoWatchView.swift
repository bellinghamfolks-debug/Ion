import AVFoundation
import AVKit
import SwiftUI
import WebKit

/// The player under "Watch with description": the video kept on the phone,
/// or a YouTube video in YouTube's own embedded player.
@MainActor
protocol DescribedPlayer: AnyObject {
    func currentTime() async -> Double?
    func play()
    func pause()
    func seek(to seconds: Double)
    func setVolume(_ volume: Float)
}

@MainActor
final class LocalVideoPlayer: DescribedPlayer {
    let player: AVPlayer

    init(url: URL) { player = AVPlayer(url: url) }

    func currentTime() async -> Double? {
        let seconds = CMTimeGetSeconds(player.currentTime())
        return seconds.isFinite ? seconds : nil
    }
    func play() { player.play() }
    func pause() { player.pause() }
    func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: max(0, seconds), preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }
    func setVolume(_ volume: Float) { player.volume = volume }
}

@MainActor
final class YouTubeVideoPlayer: NSObject, DescribedPlayer, WKScriptMessageHandler {
    let webView: WKWebView
    var onReady: (() -> Void)?
    var onError: ((Int) -> Void)?

    init(pageURL: URL) {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let controller = WKUserContentController()
        configuration.userContentController = controller
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        controller.add(WeakMessageHandler(self), name: "basir")
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.load(URLRequest(url: pageURL))
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let event = body["event"] as? String else { return }
        switch event {
        case "ready": onReady?()
        case "error": onError?((body["code"] as? Int) ?? 0)
        default: break
        }
    }

    func currentTime() async -> Double? {
        let value = try? await webView.evaluateJavaScript("player && player.getCurrentTime ? player.getCurrentTime() : -1")
        guard let seconds = (value as? NSNumber)?.doubleValue, seconds >= 0 else { return nil }
        return seconds
    }
    func play() { webView.evaluateJavaScript("player && player.playVideo()", completionHandler: nil) }
    func pause() { webView.evaluateJavaScript("player && player.pauseVideo()", completionHandler: nil) }
    func seek(to seconds: Double) {
        webView.evaluateJavaScript("player && player.seekTo(\(max(0, seconds)), true)", completionHandler: nil)
    }
    func setVolume(_ volume: Float) {
        webView.evaluateJavaScript("player && player.setVolume(\(Int(volume * 100)))", completionHandler: nil)
    }
}

/// WKUserContentController keeps its handlers alive; this breaks the cycle.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}

/// Says each description at its moment, over the video turned down, or with
/// the video paused for each one when the person chooses. Play and Pause
/// follow the person: a description never starts the video again after
/// they paused it.
@MainActor
final class DescribedWatchController: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var current: String = ""
    /// What the person asked for: playing or paused.
    @Published private(set) var playing = false
    @Published var describing = true {
        didSet { if !describing { speech.stopSpeaking(at: .immediate) } }
    }
    /// Pause the video for every description instead of turning it down.
    @Published var alwaysPause = UserDefaults.standard.bool(forKey: "video_watch_always_pause") {
        didSet { UserDefaults.standard.set(alwaysPause, forKey: "video_watch_always_pause") }
    }

    let cues: [DescriptionCue]
    let player: DescribedPlayer
    private let arabic: Bool
    private let speech = AVSpeechSynthesizer()
    private var next = 0
    private var lastTime: Double = 0
    private var ticker: Task<Void, Never>?
    /// The video is held still until the description ends ("always pause").
    private var holding = false

    init(cues: [DescriptionCue], player: DescribedPlayer, arabic: Bool) {
        self.cues = cues
        self.player = player
        self.arabic = arabic
        super.init()
        speech.delegate = self
    }

    func start() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }

    func stop() {
        ticker?.cancel()
        speech.stopSpeaking(at: .immediate)
        player.pause()
        playing = false
    }

    func togglePlay() {
        if playing {
            playing = false
            player.pause()
            if speech.isSpeaking { speech.pauseSpeaking(at: .word) }
        } else {
            playing = true
            if speech.isPaused { speech.continueSpeaking() }
            // During a description that holds the video, it plays when the description ends.
            if !(holding && speech.isSpeaking) {
                holding = false
                player.setVolume(speech.isSpeaking ? 0.3 : 1)
                player.play()
            }
        }
    }

    func jump(by seconds: Double) {
        Task {
            let now = await player.currentTime() ?? lastTime
            seek(to: now + seconds)
        }
    }

    func previousDescription() {
        Task {
            let now = await player.currentTime() ?? lastTime
            let index = (AudioDescription.currentIndex(at: now - 2, in: cues) ?? 0)
            seek(to: Double(cues.indices.contains(index) ? cues[index].time : 0))
        }
    }

    func nextDescription() {
        Task {
            let now = await player.currentTime() ?? lastTime
            let index = AudioDescription.nextIndex(at: now + 1, in: cues)
            if cues.indices.contains(index) { seek(to: Double(cues[index].time)) }
        }
    }

    func repeatDescription() {
        guard let index = AudioDescription.currentIndex(at: lastTime, in: cues) else { return }
        say(index)
    }

    private func seek(to seconds: Double) {
        speech.stopSpeaking(at: .immediate)
        holding = false
        player.seek(to: seconds)
        player.setVolume(1)
        if playing { player.play() }
        lastTime = seconds
        next = AudioDescription.nextIndex(at: seconds, in: cues)
    }

    private func tick() async {
        guard let now = await player.currentTime() else { return }
        // A jump (the player's own controls, or ours) restarts from there.
        if abs(now - lastTime) > 3 {
            next = AudioDescription.nextIndex(at: now, in: cues)
            if speech.isSpeaking && !holding { speech.stopSpeaking(at: .immediate) }
        }
        // Played from the video's own controls: follow it.
        if !playing, !holding, now > lastTime + 0.2 { playing = true }
        lastTime = now
        guard describing, playing, !speech.isSpeaking, !speech.isPaused, cues.indices.contains(next),
              Double(cues[next].time) <= now + 0.2 else { return }
        say(next)
        next += 1
    }

    private func say(_ index: Int) {
        let cue = cues[index]
        current = cue.text
        speech.stopSpeaking(at: .immediate)
        if alwaysPause {
            holding = true
            player.pause()
        } else {
            // Lower still while someone is talking, so the description is heard.
            player.setVolume(cue.nearSpeech ? 0.2 : 0.35)
        }
        let utterance = AVSpeechUtterance(string: cue.text)
        utterance.voice = AVSpeechSynthesisVoice(language: arabic ? "ar-SA" : "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05
        speech.speak(utterance)
        UIAccessibility.post(notification: .layoutChanged, argument: nil)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finishedSpeaking() }
    }

    private func finishedSpeaking() {
        player.setVolume(1)
        if holding {
            holding = false
            if playing { player.play() }
        }
    }
}

/// "Watch with description".
struct VideoWatchView: View {
    @EnvironmentObject private var l10n: L10n
    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller: DescribedWatchController
    @State private var failure: String?
    private var local: LocalVideoPlayer? { controller.player as? LocalVideoPlayer }
    private var youtube: YouTubeVideoPlayer? { controller.player as? YouTubeVideoPlayer }

    init(video: VideoDescription, localURL: URL?, youtubePage: URL?, arabic: Bool) {
        // Made once for the life of the screen (StateObject evaluates this once).
        _controller = StateObject(wrappedValue: {
            let cues = AudioDescription.cues(video, arabic: arabic)
            let player: DescribedPlayer = localURL.map { LocalVideoPlayer(url: $0) }
                ?? YouTubeVideoPlayer(pageURL: youtubePage ?? URL(string: "about:blank")!)
            return DescribedWatchController(cues: cues, player: player, arabic: arabic)
        }())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BasirSpacing.l) {
                    Group {
                        if let local {
                            VideoPlayer(player: local.player)
                        } else if let youtube {
                            WebPlayerView(webView: youtube.webView)
                        }
                    }
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityLabel(l10n.t("الفيديو", "The video"))

                    if let failure { InlineMessage(text: failure, isError: true) }

                    VStack(alignment: .leading, spacing: BasirSpacing.s) {
                        Text(l10n.t("الوصف الآن", "Describing now")).font(.headline).accessibilityAddTraits(.isHeader)
                        Text(controller.current.isEmpty ? l10n.t("سيبدأ الوصف مع بداية التشغيل.", "Descriptions start when the video plays.")
                                                        : controller.current)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .glassSurface()
                    .accessibilityElement(children: .combine)

                    PrimaryActionButton(title: controller.playing ? l10n.t("إيقاف مؤقت", "Pause") : l10n.t("تشغيل", "Play"),
                                        systemImage: controller.playing ? "pause.fill" : "play.fill") { controller.togglePlay() }
                    AdaptiveStack {
                        CardActionButton(title: l10n.t("رجوع 10 ثوانٍ", "Back 10 seconds"), systemImage: "gobackward.10") { controller.jump(by: -10) }
                        CardActionButton(title: l10n.t("تقديم 10 ثوانٍ", "Forward 10 seconds"), systemImage: "goforward.10") { controller.jump(by: 10) }
                    }
                    AdaptiveStack {
                        CardActionButton(title: l10n.t("الوصف السابق", "Previous description"), systemImage: "backward.end.fill") { controller.previousDescription() }
                        CardActionButton(title: l10n.t("الوصف التالي", "Next description"), systemImage: "forward.end.fill") { controller.nextDescription() }
                    }
                    CardActionButton(title: l10n.t("أعد الوصف", "Repeat the description"), systemImage: "arrow.counterclockwise") { controller.repeatDescription() }
                    Toggle(l10n.t("الوصف الصوتي", "Audio description"), isOn: $controller.describing)
                    Toggle(l10n.t("أوقف الفيديو عند كل وصف", "Pause the video for every description"), isOn: $controller.alwaysPause)
                    Text(l10n.t("عند إيقاف هذا الخيار، يستمر الفيديو بصوت منخفض أثناء الوصف.",
                                "With this off, the video keeps playing, turned down, while each description is said."))
                        .font(.footnote)
                        .foregroundStyle(BasirPalette.secondaryText)
                }
                .appScreenContent()
            }
            .background(BasirPalette.background.ignoresSafeArea())
            .navigationTitle(l10n.t("مشاهدة مع الوصف", "Watch with description"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(l10n.t("إغلاق", "Close")) { controller.stop(); dismiss() }
                }
            }
        }
        .accessibilityAction(.magicTap) { controller.togglePlay() }
        .escapeToDismiss { controller.stop(); dismiss() }
        .onAppear {
            controller.start()
            youtube?.onError = { code in
                failure = [101, 150, 152, 153].contains(code)
                    ? l10n.t("صاحب هذا الفيديو لا يسمح بتشغيله خارج YouTube. ما زال الوصف كاملًا متاحًا في صفحة الوصف.",
                             "This video's owner doesn't allow it to play outside YouTube. The full description is still on the description page.")
                    : l10n.t("تعذّر تشغيل الفيديو.", "The video could not be played.")
            }
        }
        .onDisappear { controller.stop() }
    }
}

private struct WebPlayerView: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ view: WKWebView, context: Context) { }
}
