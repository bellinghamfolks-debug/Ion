// SpeechRecognizer.swift
// SFSpeechRecognizer wrapper. Equivalent to Android's VoiceController.
//
// Responsibilities
// ────────────────
//   - Request the two iOS permissions needed for live dictation:
//       1. NSSpeechRecognitionUsageDescription   (Apple's speech API)
//       2. NSMicrophoneUsageDescription          (audio capture)
//   - Run a single-shot dictation session: open mic, recognise, stop
//     after the user pauses, return final text.
//   - Coexist with SpeechSynthesizer: when TTS is mid-speech we hold
//     off opening the mic so the recogniser doesn't try to transcribe
//     our own voice.
//
// What it deliberately does NOT do
//   - Continuous dictation (background streaming). For the voice
//     conversation mode we wrap this in a loop driven by the TTS
//     "did finish" signal, not by holding the mic open indefinitely.

import Foundation
import Speech
import AVFoundation

@MainActor
final class SpeechRecognizer: ObservableObject {
    static let shared = SpeechRecognizer()

    enum AuthorizationState { case undetermined, denied, granted, restricted }

    @Published private(set) var isRecording: Bool = false
    @Published private(set) var transcript: String = ""
    @Published private(set) var authorization: AuthorizationState = .undetermined

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    /// Fires after a pause in speech to finalize one-shot dictation,
    /// because a live mic never produces result.isFinal on its own.
    private var silenceWork: DispatchWorkItem?
    private var finalized = false
    private var tapInstalled = false
    private var activeSessionID: UUID?

    private init() {}

    /// Asks the user for both microphone and speech-recognition
    /// permission. Call once when entering any voice screen.
    func requestAuthorization() async -> AuthorizationState {
        // 1) Speech-recognition authorisation
        let speechStatus = await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else {
            authorization = .denied
            return .denied
        }

        // 2) Microphone authorisation
        let micGranted = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
        authorization = micGranted ? .granted : .denied
        return authorization
    }

    /// Start a one-shot dictation. The callback fires once with the
    /// final recognised text when the user pauses (or when stop() is
    /// called manually). Returns false if recognition is unavailable
    /// (no Google-style fallback on iOS — SFSpeechRecognizer is the
    /// only option Apple ships).
    @discardableResult
    func startDictation(language: AppLanguage,
                         onFinal: @escaping (String) -> Void) -> Bool {
        // Initialise recogniser for the right locale.
        let locale = language == .arabic
            ? Locale(identifier: "ar-SA")
            : Locale(identifier: "en-US")
        recognizer = SFSpeechRecognizer(locale: locale)
        guard let recognizer, recognizer.isAvailable else {
            return false
        }

        // Tear down any previous session.
        stop()
        transcript = ""
        finalized = false
        let sessionID = UUID()
        activeSessionID = sessionID

        do {
            // Audio session configured for recording while TTS may
            // still be active in the background. .duckOthers means
            // Apple Music will quiet down for us.
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord,
                                     mode: .measurement,
                                     options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            recognitionRequest = request

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            tapInstalled = true

            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true

            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self else { return }
                Task { @MainActor in
                    guard self.activeSessionID == sessionID else { return }
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                        // A live mic rarely sets isFinal, so arm a silence
                        // timer that finalizes ~1.8s after the last words.
                        self.armSilenceTimer(sessionID: sessionID, onFinal: onFinal)
                        if result.isFinal {
                            self.finishOnce(sessionID: sessionID, onFinal)
                        }
                    }
                    if error != nil {
                        self.finishOnce(sessionID: sessionID, onFinal)
                    }
                }
            }
            return true
        } catch {
            stop()
            return false
        }
    }

    /// Restart the silence countdown; if no new speech arrives within the
    /// window, deliver whatever has been transcribed so far.
    private func armSilenceTimer(sessionID: UUID, onFinal: @escaping (String) -> Void) {
        silenceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.activeSessionID == sessionID, !self.transcript.isEmpty else { return }
            self.finishOnce(sessionID: sessionID, onFinal)
        }
        silenceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
    }

    /// Deliver the result exactly once, then tear down.
    private func finishOnce(sessionID: UUID, _ onFinal: @escaping (String) -> Void) {
        guard activeSessionID == sessionID, !finalized else { return }
        finalized = true
        let text = transcript
        stop()
        if !text.isEmpty { onFinal(text) }
    }

    func stop() {
        silenceWork?.cancel()
        silenceWork = nil
        recognitionTask?.cancel()
        recognitionTask = nil

        activeSessionID = nil
        finalized = true
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }

        recognitionRequest?.endAudio()
        recognitionRequest = nil
        isRecording = false

        try? AVAudioSession.sharedInstance().setActive(false,
                                                       options: .notifyOthersOnDeactivation)
    }
}
