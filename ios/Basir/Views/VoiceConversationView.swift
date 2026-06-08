// VoiceConversationView.swift
// Continuous voice conversation. Equivalent to Android's
// showVoiceConversationScreen + the TTS-recognizer ping-pong loop.
//
// State machine
// ─────────────
//   .idle           initial, "Tap Start" CTA visible
//   .listening      microphone open, transcript building
//   .thinking       sent transcript to Gemini, awaiting response
//   .speaking       TTS playing the response
//   then auto-loops back to .listening after a 0.6s grace period
//
// Stop conditions
//   - User taps Stop → engine + recogniser both cancelled.
//   - User leaves screen → onDisappear cancels.
//   - Gemini errors → state goes to .error with friendly message;
//     auto-loop pauses so user can read what went wrong.

import SwiftUI
import Combine

struct VoiceConversationView: View {
    enum Phase: String { case idle, listening, thinking, speaking, error }

    @StateObject private var tts = SpeechSynthesizer.shared
    @StateObject private var asr = SpeechRecognizer.shared
    @State private var phase: Phase = .idle
    @State private var transcript: String = ""
    @State private var lastResponse: String = ""
    @State private var errorMessage: String?
    @State private var ttsSubscription: AnyCancellable?
    @State private var loopActive: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Status indicator
            HStack(spacing: 12) {
                Circle()
                    .fill(phaseColor)
                    .frame(width: 16, height: 16)
                    .scaleEffect(phase == .listening || phase == .speaking ? 1.4 : 1.0)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                                value: phase)
                Text(phaseLabel)
                    .font(.title3.bold())
                    .accessibilityAddTraits(.isHeader)
            }

            if !transcript.isEmpty {
                Text(L10n.t("سؤالك", "Your question"))
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                Text(transcript).textSelection(.enabled)
            }

            if !lastResponse.isEmpty {
                Divider()
                Text(L10n.t("الإجابة", "Answer"))
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                SelectableText(text: lastResponse)
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Spacer()

            if loopActive {
                Button(role: .destructive) {
                    stopLoop()
                } label: {
                    Text(L10n.t("إنهاء المحادثة", "End conversation"))
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    Task { await startLoop() }
                } label: {
                    Text(L10n.t("بدء محادثة صوتية", "Start voice conversation"))
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .navigationTitle(L10n.t("محادثة صوتية", "Voice conversation"))
        .onAppear {
            ttsSubscription = tts.didFinish.sink { _ in
                Task { @MainActor in
                    // TTS just finished playback. If the loop is still
                    // active, hand back to the microphone after a small
                    // gap so the recogniser doesn't catch our own audio.
                    if loopActive {
                        try? await Task.sleep(nanoseconds: 600_000_000)
                        guard loopActive else { return }
                        startListening()
                    }
                }
            }
        }
        .onDisappear {
            stopLoop()
        }
    }

    private var phaseColor: Color {
        switch phase {
        case .idle:      return .gray
        case .listening: return .green
        case .thinking:  return .orange
        case .speaking:  return .blue
        case .error:     return .red
        }
    }

    private var phaseLabel: String {
        switch phase {
        case .idle:      return L10n.t("مستعد للاستماع", "Ready to listen")
        case .listening: return L10n.t("أستمع الآن...", "Listening now...")
        case .thinking:  return L10n.t("أجهّز الإجابة...", "Preparing your answer...")
        case .speaking:  return L10n.t("أقرأ الإجابة...", "Reading the answer...")
        case .error:     return L10n.t("تعذّر المتابعة", "Unable to continue")
        }
    }

    // MARK: - Loop control

    private func startLoop() async {
        let auth = await asr.requestAuthorization()
        guard auth == .granted else {
            errorMessage = L10n.t(
                "فعّل إذنَي الميكروفون والتعرّف على الكلام من إعدادات iPhone لاستخدام المحادثة الصوتية.",
                "Enable Microphone and Speech Recognition in iPhone Settings to use voice conversation."
            )
            phase = .error
            return
        }
        loopActive = true
        errorMessage = nil
        startListening()
    }

    private func stopLoop() {
        loopActive = false
        asr.stop()
        tts.stop()
        phase = .idle
    }

    private func startListening() {
        guard loopActive else { return }
        transcript = ""
        phase = .listening
        let ok = asr.startDictation(language: BasirSettings.shared.language) { final in
            Task { await onTranscriptFinal(final) }
        }
        if !ok {
            errorMessage = L10n.t(
                "التعرّف على الكلام غير متاح على هذا الجهاز.",
                "Speech recognition is not available on this device."
            )
            phase = .error
        }
    }

    private func onTranscriptFinal(_ text: String) async {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            if loopActive { startListening() }
            return
        }
        transcript = q
        phase = .thinking

        do {
            let response = try await AiProviderFactory.current().ask(
                task: .ask,
                input: q,
                instruction: "Answer as Basir, screen-reader friendly and practical. Keep replies under 80 words for voice readability.",
                language: BasirSettings.shared.language,
                imageData: nil,
                mimeType: nil
            )
            lastResponse = response
            phase = .speaking
            tts.speak(response, utteranceId: "convo")
        } catch {
            errorMessage = UserFriendlyErrorMapper.map(error)
            phase = .error
            loopActive = false   // Pause the loop so the user can read it.
        }
    }
}
