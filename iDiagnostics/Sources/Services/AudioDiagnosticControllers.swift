import AVFoundation
import Combine
import Foundation

final class MicrophoneDiagnosticController: NSObject, ObservableObject {
    enum Phase: Equatable {
        case idle
        case requestingPermission
        case recording
        case playing
        case finished
        case failed
    }

    @Published private(set) var permission: MediaPermissionState = .undetermined
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var level: Float = 0
    @Published private(set) var errorMessage: String?

    private let recordingURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("idiagnostics-microphone.m4a")
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var meterTimer: Timer?
    private var interruptionObserver: NSObjectProtocol?

    override init() {
        super.init()
        refreshPermission()
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] _ in
            guard let self, self.phase == .recording || self.phase == .playing else { return }
            self.fail("قوطع فحص الصوت بمكالمة أو صوت من تطبيق آخر. أعد المحاولة.")
        }
    }

    deinit {
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        meterTimer?.invalidate()
        try? FileManager.default.removeItem(at: recordingURL)
    }

    func recordThenPlay() {
        guard phase != .recording, phase != .playing, phase != .requestingPermission else { return }
        errorMessage = nil
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            permission = .granted
            startRecording()
        case .denied:
            permission = .denied
            fail("إذن الميكروفون مرفوض. فعّله من إعدادات النظام.")
        case .undetermined:
            permission = .requesting
            phase = .requestingPermission
            requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.permission = granted ? .granted : .denied
                    if granted { self.startRecording() }
                    else { self.fail("لم يُمنح إذن الميكروفون.") }
                }
            }
        @unknown default:
            permission = .denied
            fail("تعذر تحديد إذن الميكروفون.")
        }
    }

    func cancel() {
        recorder?.stop()
        player?.stop()
        recorder = nil
        player = nil
        stopMetering()
        level = 0
        phase = .idle
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        try? FileManager.default.removeItem(at: recordingURL)
    }

    private func refreshPermission() {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted: permission = .granted
        case .denied: permission = .denied
        case .undetermined: permission = .undetermined
        @unknown default: permission = .denied
        }
    }

    private func requestRecordPermission(_ completion: @escaping (Bool) -> Void) {
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission(completionHandler: completion)
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission(completion)
        }
    }

    private func startRecording() {
        do {
            try? FileManager.default.removeItem(at: recordingURL)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
            try session.setActive(true)

            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let recorder = try AVAudioRecorder(url: recordingURL, settings: settings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            guard recorder.prepareToRecord(), recorder.record(forDuration: 4) else {
                throw AudioDiagnosticError.cannotStartRecording
            }
            self.recorder = recorder
            phase = .recording
            startMetering()
            AccessibilityAnnouncer.post("بدأ تسجيل أربع ثوانٍ")
        } catch {
            fail("تعذر بدء التسجيل: \(error.localizedDescription)")
        }
    }

    private func startPlayback() {
        do {
            stopMetering()
            level = 0
            let player = try AVAudioPlayer(contentsOf: recordingURL)
            player.delegate = self
            player.volume = 1
            guard player.prepareToPlay(), player.play() else {
                throw AudioDiagnosticError.cannotStartPlayback
            }
            self.player = player
            phase = .playing
            AccessibilityAnnouncer.post("بدأ تشغيل التسجيل")
        } catch {
            fail("تم التسجيل لكن تعذر تشغيله: \(error.localizedDescription)")
        }
    }

    private func startMetering() {
        stopMetering()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            guard let self, let recorder = self.recorder else { return }
            recorder.updateMeters()
            let decibels = recorder.averagePower(forChannel: 0)
            self.level = max(0, min(1, (decibels + 60) / 60))
        }
    }

    private func stopMetering() {
        meterTimer?.invalidate()
        meterTimer = nil
    }

    private func fail(_ message: String) {
        recorder?.stop()
        player?.stop()
        recorder = nil
        player = nil
        stopMetering()
        phase = .failed
        errorMessage = message
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        try? FileManager.default.removeItem(at: recordingURL)
        AppLog.media.error("Microphone diagnostic: \(message, privacy: .public)")
    }
}

extension MicrophoneDiagnosticController: AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.recorder = nil
            if flag { self.startPlayback() }
            else { self.fail("توقف التسجيل قبل اكتماله.") }
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.player = nil
            try? FileManager.default.removeItem(at: self.recordingURL)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            if flag {
                self.phase = .finished
                AccessibilityAnnouncer.post("اكتمل فحص الميكروفون")
            } else {
                self.fail("توقف تشغيل العينة قبل اكتمالها.")
            }
        }
    }
}

final class SpeakerDiagnosticController: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var errorMessage: String?

    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private var stopWorkItem: DispatchWorkItem?

    func play() {
        stop()
        errorMessage = nil
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)

            guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1),
                  let buffer = Self.makeTone(format: format, duration: 2.5) else {
                throw AudioDiagnosticError.cannotCreateTone
            }

            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            engine.mainMixerNode.outputVolume = 0.25
            try engine.start()
            node.scheduleBuffer(buffer, at: nil, options: [])
            node.play()
            isPlaying = true

            let work = DispatchWorkItem { [weak self] in self?.stop() }
            stopWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.6, execute: work)
            AccessibilityAnnouncer.post("بدأت نغمة اختبار آمنة لمدة ثانيتين ونصف")
        } catch {
            stop()
            errorMessage = "تعذر تشغيل النغمة: \(error.localizedDescription)"
        }
    }

    func stop() {
        stopWorkItem?.cancel()
        stopWorkItem = nil
        node.stop()
        engine.stop()
        engine.reset()
        if engine.attachedNodes.contains(node) { engine.detach(node) }
        isPlaying = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private static func makeTone(format: AVAudioFormat, duration: TimeInterval) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(format.sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        for frame in 0..<Int(frames) {
            let time = Double(frame) / format.sampleRate
            let envelope = min(1, time / 0.05, (duration - time) / 0.05)
            channel[frame] = Float(sin(2 * Double.pi * 660 * time) * 0.35 * max(0, envelope))
        }
        return buffer
    }
}

enum AudioDiagnosticError: LocalizedError {
    case cannotStartRecording
    case cannotStartPlayback
    case cannotCreateTone

    var errorDescription: String? {
        switch self {
        case .cannotStartRecording: return "لم يقبل النظام بدء التسجيل."
        case .cannotStartPlayback: return "لم يقبل النظام بدء التشغيل."
        case .cannotCreateTone: return "تعذر إنشاء نغمة الاختبار."
        }
    }
}
