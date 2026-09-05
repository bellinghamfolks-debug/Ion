import SwiftUI

struct HapticsTestView: View {
    @EnvironmentObject private var store: DiagnosticsStore
    @StateObject private var haptics = HapticDiagnosticController()
    @State private var playedPatterns = Set<String>()
    @State private var startedAt = Date()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                DiagnosticCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("اختبر ثلاثة أنماط", systemImage: "iphone.radiowaves.left.and.right")
                            .font(.headline)
                        Text("أمسك الهاتف بيدك، ثم شغّل كل نمط مرة واحدة على الأقل.")
                        Text(haptics.supportsHaptics ? "يدعم الجهاز Core Haptics." : "سيستخدم التطبيق اهتزاز النظام البديل.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                DiagnosticCard {
                    VStack(spacing: 10) {
                        patternButton("خفيف", intensity: 0.35, sharpness: 0.25)
                        patternButton("متوسط", intensity: 0.7, sharpness: 0.5)
                        patternButton("قوي مزدوج", intensity: 1, sharpness: 0.8, doublePulse: true)
                    }
                }

                if let error = haptics.errorMessage {
                    Text(error).foregroundStyle(.red)
                }

                DiagnosticCard {
                    VStack(alignment: .leading, spacing: 12) {
                        MetricRow(metric: .init(label: "الأنماط المشغلة", value: "\(playedPatterns.count) من 3"))
                        ResultControls(
                            onPass: { save(playedPatterns.count == 3 ? .pass : .warning) },
                            onWarning: { save(.warning) },
                            onFail: { save(.fail) }
                        )
                    }
                }
                TestDisclaimer()
            }
            .padding(AppTheme.screenPadding)
        }
        .navigationTitle(TestCategory.haptics.titleAr)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            startedAt = Date()
            haptics.prepare()
        }
        .onDisappear { haptics.stop() }
    }

    private func patternButton(_ title: String, intensity: Float, sharpness: Float, doublePulse: Bool = false) -> some View {
        Button {
            playedPatterns.insert(title)
            haptics.play(intensity: intensity, sharpness: sharpness, doublePulse: doublePulse)
        } label: {
            HStack {
                Label("تشغيل اهتزاز \(title)", systemImage: "wave.3.right")
                Spacer()
                if playedPatterns.contains(title) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel("تم تشغيله")
                }
            }
            .frame(maxWidth: .infinity, minHeight: 30)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    private func save(_ outcome: TestOutcome) {
        store.record(
            category: .haptics,
            outcome: outcome,
            summary: outcome == .pass ? "شغّل المستخدم الأنماط الثلاثة وأكد الشعور بها." : "لم يكتمل تشغيل الأنماط أو أبلغ المستخدم عن مشكلة.",
            metrics: [
                .init(label: "دعم Core Haptics", value: haptics.supportsHaptics ? "نعم" : "لا"),
                .init(label: "الأنماط المشغلة", value: "\(playedPatterns.count) من 3")
            ],
            evidence: .mixed,
            limitation: "قوة الاهتزاز يقيّمها المستخدم ولا يتيح iOS حساسًا لقياسها.",
            startedAt: startedAt
        )
    }
}

struct ButtonsTestView: View {
    @EnvironmentObject private var store: DiagnosticsStore
    @StateObject private var volume = VolumeButtonMonitor()
    @State private var sideButtonConfirmed = false
    @State private var actionOrMuteConfirmed = false
    @State private var startedAt = Date()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                DiagnosticCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("أزرار الصوت", systemImage: "speaker.plus.fill")
                            .font(.headline)
                        Text("اضغط رفع الصوت مرة وخفض الصوت مرة. إذا كان المستوى عند الحد الأعلى أو الأدنى، حرّكه أولًا بعيدًا عن الحد.")
                        MetricRow(metric: .init(label: "رفع الصوت", value: volume.upCount > 0 ? "رُصد" : "لم يُرصد"))
                        MetricRow(metric: .init(label: "خفض الصوت", value: volume.downCount > 0 ? "رُصد" : "لم يُرصد"))
                        Button("إعادة عدّ أزرار الصوت") { volume.resetCounts() }
                            .buttonStyle(.bordered)
                    }
                }

                DiagnosticCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("الأزرار التي لا يتيح iOS التقاطها").font(.headline)
                        Toggle("زر الجانب يقفل ويفتح الشاشة", isOn: $sideButtonConfirmed)
                        Toggle("زر الإجراءات أو مفتاح الصامت يستجيب", isOn: $actionOrMuteConfirmed)
                        Text("هذه تأكيدات يدوية لأن النظام لا يرسل ضغطاتها إلى تطبيقات الطرف الثالث.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = volume.errorMessage {
                    Text(error).foregroundStyle(.red)
                }

                DiagnosticCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("حفظ النتيجة").font(.headline)
                        ResultControls(
                            onPass: { save(volume.bothDetected && sideButtonConfirmed ? .pass : .warning) },
                            onWarning: { save(.warning) },
                            onFail: { save(.fail) }
                        )
                    }
                }
                TestDisclaimer()
            }
            .padding(AppTheme.screenPadding)
        }
        .navigationTitle(TestCategory.buttons.titleAr)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            startedAt = Date()
            volume.start()
        }
        .onDisappear { volume.stop() }
    }

    private func save(_ outcome: TestOutcome) {
        store.record(
            category: .buttons,
            outcome: outcome,
            summary: outcome == .pass ? "رُصد زرا الصوت وأكد المستخدم بقية الأزرار." : "لم يكتمل رصد الأزرار أو أبلغ المستخدم عن مشكلة.",
            metrics: [
                .init(label: "رفع الصوت", value: volume.upCount > 0 ? "رُصد" : "لم يُرصد"),
                .init(label: "خفض الصوت", value: volume.downCount > 0 ? "رُصد" : "لم يُرصد"),
                .init(label: "زر الجانب", value: sideButtonConfirmed ? "أكد المستخدم عمله" : "غير مؤكد"),
                .init(label: "زر الإجراءات أو الصامت", value: actionOrMuteConfirmed ? "أكد المستخدم عمله" : "غير مؤكد")
            ],
            evidence: .mixed,
            limitation: "يُستدل على زري الصوت من تغير المستوى، أما زر الجانب والإجراءات أو الصامت فتأكيدهما يدوي.",
            startedAt: startedAt
        )
    }
}

struct BiometricsTestView: View {
    @EnvironmentObject private var store: DiagnosticsStore
    @StateObject private var biometrics = BiometricDiagnosticService()
    @State private var attempted = false
    @State private var startedAt = Date()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                DiagnosticCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(biometrics.typeTitle, systemImage: biometrics.typeTitle == "Touch ID" ? "touchid" : "faceid")
                            .font(.title3.bold())
                        Text(biometrics.isAvailable
                             ? "سيعرض النظام نافذة مصادقة حقيقية. لا يستطيع التطبيق رؤية بيانات الوجه أو البصمة."
                             : (biometrics.errorMessage ?? "المصادقة البيومترية غير متاحة."))
                            .foregroundStyle(.secondary)
                    }
                }

                if biometrics.isAvailable {
                    PrimaryActionButton(
                        title: biometrics.isAuthenticating ? "جارٍ انتظار المصادقة…" : "بدء اختبار المصادقة",
                        systemImage: biometrics.typeTitle == "Touch ID" ? "touchid" : "faceid",
                        disabled: biometrics.isAuthenticating
                    ) {
                        attempted = true
                        startedAt = Date()
                        biometrics.authenticate { success, _ in
                            if success { save(.pass) }
                        }
                    }
                } else {
                    PrimaryActionButton(title: "حفظ كغير قابل للفحص", systemImage: "lock.slash") {
                        save(.unsupported)
                    }
                }

                if attempted, let error = biometrics.errorMessage {
                    Text(error).foregroundStyle(.orange)
                    DiagnosticCard {
                        ResultControls(
                            onPass: { save(.warning) },
                            onWarning: { save(.warning) },
                            onFail: { save(.fail) }
                        )
                    }
                }
                TestDisclaimer()
            }
            .padding(AppTheme.screenPadding)
        }
        .navigationTitle(TestCategory.biometrics.titleAr)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            startedAt = Date()
            biometrics.refresh()
        }
    }

    private func save(_ outcome: TestOutcome) {
        store.record(
            category: .biometrics,
            outcome: outcome,
            summary: outcome == .pass ? "نجحت مصادقة بيومترية فعلية يديرها النظام." : "تعذرت المصادقة أو لم تكن مهيأة على الجهاز.",
            metrics: [
                .init(label: "النوع", value: biometrics.typeTitle),
                .init(label: "متاح للاختبار", value: biometrics.isAvailable ? "نعم" : "لا")
            ],
            evidence: .automatic,
            limitation: "النتيجة تثبت نجاح المصادقة لحظيًا ولا تكشف بيانات بيومترية للتطبيق.",
            startedAt: startedAt
        )
    }
}
