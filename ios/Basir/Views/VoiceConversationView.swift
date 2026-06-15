import SwiftUI
import Combine

struct VoiceConversationView: View {
    enum Phase: String { case idle, listening, thinking, speaking, error }

    @StateObject private var tts = SpeechSynthesizer.shared
    @StateObject private var asr = SpeechRecognizer.shared
    @State private var phase: Phase = .idle
    @State private var transcript = ""
    @State private var lastResponse = ""
    @State private var errorMessage: String?
    @State private var ttsSubscription: AnyCancellable?
    @State private var loopActive = false
    @State private var isStarting = false
    @State private var responseTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        BasirScreen {
            BasirPageIntro(
                text: L10n.t(
                    "اضغط بدء ثم تحدث بعد سماع إشارة الاستماع. بعد قراءة الإجابة سيفتح الميكروفون تلقائيًا للسؤال التالي.",
                    "Tap Start, then speak when listening begins. After the answer is read aloud, the microphone opens automatically for your next question."
                )
            )

            phaseCard

            if !transcript.isEmpty {
                BasirInfoRow(label: L10n.t("آخر سؤال سُمع", "Last question heard"),
                             value: transcript,
                             systemImage: "quote.bubble.fill")
            }

            if !lastResponse.isEmpty {
                BasirResultCard(title: L10n.t("آخر إجابة", "Last answer"), text: lastResponse) {
                    CopyButton(text: lastResponse)
                }
            }

            if let errorMessage {
                BasirStatusBanner(text: errorMessage, tone: .danger)
            }

            if loopActive {
                Button(role: .destructive) { stopLoop() } label: {
                    Label(L10n.t("إنهاء المحادثة", "End conversation"),
                          systemImage: "stop.circle.fill")
                }
                .buttonStyle(BasirPrimaryButtonStyle(tone: .danger))
            } else {
                Button { Task { await startLoop() } } label: {
                    Label(L10n.t("بدء المحادثة الصوتية", "Start voice conversation"),
                          systemImage: "waveform.and.mic")
                }
                .buttonStyle(BasirPrimaryButtonStyle())
                .disabled(isStarting)
            }

            BasirStatusBanner(
                text: L10n.t(
                    "يمكنك إنهاء المحادثة في أي وقت. لا يُحفظ التسجيل الصوتي داخل بصير؛ يتحول الكلام إلى نص لإرسال السؤال.",
                    "You can end the conversation at any time. Basir does not save the audio recording; speech is converted to text for the question."
                ),
                tone: .neutral
            )
        }
        .navigationTitle(L10n.t("محادثة صوتية", "Voice conversation"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            ttsSubscription = tts.didFinish.sink { _ in
                Task { @MainActor in
                    if loopActive {
                        try? await Task.sleep(nanoseconds: 600_000_000)
                        guard loopActive else { return }
                        startListening()
                    }
                }
            }
        }
        .onDisappear { stopLoop() }
    }

    private var phaseCard: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(phaseColor.opacity(0.14)).frame(width: 62, height: 62)
                Image(systemName: phaseIcon)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(phaseColor)
                    .scaleEffect(!reduceMotion && (phase == .listening || phase == .speaking) ? 1.12 : 1)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: phase)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.t("حالة المحادثة", "Conversation status"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(phaseLabel)
                    .font(.title3.bold())
                    .foregroundStyle(phaseColor)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            Spacer()
        }
        .basirCardSurface()
        .accessibilityElement(children: .combine)
    }

    private var phaseColor: Color {
        switch phase {
        case .idle: return .secondary
        case .listening: return .green
        case .thinking: return .orange
        case .speaking: return .blue
        case .error: return .red
        }
    }

    private var phaseIcon: String {
        switch phase {
        case .idle: return "mic.circle.fill"
        case .listening: return "ear.fill"
        case .thinking: return "ellipsis.bubble.fill"
        case .speaking: return "speaker.wave.3.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private var phaseLabel: String {
        switch phase {
        case .idle: return L10n.t("جاهز للبدء", "Ready to start")
        case .listening: return L10n.t("أستمع الآن", "Listening now")
        case .thinking: return L10n.t("جاري إعداد الإجابة", "Preparing the answer")
        case .speaking: return L10n.t("جاري قراءة الإجابة", "Reading the answer")
        case .error: return L10n.t("توقفت المحادثة", "Conversation stopped")
        }
    }

    private func startLoop() async {
        guard !loopActive, !isStarting else { return }
        guard BasirSettings.shared.speechEnabled else {
            errorMessage = L10n.t(
                "فعّل القراءة الصوتية من الإعدادات قبل بدء المحادثة الصوتية.",
                "Enable spoken output in Settings before starting a voice conversation."
            )
            phase = .error
            return
        }
        isStarting = true
        defer { isStarting = false }
        let auth = await asr.requestAuthorization()
        guard auth == .granted else {
            errorMessage = L10n.t(
                "اسمح لبصير باستخدام الميكروفون والتعرّف على الكلام من إعدادات iPhone، ثم أعد المحاولة.",
                "Allow Basir to use the microphone and Speech Recognition in iPhone Settings, then try again."
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
        responseTask?.cancel()
        responseTask = nil
        phase = .idle
    }

    private func startListening() {
        guard loopActive else { return }
        transcript = ""
        phase = .listening
        let ok = asr.startDictation(language: BasirSettings.shared.language) { final in
            Task { @MainActor in
                responseTask?.cancel()
                responseTask = Task { await onTranscriptFinal(final) }
            }
        }
        if !ok {
            errorMessage = L10n.t("التعرّف على الكلام غير متاح على هذا الجهاز.",
                                  "Speech recognition is not available on this device.")
            phase = .error
            loopActive = false
        }
    }

    private func onTranscriptFinal(_ text: String) async {
        guard loopActive, !Task.isCancelled else { return }
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            if loopActive { startListening() }
            return
        }
        transcript = q
        phase = .thinking

        do {
            let response = try await AiProviderFactory.current().ask(
                task: .voiceConversation,
                input: q,
                instruction: GeminiPrompts.voiceAnswerInstruction,
                language: BasirSettings.shared.language,
                imageData: nil,
                mimeType: nil
            )
            guard loopActive, !Task.isCancelled else { return }
            lastResponse = response
            phase = .speaking
            guard tts.speak(response, utteranceId: "convo") else {
                errorMessage = L10n.t(
                    "توقفت القراءة الصوتية من الإعدادات؛ أُنهِيت المحادثة بأمان.",
                    "Spoken output was disabled in Settings, so the conversation ended safely."
                )
                phase = .error
                loopActive = false
                return
            }
        } catch {
            if Task.isCancelled || !loopActive { return }
            errorMessage = UserFriendlyErrorMapper.map(error)
            phase = .error
            loopActive = false
        }
    }
}
