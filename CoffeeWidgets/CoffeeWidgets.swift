import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct CoffeeWidgetsBundle: WidgetBundle {
    var body: some Widget {
        UsualDrinkWidget()
        MachineStatusWidget()
        BrewLiveActivity()
        if #available(iOS 18.0, *) {
            UsualDrinkControl()
            MorningRoutineControl()
        }
    }
}

// MARK: - Shared text

private struct Texts {
    let arabic: Bool
    init(_ snapshot: WidgetSnapshot?) {
        arabic = snapshot?.isArabic ?? (Locale.current.language.languageCode?.identifier == "ar")
    }
    func t(_ ar: String, _ en: String) -> String { arabic ? ar : en }
}

private let accent = Color(red: 0.89, green: 0.65, blue: 0.46)

// MARK: - Timeline

struct CoffeeEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct CoffeeProvider: TimelineProvider {
    func placeholder(in context: Context) -> CoffeeEntry {
        CoffeeEntry(date: Date(), snapshot: WidgetSnapshot(
            usualName: "كابتشينو", usualSummary: "", usualLink: CoffeeLink.usual.absoluteString, machineStatus: "جاهزة",
            machineReady: true, caffeineToday: 120, caffeineLimit: 400, isArabic: true, updatedAt: Date()))
    }

    func getSnapshot(in context: Context, completion: @escaping (CoffeeEntry) -> Void) {
        completion(CoffeeEntry(date: Date(), snapshot: WidgetSnapshot.load() ?? placeholder(in: context).snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CoffeeEntry>) -> Void) {
        let entry = CoffeeEntry(date: Date(), snapshot: WidgetSnapshot.load())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(1800))))
    }
}

private struct WidgetBackground: ViewModifier {
    func body(content: Content) -> some View {
        content.containerBackground(for: .widget) { Color(red: 0.13, green: 0.11, blue: 0.09) }
    }
}

// MARK: - "My usual" widget

struct UsualDrinkWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedCoffee.widgetKind, provider: CoffeeProvider()) { entry in
            UsualDrinkView(entry: entry)
        }
        .configurationDisplayName("قهوتي المعتادة")
        .description("My usual drink in one tap · مشروبك المعتاد بلمسة")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryCircular])
    }
}

struct UsualDrinkView: View {
    @Environment(\.widgetFamily) var family
    let entry: CoffeeEntry

    var body: some View {
        let texts = Texts(entry.snapshot)
        let name = entry.snapshot?.usualName ?? texts.t("قهوتي", "My coffee")
        Group {
            switch family {
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "cup.and.saucer.fill").font(.title2)
                }
                .accessibilityLabel(texts.t("حضّر \(name)", "Make \(name)"))
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text(texts.t("مشروبك المعتاد", "Your usual")).font(.caption2)
                    Text(name).font(.headline).lineLimit(2)
                }
                .accessibilityElement(children: .combine)
            default:
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "cup.and.saucer.fill").font(.title2).foregroundStyle(accent).accessibilityHidden(true)
                    Text(texts.t("مشروبك المعتاد", "Your usual")).font(.caption).foregroundStyle(.white.opacity(0.75))
                    Text(name).font(.headline).foregroundStyle(.white).lineLimit(3)
                    Spacer(minLength: 0)
                    Button(intent: BrewUsualIntent()) {
                        Text(texts.t("حضّر", "Make it")).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity)
                    }
                    .tint(accent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .environment(\.layoutDirection, texts.arabic ? .rightToLeft : .leftToRight)
        .widgetURL(CoffeeLink.usual)
        .modifier(WidgetBackground())
    }
}

// MARK: - Machine status and caffeine widget

struct MachineStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedCoffee.statusWidgetKind, provider: CoffeeProvider()) { entry in
            MachineStatusWidgetView(entry: entry)
        }
        .configurationDisplayName("حالة الماكينة")
        .description("Machine status and today's caffeine · حالة الماكينة وكافيين اليوم")
        .supportedFamilies([.systemSmall, .accessoryInline, .accessoryRectangular])
    }
}

struct MachineStatusWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: CoffeeEntry

    var body: some View {
        let texts = Texts(entry.snapshot)
        let status = entry.snapshot?.machineStatus ?? texts.t("افتح التطبيق للاتصال", "Open the app to connect")
        let caffeine = entry.snapshot.map { texts.t("الكافيين \($0.caffeineToday) من \($0.caffeineLimit) ملغ", "Caffeine \($0.caffeineToday) of \($0.caffeineLimit) mg") } ?? ""
        Group {
            switch family {
            case .accessoryInline:
                Label(status, systemImage: entry.snapshot?.machineReady == true ? "checkmark.circle" : "cup.and.saucer")
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text(status).font(.headline).lineLimit(2)
                    Text(caffeine).font(.caption2)
                }
                .accessibilityElement(children: .combine)
            default:
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: entry.snapshot?.machineReady == true ? "checkmark.circle.fill" : "cup.and.saucer")
                        .font(.title2).foregroundStyle(accent).accessibilityHidden(true)
                    Text(status).font(.headline).foregroundStyle(.white).lineLimit(3)
                    Spacer(minLength: 0)
                    Text(caffeine).font(.caption).foregroundStyle(.white.opacity(0.8)).lineLimit(2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .accessibilityElement(children: .combine)
            }
        }
        .environment(\.layoutDirection, texts.arabic ? .rightToLeft : .leftToRight)
        .widgetURL(CoffeeLink.home)
        .modifier(WidgetBackground())
    }
}

// MARK: - Live Activity

struct BrewLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BrewActivityAttributes.self) { context in
            HStack(spacing: 14) {
                Image(systemName: context.state.finished ? "checkmark.circle.fill" : "cup.and.saucer.fill")
                    .font(.title)
                    .foregroundStyle(accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.attributes.drinkName).font(.headline).foregroundStyle(.white)
                    Text(context.state.phase).font(.subheadline).foregroundStyle(.white.opacity(0.85))
                    if !context.state.finished && !context.state.failed {
                        ProgressView(value: Double(context.state.percent), total: 100).tint(accent)
                    }
                }
                Spacer(minLength: 0)
                Text("\(context.state.percent)%").font(.title3.monospacedDigit().weight(.semibold)).foregroundStyle(.white)
            }
            .padding()
            .environment(\.layoutDirection, context.attributes.isArabic ? .rightToLeft : .leftToRight)
            .activityBackgroundTint(Color.black.opacity(0.85))
            .accessibilityElement(children: .combine)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "cup.and.saucer.fill").foregroundStyle(accent).accessibilityHidden(true)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.percent)%").monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading) {
                        Text(context.attributes.drinkName).font(.headline)
                        Text(context.state.phase).font(.subheadline)
                        if !context.state.finished {
                            Button(intent: StopBrewingIntent()) {
                                Label(context.attributes.isArabic ? "إيقاف" : "Stop", systemImage: "stop.fill")
                            }
                            .tint(.red)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "cup.and.saucer.fill").foregroundStyle(accent)
            } compactTrailing: {
                Text("\(context.state.percent)%").monospacedDigit()
            } minimal: {
                Image(systemName: "cup.and.saucer.fill").foregroundStyle(accent)
            }
        }
    }
}

// MARK: - Control Center, Lock Screen and Action button (iOS 18)

@available(iOS 18.0, *)
struct UsualDrinkControl: ControlWidget {
    private static var arabic: Bool { Locale.current.language.languageCode?.identifier == "ar" }

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.coffeeaccess.control.usual") {
            ControlWidgetButton(action: BrewUsualIntent()) {
                Label(Self.arabic ? "قهوتي المعتادة" : "My usual", systemImage: "cup.and.saucer.fill")
            }
        }
        .displayName(LocalizedStringResource(String.LocalizationValue(Self.arabic ? "قهوتي: مشروبي المعتاد" : "Coffee: my usual")))
        .description(LocalizedStringResource(String.LocalizationValue(Self.arabic ? "يحضّر مشروبك المعتاد فورًا." : "Makes your usual drink right away.")))
    }
}

@available(iOS 18.0, *)
struct MorningRoutineControl: ControlWidget {
    private static var arabic: Bool { Locale.current.language.languageCode?.identifier == "ar" }

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.coffeeaccess.control.routine") {
            ControlWidgetButton(action: MorningRoutineIntent()) {
                Label(Self.arabic ? "روتين الصباح" : "Morning coffee", systemImage: "sunrise.fill")
            }
        }
        .displayName(LocalizedStringResource(String.LocalizationValue(Self.arabic ? "قهوتي: روتين الصباح" : "Coffee: morning routine")))
        .description(LocalizedStringResource(String.LocalizationValue(Self.arabic ? "يشغّل الماكينة ثم يحضّر مشروبك." : "Turns the machine on, then makes your drink.")))
    }
}
