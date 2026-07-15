import SwiftUI

/// Tracks multiple simultaneous touches. A `UIViewRepresentable` reports the set
/// of active touch points; we overlay a colored circle at each and show the live
/// and maximum simultaneous touch count. The user confirms via `PassFailControls`,
/// recording `.multiTouch`.
struct MultiTouchTestView: View {
    @EnvironmentObject private var store: DiagnosticsStore
    @Environment(\.dismiss) private var dismiss

    @State private var activePoints: [CGPoint] = []
    @State private var maxSimultaneous = 0

    /// A stable palette so each finger keeps a distinct color by slot.
    private let palette: [Color] = [
        .red, .orange, .yellow, .green, .mint, .teal,
        .blue, .indigo, .purple, .pink, .brown, .cyan,
    ]

    var body: some View {
        VStack(spacing: 16) {
            counters

            ZStack {
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .fill(.background.secondary)

                TouchTrackingView(points: $activePoints)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))

                ForEach(Array(activePoints.enumerated()), id: \.offset) { pair in
                    Circle()
                        .fill(palette[pair.offset % palette.count].opacity(0.85))
                        .frame(width: 66, height: 66)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .position(pair.element)
                        .allowsHitTesting(false)
                }

                if activePoints.isEmpty {
                    Text("ضع أصابعك على هذه المنطقة")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement()
            .accessibilityLabel("منطقة تتبّع اللمس. عدد اللمسات النشطة: \(activePoints.count)")

            PassFailControls(
                onPass: { record(.pass) },
                onFail: { record(.fail) }
            )
        }
        .padding(Theme.screenPadding)
        .navigationTitle("اللمس المتعدد")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: activePoints) { newValue in
            if newValue.count > maxSimultaneous {
                maxSimultaneous = newValue.count
            }
        }
    }

    private var counters: some View {
        HStack(spacing: 12) {
            countTile(title: "اللمسات الآن", value: activePoints.count, tint: .blue)
            countTile(title: "أقصى عدد متزامن", value: maxSimultaneous, tint: .green)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("اللمسات النشطة \(activePoints.count)، أقصى عدد متزامن \(maxSimultaneous)")
    }

    private func countTile(title: String, value: Int, tint: Color) -> some View {
        Card {
            VStack(spacing: 4) {
                Text("\(value)")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func record(_ outcome: TestOutcome) {
        let summary = outcome == .pass
            ? "أكّد المستخدم تتبّع جميع الأصابع بشكل صحيح."
            : "أبلغ المستخدم عن نقاط لمس لم تُتتبَّع بشكل صحيح."
        store.record(TestResult(
            category: .multiTouch,
            outcome: outcome,
            summaryAr: summary,
            metrics: [
                TestResult.Metric(label: "أقصى عدد لمسات متزامنة", value: "\(maxSimultaneous)")
            ]
        ))
        dismiss()
    }
}

/// A UIView that enables multi-touch and reports the current set of active touch
/// locations (in its own coordinate space) back to SwiftUI via a binding.
struct TouchTrackingView: UIViewRepresentable {
    @Binding var points: [CGPoint]

    func makeUIView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.isMultipleTouchEnabled = true
        view.backgroundColor = .clear
        view.onChange = { newPoints in
            // Hop to the main actor before mutating SwiftUI state.
            DispatchQueue.main.async { points = newPoints }
        }
        return view
    }

    func updateUIView(_ uiView: TrackingView, context: Context) {}

    /// The backing UIView. Overrides every touch phase and recomputes the live
    /// set of active touches from its own tracked set.
    final class TrackingView: UIView {
        var onChange: (([CGPoint]) -> Void)?
        private var active: Set<UITouch> = []

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            active.formUnion(touches)
            report()
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            report()
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            active.subtract(touches)
            report()
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            active.subtract(touches)
            report()
        }

        private func report() {
            let locations = active.map { $0.location(in: self) }
            onChange?(locations)
        }
    }
}
