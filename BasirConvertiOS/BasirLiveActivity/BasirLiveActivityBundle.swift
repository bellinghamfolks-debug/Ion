import ActivityKit
import SwiftUI
import WidgetKit

@main
struct BasirLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        BasirJobLiveActivity()
        BasirLatestResultWidget()
        if #available(iOS 18.0, *) {
            BasirScanControl()
            BasirReadLatestControl()
        }
    }
}

struct BasirJobLiveActivity: Widget {
    private let accent = Color(red: 0.36, green: 0.86, blue: 1.00)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BasirJobActivityAttributes.self) { context in
            LockScreenJobView(attributes: context.attributes, state: context.state, accent: accent)
                .environment(\.layoutDirection, context.attributes.isArabic ? .rightToLeft : .leftToRight)
                .activityBackgroundTint(Color.black.opacity(0.82))
                .activitySystemActionForegroundColor(accent)
        } dynamicIsland: { context in
            let state = context.state
            let attributes = context.attributes
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: icon(for: state))
                        .font(.title2)
                        .foregroundStyle(accent)
                        .accessibilityHidden(true)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(state.percent)%")
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(attributes.fileName)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: Double(state.percent), total: 100).tint(accent)
                        Text(state.statusText)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(2)
                    }
                    .environment(\.layoutDirection, attributes.isArabic ? .rightToLeft : .leftToRight)
                }
            } compactLeading: {
                Image(systemName: icon(for: state))
                    .foregroundStyle(accent)
                    .accessibilityLabel(state.stepTitle)
            } compactTrailing: {
                Text("\(state.percent)%")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(accent)
            } minimal: {
                ProgressView(value: Double(state.percent), total: 100)
                    .progressViewStyle(.circular)
                    .tint(accent)
                    .accessibilityLabel(state.statusText)
            }
        }
    }

    private func icon(for state: BasirJobActivityAttributes.ContentState) -> String {
        if state.isFinished { return state.succeeded ? "checkmark.circle.fill" : "xmark.octagon.fill" }
        if state.isPaused { return "pause.circle.fill" }
        switch state.stepIndex {
        case 0: return "arrow.up.doc"
        case 1: return "text.viewfinder"
        case 2: return "checkmark.shield"
        case 3: return "doc.richtext"
        default: return "arrow.down.doc"
        }
    }
}

private struct LockScreenJobView: View {
    let attributes: BasirJobActivityAttributes
    let state: BasirJobActivityAttributes.ContentState
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "eye.circle.fill")
                    .font(.title3)
                    .foregroundStyle(accent)
                    .accessibilityHidden(true)
                Text(attributes.fileName)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("\(state.percent)%")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.white)
            }
            ProgressView(value: Double(state.percent), total: 100).tint(accent)
            HStack(spacing: 6) {
                ForEach(Array(attributes.stepNames.enumerated()), id: \.offset) { index, name in
                    Text(name)
                        .font(.caption2.weight(index == state.stepIndex ? .bold : .regular))
                        .foregroundStyle(index < state.stepIndex || state.isFinished && state.succeeded
                                         ? accent
                                         : (index == state.stepIndex ? .white : .white.opacity(0.55)))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)
            Text(state.statusText)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(2)
        }
        .padding(16)
        .accessibilityElement(children: .combine)
    }
}
