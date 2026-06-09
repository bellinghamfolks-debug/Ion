import AVFoundation
import Speech
import Combine

@MainActor
final class SpeechService: ObservableObject {
    enum State: Equatable {
        case idle
        case requestingPermission
        case listening
        case processing
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var transcript = ""
    @Published private(set) var segments: [SpeechSegmentSnapshot] = []
    @Published private(set) var elapsedTime: TimeInterval = 0
    @Published private(set) var activeLocaleIdentifier = "en-US"

    private var recognizer: SFSpeechRecognizer?
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var startedAt: Date?

    func requestPermissions() async -> Bool {
        state = .requestingPermission
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        let microphone = await MicrophonePermission.request()
        let granted = speech == .authorized && microphone
        state = granted ? .idle : .failed("يلزم السماح بالميكروفون والتعرف على الكلام.")
        return granted
    }

    func start(localeIdentifier: String = "en-US") async {
        guard await requestPermissions() else { return }
        stop()
        transcript = ""
        segments = []
        elapsedTime = 0
        activeLocaleIdentifier = localeIdentifier
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))

        guard recognizer?.isAvailable == true else {
            state = .failed("التعرف على الكلام غير متاح حاليًا لهذه اللكنة.")
            return
        }

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers, .allowBluetooth])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            if #available(iOS 16.0, *) {
                request.addsPunctuation = true
            }
            self.request = request
            let node = engine.inputNode
            let format = node.outputFormat(forBus: 0)
            node.removeTap(onBus: 0)
            node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            engine.prepare()
            try engine.start()
            startedAt = .now
            state = .listening
            task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                        self.segments = result.bestTranscription.segments.map {
                            SpeechSegmentSnapshot(
                                text: $0.substring,
                                timestamp: $0.timestamp,
                                duration: $0.duration,
                                confidence: $0.confidence
                            )
                        }
                    }
                    if error != nil || result?.isFinal == true {
                        self.finishRecognition()
                    }
                }
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func stop() {
        finishRecognition()
    }

    func resetTranscript() {
        transcript = ""
        segments = []
        elapsedTime = 0
    }

    private func finishRecognition() {
        if let startedAt {
            elapsedTime = max(elapsedTime, Date().timeIntervalSince(startedAt))
        }
        startedAt = nil
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if case .failed = state {} else { state = .idle }
    }
}

private enum MicrophonePermission {
    static func request() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }
    }
}
