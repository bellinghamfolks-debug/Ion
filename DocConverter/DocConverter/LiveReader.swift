import SwiftUI
import AVFoundation
import ReplayKit

// MARK: - Live Reader for the eSight Go glasses
//
// Flow: the user opens the eSight Companion app (showing the glasses camera),
// starts a system screen broadcast and picks OUR broadcast extension. The
// extension OCRs frames on the server and hands text here via the shared App
// Group + a Darwin notification; this model speaks it aloud in Arabic/English.
// A background audio session keeps us alive to speak while the user is in the
// eSight app.

@MainActor
@Observable
final class LiveReaderModel {
    static let appGroup = "group.com.bellinghamfolks.docconverter"
    static let darwinName = "com.bellinghamfolks.docconverter.livetext"

    var running = false
    var lastText = ""
    var model = "gemini-3.6-flash"

    private let synth = AVSpeechSynthesizer()
    private var lastSpokenNorm = ""

    func start() {
        // Background playback so speech continues while the user is in eSight.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)

        UserDefaults(suiteName: Self.appGroup)?.set(model, forKey: "live.model")

        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterAddObserver(
            center, Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                let me = Unmanaged<LiveReaderModel>.fromOpaque(observer).takeUnretainedValue()
                Task { @MainActor in me.pickup() }
            },
            Self.darwinName as CFString, nil, .deliverImmediately)
        running = true
    }

    func stop() {
        CFNotificationCenterRemoveEveryObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque())
        synth.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setActive(false)
        running = false
    }

    /// New text arrived from the extension: read it automatically. Skips
    /// near-duplicates (same normalised text, or one contained in the other) so
    /// panning the glasses over the same text doesn't re-read it.
    func pickup() {
        guard let d = UserDefaults(suiteName: Self.appGroup),
              let text = d.string(forKey: "live.text") else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let norm = normalize(trimmed)
        guard norm.count >= 2 else { return }
        if norm == lastSpokenNorm
            || (lastSpokenNorm.count >= 8 && (lastSpokenNorm.contains(norm) || norm.contains(lastSpokenNorm))) {
            return
        }
        lastSpokenNorm = norm
        lastText = trimmed
        speak(trimmed)
    }

    /// Normalise for duplicate detection: collapse whitespace, drop Arabic
    /// diacritics/tatweel, lowercase.
    private func normalize(_ s: String) -> String {
        let stripped = s.unicodeScalars.filter { sc in
            !(0x064B...0x0652).contains(sc.value) && sc.value != 0x0640
        }
        return String(String.UnicodeScalarView(stripped))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    func speak(_ text: String) {
        let isArabic = text.range(of: "\\p{Arabic}", options: .regularExpression) != nil
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: isArabic ? "ar-SA" : "en-US")
        u.rate = AVSpeechUtteranceDefaultSpeechRate
        synth.speak(u)
    }

    func setModel(_ m: String) {
        model = m
        UserDefaults(suiteName: Self.appGroup)?.set(m, forKey: "live.model")
    }
}

struct LiveReaderView: View {
    @State private var model = LiveReaderModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("يقرأ هذا الوضع النصّ الظاهر من كاميرا نظارة eSight بصوت عربي/إنجليزي.")
                        .font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    stepsCard

                    if model.running {
                        Label("الاستماع فعّال — سيُقرأ النص تلقائيًا", systemImage: "waveform")
                            .foregroundStyle(.green).font(.headline)
                        if !model.lastText.isEmpty {
                            Text(model.lastText)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }

                    // 1) Activate audio/listening.
                    if model.running {
                        bigButton("إيقاف القراءة", icon: "stop.circle", color: .red) { model.stop() }
                    } else {
                        bigButton("تفعيل القراءة الصوتية", icon: "speaker.wave.2", color: .green) { model.start() }
                    }

                    // 2) The system broadcast picker (start sharing the screen to our extension).
                    VStack(spacing: 6) {
                        Text("ابدأ بثّ الشاشة").font(.headline)
                        BroadcastPicker()
                            .frame(width: 220, height: 70)
                    }
                }
                .padding()
            }
            .navigationTitle("القارئ اللحظي للنظارة")
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("تم") { model.stop(); dismiss() } } }
        }
        .onDisappear { model.stop() }
    }

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("الخطوات:").font(.headline)
            Text("١) اضغط «تفعيل القراءة الصوتية».").font(.callout)
            Text("٢) اضغط زر البثّ بالأسفل واختر «محول المستندات».").font(.callout)
            Text("٣) افتح تطبيق eSight ووجّه النظارة نحو النص — سيُقرأ لك تلقائيًا.").font(.callout)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func bigButton(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack { Image(systemName: icon); Text(title) }
                .frame(maxWidth: .infinity).padding()
                .background(color).foregroundStyle(.white).font(.title2)
                .clipShape(RoundedRectangle(cornerRadius: 15))
        }
        .accessibilityLabel(title)
    }
}

/// Wraps RPSystemBroadcastPickerView so the user can start a screen broadcast
/// pre-targeting our broadcast extension.
struct BroadcastPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let v = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 220, height: 70))
        v.preferredExtension = "com.bellinghamfolks.docconverter.broadcast"
        v.showsMicrophoneButton = false
        return v
    }
    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}
