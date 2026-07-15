import SwiftUI

/// The `.sensors` diagnostic screen: live accelerometer / gyroscope readouts, a
/// spirit-level bubble driven by tilt, a proximity sub-test, and an honest
/// `.unsupported` row for ambient-light (no public iOS API).
struct SensorTestView: View {
    @EnvironmentObject private var store: DiagnosticsStore
    @StateObject private var sensors = SensorService()

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                spiritLevelCard
                readoutsCard
                proximityCard
                ambientLightCard

                PrimaryButton(title: "إنهاء وتسجيل النتيجة",
                              systemImage: "checkmark.circle") {
                    recordResult()
                }
                .disabled(!sensors.didReceiveMotion)
            }
            .padding(Theme.screenPadding)
        }
        .navigationTitle(TestCategory.sensors.titleAr)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { sensors.start() }
        .onDisappear { sensors.stop() }
    }

    // MARK: - Spirit level

    private var spiritLevelCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Label("ميزان الاستواء", systemImage: "level")
                    .font(.headline)
                Text("أمِل الجهاز لتحريك الفقاعة نحو المركز")
                    .font(.caption).foregroundStyle(.secondary)

                SpiritLevelBubble(x: sensors.acceleration.x,
                                  y: sensors.acceleration.y)
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
            }
        }
    }

    // MARK: - Numeric readouts

    private var readoutsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                axisGroup(title: "التسارع (g)",
                          systemImage: "gauge.with.dots.needle.bottom.50percent",
                          available: sensors.isAccelerometerAvailable,
                          value: sensors.acceleration)
                Divider()
                axisGroup(title: "الجيروسكوب (راديان/ث)",
                          systemImage: "gyroscope",
                          available: sensors.isGyroAvailable,
                          value: sensors.rotation)
            }
        }
    }

    private func axisGroup(title: String,
                           systemImage: String,
                           available: Bool,
                           value: (x: Double, y: Double, z: Double)) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage).font(.subheadline.weight(.semibold))
            if available {
                HStack(spacing: 10) {
                    axisPill("X", value.x)
                    axisPill("Y", value.y)
                    axisPill("Z", value.z)
                }
            } else {
                Text("غير متوفر على هذا الجهاز")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(available
            ? "\(title). سين \(fmt(value.x))، صاد \(fmt(value.y))، عين \(fmt(value.z))"
            : "\(title). غير متوفر على هذا الجهاز")
    }

    private func axisPill(_ label: String, _ value: Double) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(fmt(value)).font(.system(.body, design: .monospaced).weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Proximity

    private var proximityCard: some View {
        Card {
            HStack(spacing: 14) {
                Image(systemName: sensors.isNear ? "hand.raised.fill" : "hand.raised.slash")
                    .font(.title)
                    .foregroundStyle(sensors.isNear ? Color.green : .secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Label("مستشعر التقارب", systemImage: "sensor.tag.radiowaves.forward")
                        .font(.headline)
                    Text("غطِّ أعلى الشاشة")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(sensors.isNear ? "قريب" : "بعيد")
                    .font(.headline)
                    .foregroundStyle(sensors.isNear ? Color.green : .secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("مستشعر التقارب، غطِّ أعلى الشاشة")
        .accessibilityValue(sensors.isNear ? "قريب" : "بعيد")
    }

    // MARK: - Ambient light (unsupported)

    private var ambientLightCard: some View {
        Card {
            HStack(spacing: 14) {
                Image(systemName: TestOutcome.unsupported.systemImage)
                    .font(.title)
                    .foregroundStyle(TestOutcome.unsupported.color)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Label("مستشعر الإضاءة المحيطة", systemImage: "sun.max")
                        .font(.headline)
                    Text("لا توفّر iOS واجهة عامة لقياس شدّة الإضاءة (لكس)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(TestOutcome.unsupported.titleAr)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TestOutcome.unsupported.color)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("مستشعر الإضاءة المحيطة، \(TestOutcome.unsupported.titleAr). لا توفّر iOS واجهة عامة لقياس شدّة الإضاءة")
    }

    // MARK: - Recording

    private func recordResult() {
        let passed = sensors.didReceiveMotion
        let result = TestResult(
            category: .sensors,
            outcome: passed ? .pass : .fail,
            summaryAr: passed
                ? "تم استقبال بيانات الحركة من المستشعرات بنجاح"
                : "لم يتم استقبال بيانات من مستشعرات الحركة",
            metrics: [
                .init(label: "التسارع سين", value: fmt(sensors.acceleration.x)),
                .init(label: "التسارع صاد", value: fmt(sensors.acceleration.y)),
                .init(label: "التسارع عين", value: fmt(sensors.acceleration.z)),
                .init(label: "الجيروسكوب سين", value: fmt(sensors.rotation.x)),
                .init(label: "الجيروسكوب صاد", value: fmt(sensors.rotation.y)),
                .init(label: "الجيروسكوب عين", value: fmt(sensors.rotation.z)),
                .init(label: "التقارب", value: sensors.isNear ? "قريب" : "بعيد"),
                .init(label: "الإضاءة المحيطة", value: TestOutcome.unsupported.titleAr)
            ]
        )
        store.record(result)
    }

    private func fmt(_ v: Double) -> String {
        String(format: "%+.2f", v)
    }
}

/// A spirit-level ("bubble") that slides opposite to device tilt, driven by the
/// accelerometer's x/y axes. Announces its tilt to VoiceOver.
struct SpiritLevelBubble: View {
    /// Accelerometer x (g), roughly -1...1 across a full tilt.
    let x: Double
    /// Accelerometer y (g), roughly -1...1 across a full tilt.
    let y: Double

    private var isLevel: Bool { abs(x) < 0.04 && abs(y) < 0.04 }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let radius = side / 2
            let bubble = side * 0.18
            let travel = radius - bubble / 2 - 6

            // Bubble moves toward the raised edge (opposite gravity on that axis).
            let dx = clamp(x) * travel
            // In UIKit screen space +y points down, accelerometer +y points up.
            let dy = -clamp(y) * travel

            ZStack {
                Circle().stroke(.quaternary, lineWidth: 2)
                Circle()
                    .stroke(isLevel ? Color.green : .secondary, lineWidth: 2)
                    .frame(width: bubble * 1.15, height: bubble * 1.15)
                Circle()
                    .fill(isLevel ? Color.green : Color.accentColor)
                    .frame(width: bubble, height: bubble)
                    .offset(x: dx, y: dy)
                    .animation(.easeOut(duration: 0.12), value: dx)
                    .animation(.easeOut(duration: 0.12), value: dy)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement()
        .accessibilityLabel("فقاعة ميزان الاستواء")
        .accessibilityValue(levelDescription)
    }

    private var levelDescription: String {
        if isLevel { return "الجهاز مستوٍ" }
        let horiz = x > 0.04 ? "مائل يمينًا" : (x < -0.04 ? "مائل يسارًا" : "")
        let vert = y > 0.04 ? "مائل للأعلى" : (y < -0.04 ? "مائل للأسفل" : "")
        return [horiz, vert].filter { !$0.isEmpty }.joined(separator: "، ")
    }

    private func clamp(_ v: Double) -> CGFloat {
        CGFloat(min(1, max(-1, v)))
    }
}
