import SwiftUI

struct SystemInfoTestView: View {
    @EnvironmentObject private var store: DiagnosticsStore
    @State private var snapshot: SystemSnapshotService.Snapshot?
    @State private var startedAt = Date()

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if let snapshot {
                    DiagnosticCard {
                        VStack(alignment: .leading, spacing: 12) {
                            OutcomeBadge(outcome: snapshot.outcome)
                            Text(snapshot.summary)
                            Divider()
                            ForEach(snapshot.metrics) { MetricRow(metric: $0) }
                        }
                    }
                } else {
                    ProgressView("جارٍ جمع معلومات النظام…")
                        .frame(maxWidth: .infinity, minHeight: 180)
                }
                TestDisclaimer()
            }
            .padding(AppTheme.screenPadding)
        }
        .navigationTitle(TestCategory.system.titleAr)
        .navigationBarTitleDisplayMode(.inline)
        .task { gather() }
        .refreshable { gather() }
    }

    private func gather() {
        startedAt = Date()
        let value = SystemSnapshotService().collect()
        snapshot = value
        store.record(
            category: .system,
            outcome: value.outcome,
            summary: value.summary,
            metrics: value.metrics,
            evidence: .automatic,
            limitation: "لا تتيح Apple لتطبيقات iOS قراءة السعة القصوى للبطارية أو عدد دوراتها.",
            startedAt: startedAt
        )
    }
}

struct ConnectivityTestView: View {
    @EnvironmentObject private var store: DiagnosticsStore
    @StateObject private var monitor = ConnectivityMonitor()
    @State private var startedAt = Date()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                DiagnosticCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("الحالة الحالية", systemImage: "network")
                            .font(.headline)
                        status("الإنترنت", monitor.isOnline ? "متاح" : "غير متاح الآن", monitor.isOnline ? .green : .orange)
                        status("المسار", monitor.interfaceTitle, .primary)
                        status("البلوتوث", monitor.bluetoothTitle, .primary)
                        status("إذن الموقع", monitor.locationAuthorizationTitle, .primary)
                        if let accuracy = monitor.locationAccuracy {
                            status("قراءة GPS", "نجحت بدقة ±\(Int(accuracy.rounded())) متر", .green)
                        }
                    }
                }

                PrimaryActionButton(
                    title: monitor.isRequestingLocation ? "جارٍ انتظار قراءة GPS…" : "اختبار GPS بقراءة واحدة",
                    systemImage: "location.fill",
                    disabled: monitor.isRequestingLocation
                ) {
                    monitor.requestOneLocation()
                }

                if let error = monitor.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .accessibilityLabel("خطأ: \(error)")
                }

                DiagnosticCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("النتيجة").font(.headline)
                        Text("شغّل Wi‑Fi أو البيانات والبلوتوث، ثم أكّد هل تعمل. عدم وجود إنترنت الآن لا يثبت عطل العتاد.")
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
        .navigationTitle(TestCategory.connectivity.titleAr)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            startedAt = Date()
            monitor.start()
        }
        .onDisappear { monitor.stop() }
    }

    private func status(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold).foregroundStyle(color)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label)، \(value)")
    }

    private func save(_ outcome: TestOutcome) {
        store.record(
            category: .connectivity,
            outcome: outcome,
            summary: outcome == .pass ? "أكد المستخدم عمل الاتصالات المتاحة." : "أبلغ المستخدم عن مشكلة أو عدم يقين في الاتصالات.",
            metrics: monitor.metrics,
            evidence: .mixed,
            limitation: "لا تسمح واجهات iOS العامة باختبار هوائي Wi‑Fi أو المودم الخلوي كلًا على حدة.",
            startedAt: startedAt
        )
    }
}

struct MotionTestView: View {
    @EnvironmentObject private var store: DiagnosticsStore
    @StateObject private var motion = MotionDiagnosticController()
    @State private var startedAt = Date()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                DiagnosticCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("حرّك الهاتف وغطِّ أعلى الشاشة", systemImage: "move.3d")
                            .font(.headline)
                        Text("حرّك الهاتف بلطف في عدة اتجاهات، ثم قرّب يدك من منطقة السماعة لاختبار التقارب.")
                            .foregroundStyle(.secondary)
                        MetricRow(metric: .init(label: "عينات الحركة", value: "\(motion.sampleCount)"))
                        MetricRow(metric: .init(label: "التسارع الحالي", value: String(format: "%.3f g", motion.accelerationMagnitude)))
                        MetricRow(metric: .init(label: "الدوران الحالي", value: String(format: "%.3f rad/s", motion.rotationMagnitude)))
                        MetricRow(metric: .init(label: "التقارب", value: motion.proximityChanged ? "استجاب" : "لم يتغير بعد"))
                    }
                }

                if let error = motion.errorMessage {
                    Text(error).foregroundStyle(.red)
                }

                DiagnosticCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("حفظ النتيجة").font(.headline)
                        if !motion.motionAvailable {
                            PrimaryActionButton(title: "حفظ كغير قابل للفحص", systemImage: "lock.slash") {
                                save(.unsupported)
                            }
                        } else {
                            ResultControls(
                                onPass: { save(motion.receivedUsefulMotion ? .pass : .warning) },
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
        .navigationTitle(TestCategory.sensors.titleAr)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            startedAt = Date()
            motion.start()
        }
        .onDisappear { motion.stop() }
    }

    private func save(_ outcome: TestOutcome) {
        store.record(
            category: .sensors,
            outcome: outcome,
            summary: outcome == .pass ? "استجابت مستشعرات الحركة وأكد المستخدم سلامتها." : "لم يكتمل التحقق من جميع المستشعرات أو أبلغ المستخدم عن مشكلة.",
            metrics: motion.metrics,
            evidence: .mixed,
            limitation: "لا يتيح iOS قراءة شدة الإضاءة باللوكس لتطبيقات الطرف الثالث.",
            startedAt: startedAt
        )
    }
}
