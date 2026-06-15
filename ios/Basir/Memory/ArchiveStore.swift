// ArchiveStore.swift
// Lightweight Codable-backed persistent store for personal memory
// (people / products / places) and archived AI results.
//
// Why not Core Data?
//   Core Data is the iOS-idiomatic option but adds ~400 lines of
//   schema + migration setup and brings a real cost in app startup
//   time. Basir's personal-memory volume is small (dozens of entries
//   per user, not thousands), so a JSON file in the Documents
//   directory loaded once at launch is the right tool. We can swap
//   to Core Data later if entry counts ever justify it.
//
// On-disk layout
//   <Documents>/basir_archive.json
//     {
//       "people":    [Person, ...],
//       "products":  [Product, ...],
//       "places":    [Place, ...],
//       "results":   [ArchivedResult, ...],
//       "logs":      [ActivityLog, ...]
//     }
//
// Writes are atomic (write to temp + rename) so a crash mid-write
// cannot corrupt the file.

import Foundation
import Combine

// MARK: - Records

struct Person: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    var relation: String
    var notes: String
    var createdAt: Date = Date()
}

struct Product: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    var barcode: String
    var notes: String
    var createdAt: Date = Date()
}

struct Place: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    var description: String
    var notes: String
    var createdAt: Date = Date()
}

struct ArchivedResult: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var title: String
    var kind: String          // e.g. "image_describe", "translate", "math_extract"
    var text: String
    var summary: String
    var createdAt: Date = Date()
}

struct ActivityLog: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var type: String
    var content: String
    var createdAt: Date = Date()
}

// MARK: - Snapshot

private struct ArchiveSnapshot: Codable, Sendable {
    var people: [Person] = []
    var products: [Product] = []
    var places: [Place] = []
    var results: [ArchivedResult] = []
    var logs: [ActivityLog] = []
}

// MARK: - Store

@MainActor
final class ArchiveStore: ObservableObject {
    static let shared = ArchiveStore()

    @Published private(set) var people: [Person] = []
    @Published private(set) var products: [Product] = []
    @Published private(set) var places: [Place] = []
    @Published private(set) var results: [ArchivedResult] = []
    @Published private(set) var logs: [ActivityLog] = []

    /// How many activity log + archive rows we keep. Older rows are
    /// trimmed at every save() call. Matches the Android BasirDb
    /// autoTrim contract (1000 logs / 200 documents).
    static let maxLogs = 1000
    static let maxResults = 200
    private static let maximumArchiveBytes = 32 * 1_024 * 1_024
    private static let maximumResultCharacters = 100_000
    private static let maximumNoteCharacters = 20_000
    private static let maximumLogCharacters = 5_000

    private var fileURL: URL? {
        do {
            let docs = try FileManager.default.url(for: .documentDirectory,
                                                   in: .userDomainMask,
                                                   appropriateFor: nil,
                                                   create: true)
            return docs.appendingPathComponent("basir_archive.json")
        } catch {
            AppLogger.documentError("Archive directory unavailable")
            return nil
        }
    }

    private init() {
        load()
    }

    // MARK: - Mutations

    func addPerson(_ person: Person) {
        var safe = person
        safe.name = Self.clamp(person.name, to: 500)
        safe.relation = Self.clamp(person.relation, to: 500)
        safe.notes = Self.clamp(person.notes, to: Self.maximumNoteCharacters)
        people.append(safe)
        save()
    }
    func deletePerson(_ id: UUID) {
        people.removeAll { $0.id == id }
        save()
    }
    func addProduct(_ product: Product) {
        var safe = product
        safe.name = Self.clamp(product.name, to: 500)
        safe.barcode = Self.clamp(product.barcode, to: 500)
        safe.notes = Self.clamp(product.notes, to: Self.maximumNoteCharacters)
        products.append(safe)
        save()
    }
    func deleteProduct(_ id: UUID) {
        products.removeAll { $0.id == id }
        save()
    }
    func addPlace(_ place: Place) {
        var safe = place
        safe.name = Self.clamp(place.name, to: 500)
        safe.description = Self.clamp(place.description, to: Self.maximumNoteCharacters)
        safe.notes = Self.clamp(place.notes, to: Self.maximumNoteCharacters)
        places.append(safe)
        save()
    }
    func deletePlace(_ id: UUID) {
        places.removeAll { $0.id == id }
        save()
    }

    func addResult(_ result: ArchivedResult) {
        guard BasirSettings.shared.autoSaveResults else { return }
        var safe = result
        safe.title = Self.clamp(result.title, to: 1_000)
        safe.kind = Self.clamp(result.kind, to: 100)
        safe.text = Self.clamp(result.text, to: Self.maximumResultCharacters)
        safe.summary = Self.clamp(result.summary, to: 2_000)
        results.insert(safe, at: 0)
        save()
    }
    func deleteResult(_ id: UUID) {
        results.removeAll { $0.id == id }
        save()
    }

    func appendLog(type: String, content: String) {
        guard !BasirSettings.shared.privacyMode else { return }
        logs.insert(ActivityLog(
            type: Self.clamp(type, to: 100),
            content: Self.clamp(content, to: Self.maximumLogCharacters)
        ), at: 0)
        save()
    }
    func clearLogs() {
        logs.removeAll()
        save()
    }

    /// Wipe all locally stored data (saved items, results, history).
    func clearAll() {
        people.removeAll()
        products.removeAll()
        places.removeAll()
        results.removeAll()
        logs.removeAll()
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let fileURL,
              let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true,
              let size = values.fileSize, size > 0, size <= Self.maximumArchiveBytes,
              let data = try? Data(contentsOf: fileURL, options: [.mappedIfSafe]),
              let snapshot = try? JSONDecoder.iso.decode(ArchiveSnapshot.self, from: data) else {
            return
        }
        self.people = Array(snapshot.people.prefix(1_000)).map(Self.sanitized)
        self.products = Array(snapshot.products.prefix(1_000)).map(Self.sanitized)
        self.places = Array(snapshot.places.prefix(1_000)).map(Self.sanitized)
        self.results = Array(snapshot.results.prefix(Self.maxResults)).map(Self.sanitized)
        self.logs = Array(snapshot.logs.prefix(Self.maxLogs)).map(Self.sanitized)
    }

    private func save() {
        // Apply trim policy.
        if logs.count > Self.maxLogs {
            logs = Array(logs.prefix(Self.maxLogs))
        }
        if results.count > Self.maxResults {
            results = Array(results.prefix(Self.maxResults))
        }
        let snapshot = ArchiveSnapshot(
            people: people,
            products: products,
            places: places,
            results: results,
            logs: logs
        )
        guard let fileURL else { return }
        do {
            let data = try JSONEncoder.iso.encode(snapshot)
            guard data.count <= Self.maximumArchiveBytes else {
                AppLogger.documentError("Archive save skipped because it exceeded the safe limit")
                return
            }
            // Foundation writes to a sibling temporary file and replaces the
            // destination atomically, avoiding a delete-then-move loss window.
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        } catch {
            AppLogger.documentError("Archive save failed")
        }
    }

    private static func clamp(_ value: String, to limit: Int) -> String {
        value.count <= limit ? value : String(value.prefix(limit))
    }

    private static func sanitized(_ value: Person) -> Person {
        var copy = value
        copy.name = clamp(copy.name, to: 500)
        copy.relation = clamp(copy.relation, to: 500)
        copy.notes = clamp(copy.notes, to: maximumNoteCharacters)
        return copy
    }

    private static func sanitized(_ value: Product) -> Product {
        var copy = value
        copy.name = clamp(copy.name, to: 500)
        copy.barcode = clamp(copy.barcode, to: 500)
        copy.notes = clamp(copy.notes, to: maximumNoteCharacters)
        return copy
    }

    private static func sanitized(_ value: Place) -> Place {
        var copy = value
        copy.name = clamp(copy.name, to: 500)
        copy.description = clamp(copy.description, to: maximumNoteCharacters)
        copy.notes = clamp(copy.notes, to: maximumNoteCharacters)
        return copy
    }

    private static func sanitized(_ value: ArchivedResult) -> ArchivedResult {
        var copy = value
        copy.title = clamp(copy.title, to: 1_000)
        copy.kind = clamp(copy.kind, to: 100)
        copy.text = clamp(copy.text, to: maximumResultCharacters)
        copy.summary = clamp(copy.summary, to: 2_000)
        return copy
    }

    private static func sanitized(_ value: ActivityLog) -> ActivityLog {
        var copy = value
        copy.type = clamp(copy.type, to: 100)
        copy.content = clamp(copy.content, to: maximumLogCharacters)
        return copy
    }
}

// MARK: - Codable helpers

private extension JSONEncoder {
    static let iso: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
}

private extension JSONDecoder {
    static let iso: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
