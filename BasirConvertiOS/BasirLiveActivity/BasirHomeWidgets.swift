import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Latest result widget (Home Screen and Lock Screen)

struct LatestResultEntry: TimelineEntry {
    let date: Date
    let snapshot: LatestResultSnapshot?
}

struct LatestResultProvider: TimelineProvider {
    func placeholder(in context: Context) -> LatestResultEntry {
        LatestResultEntry(date: Date(), snapshot: LatestResultSnapshot(
            fileName: "تقرير", createdAt: Date(), isTranslation: false, isArabic: true))
    }

    func getSnapshot(in context: Context, completion: @escaping (LatestResultEntry) -> Void) {
        completion(LatestResultEntry(date: Date(), snapshot: LatestResultSnapshot.load() ?? placeholder(in: context).snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LatestResultEntry>) -> Void) {
        // The app reloads the widget when a result arrives; the hourly
        // refresh only keeps "2 hours ago" honest.
        let entry = LatestResultEntry(date: Date(), snapshot: LatestResultSnapshot.load())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(3600))))
    }
}

private struct LatestResultTexts {
    let isArabic: Bool
    func t(_ arabic: String, _ english: String) -> String { isArabic ? arabic : english }

    var title: String { t("آخر نتيجة", "Latest result") }
    var empty: String { t("لا توجد نتيجة بعد", "No result yet") }
    var scan: String { t("صوّر مستندًا", "Scan a page") }

    func age(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: isArabic ? "ar" : "en")
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    func kind(_ snapshot: LatestResultSnapshot) -> String {
        snapshot.isTranslation ? t("ترجمة", "Translation") : t("تحويل", "Conversion")
    }
}

struct LatestResultWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LatestResultEntry
    private let accent = Color(red: 0.36, green: 0.86, blue: 1.00)

    private var texts: LatestResultTexts {
        LatestResultTexts(isArabic: entry.snapshot?.isArabic
                          ?? (Locale.current.language.languageCode?.identifier == "ar"))
    }

    var body: some View {
        content
            .environment(\.layoutDirection, texts.isArabic ? .rightToLeft : .leftToRight)
            .widgetURL(entry.snapshot == nil ? BasirLink.scan.url : BasirLink.latest.url)
            .modifier(WidgetBackground())
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryInline:
            if let snapshot = entry.snapshot {
                Label(snapshot.fileName, systemImage: "doc.richtext")
            } else {
                Label(texts.scan, systemImage: "doc.viewfinder")
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(texts.title).font(.caption2.weight(.semibold))
                if let snapshot = entry.snapshot {
                    Text(snapshot.fileName).font(.headline).lineLimit(2)
                    Text(texts.age(snapshot.createdAt)).font(.caption2)
                } else {
                    Text(texts.empty).font(.headline)
                }
            }
            .accessibilityElement(children: .combine)
        default:
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: entry.snapshot == nil ? "doc.viewfinder" : "doc.richtext.fill")
                    .font(.title2)
                    .foregroundStyle(accent)
                    .accessibilityHidden(true)
                Text(texts.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let snapshot = entry.snapshot {
                    Text(snapshot.fileName)
                        .font(.headline)
                        .lineLimit(3)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    Text("\(texts.kind(snapshot)) · \(texts.age(snapshot.createdAt))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    Text(texts.empty).font(.headline)
                    Spacer(minLength: 0)
                    Text(texts.scan).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityElement(children: .combine)
            .accessibilityHint(entry.snapshot == nil ? texts.t("يفتح الكاميرا الموجّهة", "Opens the guided camera")
                                                     : texts.t("يفتحها في قارئ بصير", "Opens it in Basir's reader"))
        }
    }
}

/// iOS 17 requires a container background; iOS 16 draws its own.
private struct WidgetBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.containerBackground(for: .widget) { Color(.systemBackground) }
        } else {
            content.padding()
        }
    }
}

struct BasirLatestResultWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: LatestResultSnapshot.widgetKind, provider: LatestResultProvider()) { entry in
            LatestResultWidgetView(entry: entry)
        }
        .configurationDisplayName("بصير — آخر نتيجة")
        .description("Latest Basir result · آخر ملف حوّله بصير، يُفتح في القارئ مباشرة.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Control Center, Lock Screen and Action button (iOS 18)

@available(iOS 18.0, *)
struct BasirScanControl: ControlWidget {
    private static var isArabic: Bool { Locale.current.language.languageCode?.identifier == "ar" }

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.basir.convert.ios.control.scan") {
            ControlWidgetButton(action: StartGuidedCaptureIntent()) {
                Label(Self.isArabic ? "صوّر مستندًا" : "Scan a page", systemImage: "doc.viewfinder")
            }
        }
        .displayName(LocalizedStringResource(String.LocalizationValue(Self.isArabic ? "بصير: صوّر مستندًا" : "Basir: Scan a page")))
        .description(LocalizedStringResource(String.LocalizationValue(Self.isArabic
            ? "يفتح الكاميرا الموجّهة بالصوت مباشرة."
            : "Opens Basir's voice-guided camera directly.")))
    }
}

@available(iOS 18.0, *)
struct BasirReadLatestControl: ControlWidget {
    private static var isArabic: Bool { Locale.current.language.languageCode?.identifier == "ar" }

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.basir.convert.ios.control.read") {
            ControlWidgetButton(action: ReadLatestResultIntent()) {
                Label(Self.isArabic ? "اقرأ آخر نتيجة" : "Read latest", systemImage: "text.book.closed")
            }
        }
        .displayName(LocalizedStringResource(String.LocalizationValue(Self.isArabic ? "بصير: اقرأ آخر نتيجة" : "Basir: Read latest result")))
        .description(LocalizedStringResource(String.LocalizationValue(Self.isArabic
            ? "يفتح آخر ملف في قارئ بصير من حيث توقفت."
            : "Opens the latest file in Basir's reader where you stopped.")))
    }
}
