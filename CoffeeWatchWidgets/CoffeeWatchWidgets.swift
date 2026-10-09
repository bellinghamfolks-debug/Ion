import SwiftUI
import WidgetKit

/// Watch face complications: the machine's state, today's caffeine and the
/// next care job, as last sent by the phone.
@main
struct CoffeeWatchWidgets: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CoffeeWatchComplication", provider: WatchProvider()) { entry in
            WatchComplicationView(entry: entry)
        }
        .configurationDisplayName("قهوتي")
        .description("Machine status and caffeine · حالة الماكينة والكافيين")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

struct WatchEntry: TimelineEntry {
    let date: Date
    let status: String
    let caffeine: String
    let care: String
    let ready: Bool
    let arabic: Bool

    static func load(date: Date = Date()) -> WatchEntry {
        let shared = UserDefaults(suiteName: "group.com.coffeeaccess.app")
        return WatchEntry(date: date,
                          status: shared?.string(forKey: "watch.status") ?? "",
                          caffeine: shared?.string(forKey: "watch.caffeine") ?? "",
                          care: shared?.string(forKey: "watch.care") ?? "",
                          ready: shared?.bool(forKey: "watch.ready") ?? false,
                          arabic: shared?.object(forKey: "watch.arabic") as? Bool ?? true)
    }
}

struct WatchProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchEntry {
        WatchEntry(date: Date(), status: "جاهزة", caffeine: "120 / 400", care: "", ready: true, arabic: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : WatchEntry.load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchEntry>) -> Void) {
        completion(Timeline(entries: [WatchEntry.load()], policy: .after(Date().addingTimeInterval(1800))))
    }
}

struct WatchComplicationView: View {
    @Environment(\.widgetFamily) var family
    let entry: WatchEntry

    var body: some View {
        let title = entry.status.isEmpty ? (entry.arabic ? "افتح قهوتي" : "Open Coffee") : entry.status
        Group {
            switch family {
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: entry.ready ? "cup.and.saucer.fill" : "cup.and.saucer")
                }
            case .accessoryInline:
                Text(entry.caffeine.isEmpty ? title : "☕︎ \(entry.caffeine)")
            case .accessoryCorner:
                Image(systemName: entry.ready ? "cup.and.saucer.fill" : "cup.and.saucer")
                    .widgetLabel(entry.caffeine.isEmpty ? title : entry.caffeine)
            default:
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.headline).lineLimit(1)
                    if !entry.caffeine.isEmpty { Text(entry.caffeine).font(.caption2) }
                    if !entry.care.isEmpty { Text(entry.care).font(.caption2).lineLimit(1) }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .containerBackground(for: .widget) { Color.clear }
    }
}
