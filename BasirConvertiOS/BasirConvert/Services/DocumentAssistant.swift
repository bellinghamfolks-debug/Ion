import Foundation
import EventKit

/// Questions about a finished document, answered by the server from the
/// document's own text (POST /api/assist). The text comes from the Word
/// result already on the phone; the server keeps nothing.
enum AssistTask: String, Codable, Sendable {
    case ask, brief, dates, table, image, compare, translate
}

struct AssistRequestBody: Encodable, Sendable {
    var task: AssistTask
    var language: String
    var text: String = ""
    var question: String = ""
    var table: [[String]] = []
    var otherText: String = ""
    var imageBase64: String = ""
    var imageMime: String = "image/jpeg"
    var title: String = ""
    var today: String = ""
    var segments: [String] = []
    var target: String = ""
}

struct AskAnswer: Codable, Equatable, Sendable {
    var found: Bool
    var answer: String
    var quotes: [String]
}

struct DocumentBrief: Codable, Equatable, Sendable {
    struct RequestedAction: Codable, Equatable, Sendable {
        var action: String
        var deadline: String
        var details: String
    }
    struct LabelledValue: Codable, Equatable, Sendable {
        var label: String
        var value: String
    }
    var documentType: String
    var summary: String
    var requests: [RequestedAction]
    var amounts: [LabelledValue]
    var contacts: [String]
    var documentsNeeded: [String]
    var warnings: [String]
}

struct DocumentEvent: Codable, Equatable, Identifiable, Sendable {
    var title: String
    var date: String
    var time: String
    var endTime: String
    var location: String
    var notes: String
    var quote: String
    var id: String { "\(date)|\(time)|\(title)" }

    /// The start as a date on the phone's calendar, or nil when unreadable.
    var start: Date? { Self.parse(date, time) }
    var isAllDay: Bool { time.isEmpty }

    static func parse(_ day: String, _ time: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = time.isEmpty ? "yyyy-MM-dd" : "yyyy-MM-dd HH:mm"
        return formatter.date(from: time.isEmpty ? day : "\(day) \(time)")
    }
}

struct DocumentEvents: Codable, Equatable, Sendable {
    var events: [DocumentEvent]
}

struct TableExplanation: Codable, Equatable, Sendable {
    struct Column: Codable, Equatable, Sendable {
        var name: String
        var meaning: String
    }
    var overview: String
    var columns: [Column]
    var highlights: [String]
    var totals: [String]
}

struct ImageAnswer: Codable, Equatable, Sendable {
    var answer: String
    var visibleText: String
}

struct DocumentComparison: Codable, Equatable, Sendable {
    struct Change: Codable, Equatable, Identifiable, Sendable {
        var kind: String
        var `where`: String
        var before: String
        var after: String
        var important: Bool
        var id: String { "\(kind)|\(self.where)|\(before)|\(after)" }
    }
    var summary: String
    var changes: [Change]
}

enum DocumentAssistant {
    /// Matches the server's limit; longer documents are cut at a heading.
    static let maximumCharacters = 590_000

    static func send<Result: Decodable>(_ body: AssistRequestBody, as type: Result.Type,
                                        configuration: ServerConfiguration) async throws -> Result {
        guard configuration.isConfigured else { throw BasirError.notConfigured }
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try await ProxyClient(configuration: configuration).assist(body: encoder.encode(body))
        struct Envelope<Value: Decodable>: Decodable { let result: Value }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(Envelope<Result>.self, from: data).result
        } catch {
            throw BasirError.invalidResponse("The answer could not be read.")
        }
    }

    /// The document as plain text for the server: headings marked, tables
    /// as rows, page markers kept so answers can say where things are.
    static func text(of blocks: [ReaderBlock]) -> String {
        var lines: [String] = []
        var count = 0
        for block in blocks {
            let line: String
            switch block.kind {
            case .heading(let level): line = String(repeating: "#", count: max(1, min(6, level))) + " " + block.text
            case .table: line = block.rows.map { $0.joined(separator: " | ") }.joined(separator: "\n")
            case .image: line = block.text.isEmpty ? "" : "[\(block.text)]"
            case .listItem: line = "- " + block.text
            default: line = block.text
            }
            guard !line.isEmpty else { continue }
            if count + line.count > maximumCharacters { break }
            lines.append(line)
            count += line.count + 1
        }
        return lines.joined(separator: "\n")
    }

    static func today() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    /// The reader block that holds a quoted passage, so "go to it" works.
    static func blockID(containing quote: String, in blocks: [ReaderBlock]) -> Int? {
        let needle = normalized(String(quote.prefix(60)))
        guard needle.count >= 3 else { return nil }
        return blocks.first { block in
            let haystack = block.kind == .table
                ? block.rows.map { $0.joined(separator: " ") }.joined(separator: " ")
                : block.text
            return normalized(haystack).contains(needle)
        }?.id
    }

    static func normalized(_ value: String) -> String {
        let stripped = value.unicodeScalars.filter { !(0x064B...0x0652).contains($0.value) && $0.value != 0x0640 }
        return String(String.UnicodeScalarView(stripped))
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }

    @MainActor
    static func message(for error: Error, l10n: L10n) -> String {
        if let error = error as? BasirError {
            switch error {
            case .notConfigured, .invalidServerURL, .authenticationFailed:
                return l10n.t("هذه الميزة تحتاج خادم بصير، وهو غير متاح في هذه النسخة.",
                              "This needs the Basir server, which this build cannot reach.")
            case .rateLimited:
                return l10n.t("طلبات كثيرة في وقت قصير. حاول بعد دقائق.", "Too many requests. Try again in a few minutes.")
            case .networkUnavailable:
                return l10n.t("لا يوجد اتصال بالإنترنت.", "There is no internet connection.")
            default: break
            }
        }
        if let error = error as? URLError,
           [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost].contains(error.code) {
            return l10n.t("تعذر الوصول إلى بصير. تحقق من الاتصال وحاول مرة أخرى.",
                          "Basir could not be reached. Check the connection and try again.")
        }
        return l10n.t("تعذر الحصول على إجابة الآن. حاول مرة أخرى.", "No answer right now. Please try again.")
    }
}

/// Adds the events the person chose to their calendar. Uses write-only
/// access on iOS 17 and later, so Basir never reads existing appointments.
enum CalendarWriter {
    enum Outcome: Equatable {
        case added(Int)
        case denied
        case failed
    }

    static func add(_ events: [DocumentEvent], sourceTitle: String) async -> Outcome {
        let store = EKEventStore()
        let granted: Bool
        do {
            if #available(iOS 17.0, *) {
                granted = try await store.requestWriteOnlyAccessToEvents()
            } else {
                granted = try await store.requestAccess(to: .event)
            }
        } catch {
            return .failed
        }
        guard granted, let calendar = store.defaultCalendarForNewEvents else { return .denied }
        var added = 0
        for item in events {
            guard let start = item.start else { continue }
            let event = EKEvent(eventStore: store)
            event.calendar = calendar
            event.title = item.title
            event.location = item.location.isEmpty ? nil : item.location
            event.notes = [item.notes, item.quote, sourceTitle.isEmpty ? "" : "— \(sourceTitle)"]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            if item.isAllDay {
                event.isAllDay = true
                event.startDate = start
                event.endDate = start
                // 9:00 the day before.
                event.addAlarm(EKAlarm(relativeOffset: -15 * 3600))
            } else {
                event.startDate = start
                event.endDate = DocumentEvent.parse(item.date, item.endTime) ?? start.addingTimeInterval(3600)
                event.addAlarm(EKAlarm(relativeOffset: -3600))
            }
            do {
                try store.save(event, span: .thisEvent, commit: false)
                added += 1
            } catch {
                continue
            }
        }
        do { try store.commit() } catch { return .failed }
        return .added(added)
    }
}

/// Bilingual reading: translates the paragraphs the person reaches, a batch
/// at a time, and keeps them for the session.
@MainActor
final class BilingualTranslator: ObservableObject {
    @Published private(set) var translations: [Int: String] = [:]
    @Published private(set) var failed = false
    private(set) var target = "en"
    private var pending: [Int: String] = [:]
    private var inFlight: Set<Int> = []
    private var running = false
    private var configuration: ServerConfiguration?

    func reset(target: String, configuration: ServerConfiguration) {
        self.target = target
        self.configuration = configuration
        translations = [:]
        pending = [:]
        inFlight = []
        failed = false
    }

    /// Queues a passage for translation unless it is already known.
    func need(_ id: Int, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, translations[id] == nil, !inFlight.contains(id), pending[id] == nil else { return }
        pending[id] = String(trimmed.prefix(5_500))
        pump()
    }

    private func pump() {
        guard !running, !pending.isEmpty, let configuration else { return }
        running = true
        var batch: [(Int, String)] = []
        var characters = 0
        for id in pending.keys.sorted() {
            guard let text = pending[id] else { continue }
            if batch.count >= 40 || characters + text.count > 20_000 { break }
            batch.append((id, text))
            characters += text.count
        }
        batch.forEach { pending[$0.0] = nil; inFlight.insert($0.0) }
        let target = self.target
        let batch = batch
        Task {
            defer {
                batch.forEach { inFlight.remove($0.0) }
                running = false
                pump()
            }
            do {
                struct Result: Decodable { let translations: [String] }
                var body = AssistRequestBody(task: .translate, language: target == "ar" ? "ar" : "en")
                body.segments = batch.map(\.1)
                body.target = target
                let result = try await DocumentAssistant.send(body, as: Result.self, configuration: configuration)
                guard target == self.target else { return }
                for (index, item) in batch.enumerated() where index < result.translations.count {
                    translations[item.0] = result.translations[index]
                }
            } catch {
                failed = true
                pending = [:]
            }
        }
    }
}
