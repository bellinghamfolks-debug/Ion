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

/// What the video does while a translated line is said.
enum DialogueVideoMode: String, CaseIterable, Identifiable {
    case lower, full, pause
    var id: String { rawValue }
}

/// Says each description at its moment and translates the dialogue live.
///
/// Translated lines are said as they are spoken, over the video turned down
/// (or at full volume, or with the video paused, as the person chooses), in a
/// voice of their own, or by VoiceOver. Descriptions are fitted into the quiet
/// between lines, so the dialogue is never lost behind a description. Play and
/// Pause follow the person: nothing restarts a video they paused.
@MainActor
final class DescribedWatchController: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var current: String = ""
    @Published private(set) var subtitle: String = ""
    /// What the person asked for: playing or paused.
    @Published private(set) var playing = false
    @Published var describing = true {
        didSet { if !describing, speakingKind == .description { stopSpeaking() } }
    }
    /// Pause the video for every description instead of turning it down.
    @Published var alwaysPause = UserDefaults.standard.bool(forKey: "video_watch_always_pause") {
        didSet { UserDefaults.standard.set(alwaysPause, forKey: "video_watch_always_pause") }
    }
    @Published var translating = UserDefaults.standard.object(forKey: "video_watch_translate") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(translating, forKey: "video_watch_translate")
            if !translating, speakingKind == .dialogue { stopSpeaking() }
        }
    }
    @Published var dialogueMode = DialogueVideoMode(rawValue: UserDefaults.standard.string(forKey: "video_watch_dialogue_mode") ?? "") ?? .lower {
        didSet { UserDefaults.standard.set(dialogueMode.rawValue, forKey: "video_watch_dialogue_mode") }
    }
    /// Read by VoiceOver (its voice and speed) rather than Basir's own voices.
    @Published var useScreenReader = UserDefaults.standard.object(forKey: "video_watch_screen_reader") as? Bool
        ?? UIAccessibility.isVoiceOverRunning {
        didSet { UserDefaults.standard.set(useScreenReader, forKey: "video_watch_screen_reader") }
    }

    let cues: [DescriptionCue]
    let lines: [DialogueCue]
    let player: DescribedPlayer
    private let arabic: Bool
    private let speech = AVSpeechSynthesizer()
    private let descriptionVoice: AVSpeechSynthesisVoice?
    private let dialogueVoice: AVSpeechSynthesisVoice?
    private var nextCue = 0
    private var nextLine = 0
    private var lastTime: Double = 0
    private var ticker: Task<Void, Never>?
    /// The video is held still until what is being said ends.
    private var holding = false
    private enum Kind { case description, dialogue }
    private var speakingKind: Kind?
    private var lastSaid: (text: String, kind: Kind)?
    private var announcementDeadline: Date?
    private var waitingSince: Double?
    /// The utterance being said: a late "finished" from an earlier one is ignored.
    private var utteranceID: ObjectIdentifier?

    var hasDialogue: Bool { !lines.isEmpty }

    init(cues: [DescriptionCue], lines: [DialogueCue], player: DescribedPlayer, arabic: Bool) {
        self.cues = cues
        self.lines = lines
        self.player = player
        self.arabic = arabic
        // Two different voices, so a translated line is never mistaken for a description.
        let language = arabic ? "ar" : "en"
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(language) }
            .sorted { $0.quality.rawValue > $1.quality.rawValue }
        descriptionVoice = voices.first ?? AVSpeechSynthesisVoice(language: arabic ? "ar-SA" : "en-US")
        dialogueVoice = voices.first { $0.identifier != voices.first?.identifier && $0.gender != voices.first?.gender }
            ?? voices.dropFirst().first ?? descriptionVoice
        super.init()
        speech.delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(announcementFinished),
                                               name: UIAccessibility.announcementDidFinishNotification, object: nil)
    }

    func start() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }

    func stop() {
        ticker?.cancel()
        stopSpeaking()
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
            // While something holds the video, it plays when that ends.
            if !(holding && isBusy) {
                holding = false
                player.setVolume(isBusy ? volumeWhileSpeaking() : 1)
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

    /// Says again the last description or translated line.
    func repeatLast() {
        guard let last = lastSaid else { return }
        say(last.text, kind: last.kind)
    }

    private func seek(to seconds: Double) {
        stopSpeaking()
        holding = false
        player.seek(to: seconds)
        player.setVolume(1)
        if playing { player.play() }
        lastTime = seconds
        nextCue = AudioDescription.nextIndex(at: seconds, in: cues)
        nextLine = AudioDescription.nextDialogue(at: seconds, in: lines)
        waitingSince = nil
    }

    private var isBusy: Bool {
        if let deadline = announcementDeadline {
            if Date() < deadline { return true }
            announcementDeadline = nil
            finishedSpeaking()
        }
        return speech.isSpeaking || speech.isPaused
    }

    private func tick() async {
        guard let now = await player.currentTime() else { return }
        // A jump (the player's own controls, or ours) restarts from there.
        if abs(now - lastTime) > 3 {
            nextCue = AudioDescription.nextIndex(at: now, in: cues)
            nextLine = AudioDescription.nextDialogue(at: now, in: lines)
            if isBusy && !holding { stopSpeaking() }
        }
        // Played from the video's own controls: follow it.
        if !playing, !holding, now > lastTime + 0.2 { playing = true }
        lastTime = now
        // Lines already over are not worth saying late.
        while lines.indices.contains(nextLine), now > lines[nextLine].end + AudioDescription.dialogueGrace { nextLine += 1 }
        guard playing, !isBusy else { return }

        if translating, lines.indices.contains(nextLine), lines[nextLine].start <= now + 0.15 {
            let line = lines[nextLine]
            nextLine += 1
            subtitle = line.text
            say(line.text, kind: .dialogue)
            return
        }
        guard describing, cues.indices.contains(nextCue), Double(cues[nextCue].time) <= now + 0.2 else { return }
        // Only the latest scene is worth describing when several came due while waiting.
        while cues.indices.contains(nextCue + 1), Double(cues[nextCue + 1].time) <= now { nextCue += 1 }
        let cue = cues[nextCue]
        let upcoming = translating && lines.indices.contains(nextLine) ? lines[nextLine].start : nil
        // Said in the quiet between translated lines (or at once when the video pauses for it);
        // after twenty-five seconds of waiting it is said anyway.
        let waited = now - (waitingSince ?? now)
        if !alwaysPause, !AudioDescription.fitsBefore(cue.text, now: now, nextLineStart: upcoming), waited < 25 {
            if waitingSince == nil { waitingSince = now }
            return
        }
        waitingSince = nil
        nextCue += 1
        current = cue.text
        say(cue.text, kind: .description, nearSpeech: cue.nearSpeech)
    }

    private func volumeWhileSpeaking(nearSpeech: Bool = false) -> Float {
        switch speakingKind {
        case .dialogue: return dialogueMode == .full ? 1 : 0.25
        default: return nearSpeech ? 0.2 : 0.35
        }
    }

    private func say(_ text: String, kind: Kind, nearSpeech: Bool = false) {
        stopSpeaking()
        speakingKind = kind
        lastSaid = (text, kind)
        let pause = kind == .description ? alwaysPause : dialogueMode == .pause
        if pause {
            holding = true
            player.pause()
        } else {
            player.setVolume(volumeWhileSpeaking(nearSpeech: nearSpeech))
        }
        if useScreenReader && UIAccessibility.isVoiceOverRunning {
            // VoiceOver's own voice and speed; its finish notice ends the turn.
            announcementDeadline = Date().addingTimeInterval(AudioDescription.speakingTime(text) * 2 + 2)
            UIAccessibility.post(notification: .announcement,
                                 argument: NSAttributedString(string: text, attributes: [.accessibilitySpeechQueueAnnouncement: false]))
            return
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = kind == .dialogue ? dialogueVoice : descriptionVoice
        if kind == .dialogue, dialogueVoice?.identifier == descriptionVoice?.identifier {
            utterance.pitchMultiplier = 1.2   // one voice only: still told apart
        }
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * (kind == .dialogue ? 1.12 : 1.05)
        utteranceID = ObjectIdentifier(utterance)
        speech.speak(utterance)
    }

    private func stopSpeaking() {
        speech.stopSpeaking(at: .immediate)
        utteranceID = nil
        announcementDeadline = nil
        speakingKind = nil
    }

    @objc private func announcementFinished(_ note: Notification) {
        Task { @MainActor in
            guard self.announcementDeadline != nil else { return }
            self.announcementDeadline = nil
            self.finishedSpeaking()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in
            guard self.utteranceID == id else { return }
            self.utteranceID = nil
            self.finishedSpeaking()
        }
    }

    private func finishedSpeaking() {
        speakingKind = nil
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
            return DescribedWatchController(cues: cues, lines: AudioDescription.dialogueCues(video), player: player,
                                            arabic: arabic)
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

                    if controller.hasDialogue && controller.translating {
                        VStack(alignment: .leading, spacing: BasirSpacing.s) {
                            Text(l10n.t("الحوار الآن", "Dialogue now")).font(.headline).accessibilityAddTraits(.isHeader)
                            Text(controller.subtitle.isEmpty ? "…" : controller.subtitle)
                                .font(.title3.weight(.semibold))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .glassSurface()
                        .accessibilityElement(children: .combine)
                    }

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
                    CardActionButton(title: l10n.t("أعد آخر ما قيل", "Repeat the last line"), systemImage: "arrow.counterclockwise") { controller.repeatLast() }
                    Toggle(l10n.t("الوصف الصوتي", "Audio description"), isOn: $controller.describing)
                    Toggle(l10n.t("أوقف الفيديو عند كل وصف", "Pause the video for every description"), isOn: $controller.alwaysPause)
                    Text(l10n.t("عند إيقاف هذا الخيار، يستمر الفيديو بصوت منخفض أثناء الوصف.",
                                "With this off, the video keeps playing, turned down, while each description is said."))
                        .font(.footnote)
                        .foregroundStyle(BasirPalette.secondaryText)

                    VStack(alignment: .leading, spacing: BasirSpacing.m) {
                        SectionHeading(title: l10n.t("ترجمة الحوار الحية", "Live dialogue translation"))
                        if controller.hasDialogue {
                            Toggle(l10n.t("ترجمة الحوار", "Translate the dialogue"), isOn: $controller.translating)
                            Picker(l10n.t("صوت الفيديو أثناء الترجمة", "Video sound during a translation"),
                                   selection: $controller.dialogueMode) {
                                Text(l10n.t("منخفض", "Lower")).tag(DialogueVideoMode.lower)
                                Text(l10n.t("كامل", "Full")).tag(DialogueVideoMode.full)
                                Text(l10n.t("إيقاف مؤقت", "Pause")).tag(DialogueVideoMode.pause)
                            }
                            .pickerStyle(.segmented)
                            Toggle(l10n.t("القراءة بقارئ الشاشة", "Read with the screen reader"), isOn: $controller.useScreenReader)
                            Text(l10n.t("تُنطق ترجمة كل جملة لحظة قولها بصوت غير صوت الوصف، أو بقارئ الشاشة بصوته وسرعته، ويُقال الوصف في الفواصل بين الجمل.",
                                        "Each line's translation is said the moment it is spoken, in a voice other than the description's, or by the screen reader in its own voice and speed; descriptions fill the pauses between lines."))
                                .font(.footnote)
                                .foregroundStyle(BasirPalette.secondaryText)
                        } else {
                            Text(l10n.t("لم تُطلب ترجمة الحوار حين وُصف هذا الفيديو، أو ليس فيه حوار بلغة أخرى. لترجمته، صِفه مرة أخرى بعد تشغيل «ترجمة الحوار غير العربي» في شاشة وصف الفيديو.",
                                        "Translation wasn't asked for when this video was described, or it has no dialogue in another language. To translate it, describe it again with “Translate dialogue in other languages” turned on in the video description screen."))
                                .font(.footnote)
                                .foregroundStyle(BasirPalette.secondaryText)
                        }
                    }
                    .glassSurface()
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
