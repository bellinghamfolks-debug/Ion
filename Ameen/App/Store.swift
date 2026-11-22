import SwiftUI
import UniformTypeIdentifiers
import AVFoundation
import UIKit

@MainActor
final class LedgerStore: ObservableObject {
    @Published private(set) var book = Book()
    @Published private(set) var loadError: String?
    private let file: URL
    init() {
        file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Ameen/ledger.json")
        reload()
    }
    func reload() {
        do {
            let data = try Data(contentsOf: file)
            let value = try JSONDecoder().decode(Book.self, from: data)
            try value.validate()
            book = value
            loadError = nil
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            book = Book()
            loadError = nil
        } catch { loadError = BookError.locked.localizedDescription }
    }
    private func save(_ value: Book) throws {
        try value.validate()
        let data = try JSONEncoder().encode(value)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: [.atomic, .completeFileProtection])
        book = value
        loadError = nil
    }
    func update(_ change: (inout Book) throws -> Void) throws {
        guard loadError == nil else { throw BookError.locked }
        var next = book
        try change(&next)
        try save(next)
    }
    func restore(_ value: Book) throws { try save(value) }
}
struct Backup: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let book: Book
    init(_ book: Book) { self.book = book }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw BookError.invalid }
        book = try JSONDecoder().decode(Book.self, from: data)
        try book.validate()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try JSONEncoder().encode(book))
    }
}
@MainActor
enum Feedback {
    private static var player: AVAudioPlayer?
    static func saved(_ message: String, payment: Bool = false) {
        if UserDefaults.standard.object(forKey: "sounds") as? Bool ?? true,
           let url = Bundle.main.url(forResource: payment ? "settled" : "saved", withExtension: "wav") {
            player = try? AVAudioPlayer(contentsOf: url)
            player?.play()
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        UIAccessibility.post(notification: .announcement, argument: message)
    }
}
