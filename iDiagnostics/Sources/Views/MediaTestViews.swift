import SwiftUI

struct CameraTestView: View {
    @EnvironmentObject private var store: DiagnosticsStore
    @StateObject private var camera = CameraDiagnosticController()
    @State private var inspectedSides = Set<CameraSide>()
    @State private var testedTorch = false
    @State private var startedAt = Date()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if camera.permission == .denied {
                    PermissionHelpCard(message: "فعّل إذن الكاميرا لإجراء المعاينة. لا يحفظ التطبيق أي صورة.")
                } else {
                    ZStack {
                        CameraPreview(session: camera.session)
                            .frame(height: 340)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.radius))
                            .accessibilityHidden(true)
                        if !camera.isRunning {
                            ProgressView(camera.permission == .requesting ? "بانتظار الإذن…" : "جارٍ تشغيل الكاميرا…")
                                .padding()
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("معاينة الكاميرا \(camera.side.titleAr)، \(camera.isRunning ? "تعمل" : "غير جاهزة")")

                    HStack(spacing: 10) {
                        Button {
                            inspectedSides.insert(camera.side)
                            camera.switchCamera()
                        } label: {
                            Label("تبديل الكاميرا", systemImage: "arrow.triangle.2.circlepath.camera")
                                .frame(maxWidth: .infinity, minHeight: 30)
                        }
                        .buttonStyle(.borderedProminent)

                        if camera.hasTorch {
                            Button {
                                testedTorch = true
                                camera.setTorch(!camera.torchOn)
                            } label: {
                                Label(camera.torchOn ? "إطفاء الفلاش" : "تشغيل الفلاش", systemImage: camera.torchOn ? "flashlight.off.fill" : "flashlight.on.fill")
                                    .frame(maxWidth: .infinity, minHeight: 30)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .controlSize(.large)
                }

                if let error = camera.errorMessage {
                    Text(error).foregroundStyle(.red).accessibilityLabel("خطأ: \(error)")
                }

                DiagnosticCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("بعد مشاهدة الصورتين").font(.headline)
                        Text("بدّل بين الأمامية والخلفية، وجرّب الفلاش إن كان متاحًا، ثم احفظ النتيجة.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        ResultControls(
                            onPass: { save(.pass) },
                            onWarning: { save(.warning) },
                            onFail: { save(.fail) }
                        )
                    }
                }
                TestDisclaimer()
            }
            .padding(AppTheme.screenPadding)
        }
        .navigationTitle(TestCategory.camera.titleAr)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            startedAt = Date()
            camera.requestAccessAndStart()
        }
        .onDisappear { camera.stop() }
    }

    private func save(_ outcome: TestOutcome) {
        inspectedSides.insert(camera.side)
        store.record(
            category: .camera,
            outcome: outcome,
            summary: outcome == .pass ? "أكد المستخدم وضوح الكاميرات والفلاش المتاح." : "أبلغ المستخدم عن مشكلة أو لم يؤكد جميع عناصر الكاميرا.",
            metrics: [
                .init(label: "الكاميرات التي عوينت", value: inspectedSides.map(\.titleAr).sorted().joined(separator: "، ")),
                .init(label: "وجود فلاش", value: camera.hasTorch ? "نعم" : "غير متاح في الكاميرا الحالية"),
                .init(label: "جُرّب الفلاش", value: testedTorch ? "نعم" : "لا")
            ],
            evidence: .mixed,
            limitation: "المعاينة لا تقيس التركيز أو جودة الحساس مخبريًا، ولا تُحفظ صور.",
            startedAt: startedAt
        )
    }
}

struct MicrophoneTestView: View {
    @EnvironmentObject private var store: DiagnosticsStore
    @StateObject private var microphone = MicrophoneDiagnosticController()
    @State private var startedAt = Date()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if microphone.permission == .denied {
                    PermissionHelpCard(message: "فعّل إذن الميكروفون. تُحذف العينة فور انتهاء تشغيلها.")
                } else {
                    DiagnosticCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("تسجيل وتشغيل محلي", systemImage: "waveform.and.mic")
                                .font(.headline)
                            Text("اضغط بدء الفحص، ثم تحدث أربع ثوانٍ. سيشغّل التطبيق العينة تلقائيًا ويحذف الملف بعدها.")
                            if microphone.phase == .recording {
                                ProgressView(value: Double(microphone.level))
                                    .accessibilityLabel("مستوى الصوت أثناء التسجيل")
                                    .accessibilityValue("\(Int(microphone.level * 100)) بالمئة")
                            }
                        }
                    }

                    PrimaryActionButton(
                        title: microphoneButtonTitle,
                        systemImage: microphone.phase == .playing ? "speaker.wave.2.fill" : "mic.fill",
                        disabled: microphone.phase == .recording || microphone.phase == .playing || microphone.phase == .requestingPermission
                    ) {
                        startedAt = Date()
                        microphone.recordThenPlay()
                    }
                }

                if let error = microphone.errorMessage {
                    Text(error).foregroundStyle(.red).accessibilityLabel("خطأ: \(error)")
                }

                if microphone.phase == .finished {
                    DiagnosticCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("هل سمعت صوتك بوضوح؟").font(.headline)
                            ResultControls(
                                onPass: { save(.pass) },
                                onWarning: { save(.warning) },
                                onFail: { save(.fail) }
                            )
                        }
                    }
                }
                TestDisclaimer()
            }
            .padding(AppTheme.screenPadding)
        }
        .navigationTitle(TestCategory.microphone.titleAr)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { microphone.cancel() }
    }

    private var microphoneButtonTitle: String {
        switch microphone.phase {
        case .idle, .failed: return "بدء فحص الميكروفون"
        case .requestingPermission: return "بانتظار الإذن…"
        case .recording: return "جارٍ التسجيل…"
        case .playing: return "جارٍ تشغيل العينة…"
        case .finished: return "إعادة الفحص"
        }
    }

    private func save(_ outcome: TestOutcome) {
        store.record(
            category: .microphone,
            outcome: outcome,
            summary: outcome == .pass ? "اكتمل التسجيل والتشغيل وأكد المستخدم وضوح العينة." : "اكتمل المسار لكن المستخدم لاحظ مشكلة أو لم يتأكد من الوضوح.",
            metrics: [
                .init(label: "مدة العينة", value: "4 ثوانٍ"),
                .init(label: "التخزين", value: "مؤقت ومحلي؛ حُذف بعد التشغيل")
            ],
            evidence: .mixed,
            limitation: "يختار iOS مسار الميكروفون ولا يتيح عزل كل ميكروفون مادي على حدة.",
            startedAt: startedAt
        )
    }
}

struct SpeakerTestView: View {
    @EnvironmentObject private var store: DiagnosticsStore
    @StateObject private var speaker = SpeakerDiagnosticController()
    @State private var playedTone = false
    @State private var startedAt = Date()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                DiagnosticCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("نغمة اختبار آمنة", systemImage: "speaker.wave.3.fill")
                            .font(.headline)
                        Text("افصل سماعات Bluetooth إن أردت اختبار مكبر الهاتف نفسه، وارفع مستوى الصوت إلى درجة مريحة.")
                        Text("النغمة مدتها ثانيتان ونصف وبمستوى داخلي منخفض لتجنب الإزعاج.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                PrimaryActionButton(
                    title: speaker.isPlaying ? "إيقاف النغمة" : "تشغيل النغمة",
                    systemImage: speaker.isPlaying ? "stop.fill" : "play.fill"
                ) {
                    if speaker.isPlaying { speaker.stop() }
                    else {
                        startedAt = Date()
                        playedTone = true
                        speaker.play()
                    }
                }

                if let error = speaker.errorMessage {
                    Text(error).foregroundStyle(.red)
                }

                if playedTone {
                    DiagnosticCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("هل كان الصوت واضحًا بلا تشويش؟").font(.headline)
                            ResultControls(
                                onPass: { save(.pass) },
                                onWarning: { save(.warning) },
                                onFail: { save(.fail) }
                            )
                        }
                    }
                }
                TestDisclaimer()
            }
            .padding(AppTheme.screenPadding)
        }
        .navigationTitle(TestCategory.speaker.titleAr)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { speaker.stop() }
    }

    private func save(_ outcome: TestOutcome) {
        store.record(
            category: .speaker,
            outcome: outcome,
            summary: outcome == .pass ? "أكد المستخدم وضوح نغمة الاختبار." : "أبلغ المستخدم عن تشويش أو مشكلة في سماع النغمة.",
            metrics: [
                .init(label: "التردد", value: "660 هرتز"),
                .init(label: "المدة", value: "2.5 ثانية")
            ],
            evidence: .userConfirmed,
            limitation: "قد يوجه iOS الصوت إلى سماعة خارجية؛ لا يمكن فصل كل مكبر داخلي عبر واجهة عامة.",
            startedAt: startedAt
        )
    }
}
