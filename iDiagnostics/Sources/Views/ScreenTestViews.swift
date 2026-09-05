import SwiftUI
import UIKit

struct DisplayTestView: View {
    @EnvironmentObject private var store: DiagnosticsStore
    @State private var showColors = false
    @State private var completedColorRun = false
    @State private var startedAt = Date()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                DiagnosticCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("فحص بصري", systemImage: "eye.fill")
                            .font(.headline)
                        Text("سيعرض التطبيق ستة ألوان تملأ الشاشة. ابحث عن نقطة ثابتة لا تتغير مع الألوان، أو اطلب مساعدة شخص مبصر.")
                        Text("لا يستطيع تطبيق iOS التأكد برمجيًا من البكسل الميت؛ النتيجة تعتمد على المشاهدة.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                PrimaryActionButton(
                    title: completedColorRun ? "إعادة عرض الألوان" : "بدء عرض الألوان",
                    systemImage: "rectangle.inset.filled.and.person.filled"
                ) {
                    startedAt = Date()
                    showColors = true
                }

                if completedColorRun {
                    DiagnosticCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("هل ظهرت جميع الألوان بلا نقاط أو بقع ثابتة؟")
                                .font(.headline)
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
        .navigationTitle(TestCategory.display.titleAr)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showColors) {
            DisplayColorRunner(completed: $completedColorRun)
        }
    }

    private func save(_ outcome: TestOutcome) {
        store.record(
            category: .display,
            outcome: outcome,
            summary: outcome == .pass ? "أكد المستخدم أن الألوان ظهرت دون عيوب ثابتة." : "لاحظ المستخدم عيبًا أو لم يتمكن من تأكيد سلامة الشاشة.",
            metrics: [.init(label: "الألوان المعروضة", value: "أسود، أبيض، أحمر، أخضر، أزرق ورمادي")],
            evidence: .userConfirmed,
            limitation: "الفحص بصري ولا يقيس البكسلات إلكترونيًا.",
            startedAt: startedAt
        )
    }
}

private struct DisplayColorRunner: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var completed: Bool
    @State private var index = 0

    private let colors: [(Color, String)] = [
        (.black, "أسود"),
        (.white, "أبيض"),
        (.red, "أحمر"),
        (.green, "أخضر"),
        (.blue, "أزرق"),
        (Color(white: 0.5), "رمادي")
    ]

    var body: some View {
        ZStack {
            colors[index].0.ignoresSafeArea()
            VStack {
                HStack {
                    Button("إغلاق") { dismiss() }
                        .buttonStyle(.borderedProminent)
                    Spacer()
                    Text("\(index + 1) من \(colors.count): \(colors[index].1)")
                        .font(.headline)
                        .padding(10)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                Spacer()
                Button(index == colors.count - 1 ? "إنهاء الفحص" : "اللون التالي") {
                    advance()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()
        }
        .environment(\.layoutDirection, .rightToLeft)
        .accessibilityLabel("شاشة بلون \(colors[index].1)، اللون \(index + 1) من \(colors.count)")
        .onAppear { AccessibilityAnnouncer.post("بدأ فحص ألوان الشاشة. اللون الحالي \(colors[index].1)") }
    }

    private func advance() {
        if index < colors.count - 1 {
            index += 1
            AccessibilityAnnouncer.post("اللون \(colors[index].1)")
        } else {
            completed = true
            dismiss()
        }
    }
}

struct MultiTouchTestView: View {
    @EnvironmentObject private var store: DiagnosticsStore
    @State private var maximumTouches = 0
    @State private var coveredQuadrants = Set<Int>()
    @State private var startedAt = Date()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                DiagnosticCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("طريقة الفحص", systemImage: "hand.draw.fill")
                            .font(.headline)
                        Text("ضع إصبعين ثم زد العدد حتى خمسة، وحرّك أصابعك إلى جهات الشاشة الأربع.")
                        if UIAccessibility.isVoiceOverRunning {
                            Text("VoiceOver يلتقط إيماءات الأصابع وقد يمنع القياس. استخدم مساعدة شخص مبصر أو عطّل VoiceOver مؤقتًا لهذا الفحص فقط.")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                TouchTrackingSurface(
                    maximumTouches: $maximumTouches,
                    coveredQuadrants: $coveredQuadrants
                )
                .frame(height: 330)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.radius))
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.radius)
                        .stroke(Color.accentColor.opacity(0.4), lineWidth: 2)
                }

                DiagnosticCard {
                    VStack(alignment: .leading, spacing: 10) {
                        MetricRow(metric: .init(label: "أقصى لمس متزامن", value: "\(maximumTouches)"))
                        MetricRow(metric: .init(label: "الجهات التي وصلها اللمس", value: "\(coveredQuadrants.count) من 4"))
                        Button("إعادة القياس") {
                            maximumTouches = 0
                            coveredQuadrants.removeAll()
                            startedAt = Date()
                        }
                        .buttonStyle(.bordered)
                    }
                }

                DiagnosticCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("حفظ النتيجة").font(.headline)
                        ResultControls(
                            onPass: { save(maximumTouches >= 5 && coveredQuadrants.count == 4 ? .pass : .warning) },
                            onWarning: { save(.warning) },
                            onFail: { save(.fail) }
                        )
                    }
                }
                TestDisclaimer()
            }
            .padding(AppTheme.screenPadding)
        }
        .navigationTitle(TestCategory.multiTouch.titleAr)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func save(_ outcome: TestOutcome) {
        store.record(
            category: .multiTouch,
            outcome: outcome,
            summary: outcome == .pass ? "سُجلت خمس لمسات متزامنة وتغطية الجهات الأربع." : "لم يكتمل معيار خمس لمسات والجهات الأربع أو أبلغ المستخدم عن مشكلة.",
            metrics: [
                .init(label: "أقصى لمس متزامن", value: "\(maximumTouches)"),
                .init(label: "تغطية الجهات", value: "\(coveredQuadrants.count) من 4")
            ],
            evidence: .mixed,
            limitation: "قد تمنع ميزات تسهيلات الاستخدام وصول بعض إيماءات اللمس إلى التطبيق.",
            startedAt: startedAt
        )
    }
}

private struct TouchTrackingSurface: UIViewRepresentable {
    @Binding var maximumTouches: Int
    @Binding var coveredQuadrants: Set<Int>

    func makeUIView(context: Context) -> TouchSurfaceUIView {
        let view = TouchSurfaceUIView()
        view.onUpdate = { count, quadrants in
            DispatchQueue.main.async {
                maximumTouches = max(maximumTouches, count)
                coveredQuadrants.formUnion(quadrants)
            }
        }
        return view
    }

    func updateUIView(_ uiView: TouchSurfaceUIView, context: Context) {}
}

private final class TouchSurfaceUIView: UIView {
    var onUpdate: ((Int, Set<Int>) -> Void)?
    private var dots: [ObjectIdentifier: CAShapeLayer] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .secondarySystemGroupedBackground
        isAccessibilityElement = true
        accessibilityLabel = "منطقة قياس اللمس المتعدد"
        accessibilityHint = "ضع عدة أصابع وحركها على جميع أجزاء المنطقة"
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isMultipleTouchEnabled = true
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { update(event) }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { update(event) }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { update(event) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { update(event) }

    private func update(_ event: UIEvent?) {
        let active = (event?.allTouches ?? []).filter { $0.phase != .ended && $0.phase != .cancelled }
        var quadrants = Set<Int>()
        var activeKeys = Set<ObjectIdentifier>()

        for touch in active {
            let point = touch.location(in: self)
            let key = ObjectIdentifier(touch)
            activeKeys.insert(key)
            quadrants.insert(quadrant(for: point))

            let dot = dots[key] ?? {
                let layer = CAShapeLayer()
                layer.fillColor = UIColor.systemBlue.withAlphaComponent(0.55).cgColor
                self.layer.addSublayer(layer)
                dots[key] = layer
                return layer
            }()
            dot.path = UIBezierPath(ovalIn: CGRect(x: point.x - 22, y: point.y - 22, width: 44, height: 44)).cgPath
        }

        let staleKeys = dots.keys.filter { !activeKeys.contains($0) }
        for key in staleKeys {
            dots[key]?.removeFromSuperlayer()
            dots.removeValue(forKey: key)
        }
        onUpdate?(active.count, quadrants)
    }

    private func quadrant(for point: CGPoint) -> Int {
        let right = point.x >= bounds.midX ? 1 : 0
        let bottom = point.y >= bounds.midY ? 2 : 0
        return right + bottom
    }
}
