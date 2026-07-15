import SwiftUI

/// Full-screen dead-pixel test. Cycles through solid colors that fill the entire
/// screen (safe area + status bar hidden). Tapping anywhere advances to the next
/// color; a small always-visible "خروج" button returns. After the user has seen
/// the palette they self-assess via `PassFailControls`, recording `.display`.
struct DisplayTestView: View {
    @EnvironmentObject private var store: DiagnosticsStore
    @Environment(\.dismiss) private var dismiss

    /// One solid color plus its Arabic name for the accessibility announcement.
    private struct Swatch {
        let color: Color
        let nameAr: String
    }

    private let swatches: [Swatch] = [
        Swatch(color: .red,   nameAr: "أحمر"),
        Swatch(color: .green, nameAr: "أخضر"),
        Swatch(color: .blue,  nameAr: "أزرق"),
        Swatch(color: .white, nameAr: "أبيض"),
        Swatch(color: .black, nameAr: "أسود"),
        Swatch(color: .gray,  nameAr: "رمادي"),
    ]

    @State private var index = 0
    /// Becomes true once the user has cycled through every color at least once.
    @State private var seenAll = false
    /// When true we overlay the pass/fail prompt instead of advancing on tap.
    @State private var showingPrompt = false

    private var current: Swatch { swatches[index] }

    /// A contrasting foreground so controls stay legible on any swatch.
    private var contrastColor: Color {
        switch current.color {
        case .white, .gray: return .black
        default:            return .white
        }
    }

    var body: some View {
        ZStack {
            current.color
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !showingPrompt else { return }
                    advance()
                }
                .accessibilityElement()
                .accessibilityLabel("اللون الحالي: \(current.nameAr). انقر في أي مكان للانتقال إلى اللون التالي.")
                .accessibilityAddTraits(.isButton)

            VStack {
                HStack {
                    Button(role: .cancel) { dismiss() } label: {
                        Label("خروج", systemImage: "xmark")
                            .fontWeight(.semibold)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .tint(contrastColor)
                    .accessibilityLabel("خروج من فحص الشاشة")
                    Spacer()
                    Text("\(index + 1) / \(swatches.count)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(contrastColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .accessibilityLabel("اللون \(index + 1) من \(swatches.count)")
                }
                .padding(Theme.screenPadding)

                Spacer()

                if showingPrompt {
                    promptCard
                        .padding(Theme.screenPadding)
                } else {
                    Text(seenAll ? "انقر مرة أخرى لإنهاء الجولة" : "انقر في أي مكان للون التالي")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(contrastColor)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, Theme.screenPadding)
                        .accessibilityHidden(true)
                }
            }
        }
        .statusBarHidden(true)
        .navigationBarHidden(true)
        .onChange(of: index) { newValue in
            UIAccessibility.post(notification: .announcement, argument: current.nameAr)
        }
    }

    private var promptCard: some View {
        VStack(spacing: 14) {
            Text("هل رأيت بكسلات ميتة؟")
                .font(.headline)
                .multilineTextAlignment(.center)
            PassFailControls(
                onPass: { record(.pass) },   // يعمل: no dead pixels
                onFail: { record(.fail) }    // لا يعمل: dead pixels found
            )
        }
        .padding(Theme.cardPadding)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }

    private func advance() {
        let next = (index + 1) % swatches.count
        if next == 0 { seenAll = true }
        // Once the whole palette has been seen, the next tap raises the prompt.
        if seenAll && next == 0 {
            showingPrompt = true
        } else {
            index = next
        }
    }

    private func record(_ outcome: TestOutcome) {
        let summary = outcome == .pass
            ? "لم يُبلّغ المستخدم عن بكسلات ميتة."
            : "أبلغ المستخدم عن وجود بكسلات ميتة أو تلف في الشاشة."
        store.record(TestResult(
            category: .display,
            outcome: outcome,
            summaryAr: summary,
            metrics: [
                TestResult.Metric(label: "الألوان المفحوصة", value: "\(swatches.count)")
            ]
        ))
        dismiss()
    }
}
