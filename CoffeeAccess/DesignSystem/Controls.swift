import SwiftUI

/// A stepped amount (ml or seconds). With VoiceOver it is a single
/// adjustable element: swipe up or down to change it, and the Actions rotor
/// offers the small / standard / large presets. Without VoiceOver the − and
/// + buttons and preset chips are visible and work with Voice Control and
/// Switch Control by name.
struct QuantityControl: View {
    let title: String
    let symbol: String
    @Binding var value: Int
    let range: QuantityRange
    let unitKey: String

    @Environment(\.accessibilityVoiceOverEnabled) var voiceOver
    @Environment(\.dynamicTypeSize) var typeSize

    private var valueText: String { L(unitKey, value) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Label(title, systemImage: symbol)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 8)
                Text(valueText)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.accent)
            }
            HStack(spacing: 12) {
                stepButton(symbol: "minus", label: L("control.decrease", title), steps: -1)
                    .disabled(value <= range.min)
                ProgressView(value: Double(value - range.min), total: Double(max(range.max - range.min, 1)))
                    .tint(Theme.accent)
                    .accessibilityHidden(true)
                stepButton(symbol: "plus", label: L("control.increase", title), steps: 1)
                    .disabled(value >= range.max)
            }
            presetChips
        }
        .padding(16)
        .card()
        .accessibilityElement(children: voiceOver ? .ignore : .contain)
        .accessibilityLabel(title)
        .accessibilityValue(valueText)
        .accessibilityHint(voiceOver ? L("control.adjustHint") : "")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: change(by: 1)
            case .decrement: change(by: -1)
            @unknown default: break
            }
        }
        .modifier(PresetActions(presets: range.presets, unitKey: unitKey, standard: range.standard) { value = $0; Announcer.shared.tick() })
    }

    private func stepButton(symbol: String, label: String, steps: Int) -> some View {
        Button {
            change(by: steps)
        } label: {
            Image(systemName: symbol)
                .font(.title3.weight(.bold))
                .frame(width: 48, height: 48)
                .background(Circle().fill(Theme.surfaceRaised))
                .foregroundStyle(Theme.accent)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(valueText)
    }

    @ViewBuilder
    private var presetChips: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        layout {
            ForEach(range.presets, id: \.self) { preset in
                Button {
                    value = preset
                    Announcer.shared.tick()
                } label: {
                    Text(PresetActions.name(for: preset, in: range.presets, standard: range.standard, unitKey: unitKey))
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 12)
                        .frame(minHeight: 36)
                        .background(Capsule().fill(preset == value ? Theme.accent : Theme.surfaceRaised))
                        .foregroundStyle(preset == value ? Theme.onAccent : Theme.textPrimary)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(preset == value ? .isSelected : [])
            }
        }
    }

    private func change(by steps: Int) {
        let next = range.stepped(value, by: steps)
        guard next != value else { return }
        value = next
        Announcer.shared.tick()
    }
}

/// Exposes presets as VoiceOver custom actions ("Small, 30 ml").
private struct PresetActions: ViewModifier {
    let presets: [Int]
    let unitKey: String
    let standard: Int
    let apply: (Int) -> Void

    static func name(for preset: Int, in presets: [Int], standard: Int, unitKey: String) -> String {
        let size: String
        if preset == standard { size = L("preset.standard") }
        else if preset < standard { size = L("preset.small") }
        else { size = L("preset.large") }
        return "\(size) · \(L(unitKey, preset))"
    }

    func body(content: Content) -> some View {
        presets.reduce(AnyView(content)) { view, preset in
            AnyView(view.accessibilityAction(named: Text(Self.name(for: preset, in: presets, standard: standard, unitKey: unitKey))) {
                apply(preset)
            })
        }
    }
}

/// A choice among a few named levels (strength, temperature), shown as a
/// row of segments. VoiceOver: one adjustable element, "Strength, Strong,
/// 4 of 5".
struct LevelControl<Level: Hashable>: View {
    let title: String
    let symbol: String
    let levels: [Level]
    @Binding var selection: Level
    let name: (Level) -> String

    @Environment(\.accessibilityVoiceOverEnabled) var voiceOver
    @Environment(\.dynamicTypeSize) var typeSize

    private var index: Int { levels.firstIndex(of: selection) ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: symbol)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 8)
                Text(name(selection))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 6))
            layout {
                ForEach(Array(levels.enumerated()), id: \.offset) { offset, level in
                    Button {
                        selection = level
                        Announcer.shared.tick()
                    } label: {
                        VStack(spacing: 4) {
                            Capsule()
                                .fill(offset <= index ? Theme.accent : Theme.surfaceRaised)
                                .frame(height: 10)
                            if typeSize.isAccessibilitySize {
                                Text(name(level)).font(.callout)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(name(level))
                    .accessibilityAddTraits(level == selection ? .isSelected : [])
                }
            }
        }
        .padding(16)
        .card()
        .accessibilityElement(children: voiceOver ? .ignore : .contain)
        .accessibilityLabel(title)
        .accessibilityValue(L("control.levelValue", name(selection), index + 1, levels.count))
        .accessibilityHint(voiceOver ? L("control.adjustHint") : "")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment where index < levels.count - 1: selection = levels[index + 1]; Announcer.shared.tick()
            case .decrement where index > 0: selection = levels[index - 1]; Announcer.shared.tick()
            default: break
            }
        }
    }
}

/// A labelled fill gauge (water tank, beans, grounds).
struct LevelGauge: View {
    let title: String
    let symbol: String
    let level: Double
    var warnWhenLow = true

    private var percent: Int { Int((level * 100).rounded()) }
    private var color: Color {
        if warnWhenLow { return level < 0.15 ? Theme.danger : (level < 0.3 ? Theme.warning : Theme.success) }
        return level > 0.85 ? Theme.danger : (level > 0.6 ? Theme.warning : Theme.success)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            ProgressView(value: level)
                .tint(color)
            Text(L("unit.percent", percent))
                .font(.footnote.monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(raised: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(L("unit.percent", percent))
    }
}

struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.title2.weight(.bold))
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}
