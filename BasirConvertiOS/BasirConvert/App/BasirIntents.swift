import AppIntents
import Foundation
import SwiftUI

/// What a Siri shortcut asked the app to do once it is in the foreground.
enum IntentAction: Equatable {
    case chooseFile(OperationKind)
    case openLatestResult
    case readLatestResult
    case guidedCapture
}

/// Bridges App Intents (which run in the app process because they open the
/// app) to the SwiftUI views that carry them out.
@MainActor
final class IntentRouter: ObservableObject {
    static let shared = IntentRouter()

    @Published var pendingAction: IntentAction?
    @Published var pendingFiles: [URL] = []
    /// Set when a notification for a specific task is tapped.
    @Published var pendingJobID: UUID?

    private init() {}
}

struct ConvertLatestFileIntent: AppIntent {
    static var title: LocalizedStringResource = "Convert a File with Basir"
    static var description = IntentDescription(
        "Opens the file picker in Basir so you can choose a file to convert."
    )
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentRouter.shared.pendingAction = .chooseFile(.convert)
        return .result()
    }
}

struct TranslateFileIntent: AppIntent {
    static var title: LocalizedStringResource = "Translate a File with Basir"
    static var description = IntentDescription(
        "Opens the file picker in Basir so you can choose a document to translate."
    )
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentRouter.shared.pendingAction = .chooseFile(.translate)
        return .result()
    }
}

struct OpenLatestResultIntent: AppIntent {
    static var title: LocalizedStringResource = "Open the Latest Basir Result"
    static var description = IntentDescription("Opens the most recent Word file Basir created.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentRouter.shared.pendingAction = .openLatestResult
        return .result()
    }
}

/// Accepts a file passed from a Shortcuts automation, for example
/// "Get latest file" followed by this action.
struct SendFileToBasirIntent: AppIntent {
    static var title: LocalizedStringResource = "Send File to Basir"
    static var description = IntentDescription(
        "Sends a file to Basir, where you can choose conversion or translation for supported formats."
    )
    static var openAppWhenRun: Bool = true

    @Parameter(title: "File", supportedTypeIdentifiers: [
        "com.adobe.pdf", "public.image", "public.audio", "public.movie",
        "org.openxmlformats.presentationml.presentation", "com.microsoft.powerpoint.ppt",
        "org.openxmlformats.wordprocessingml.document", "com.microsoft.word.doc"
    ])
    var file: IntentFile

    @MainActor
    func perform() async throws -> some IntentResult {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BasirIntent-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = file.filename.isEmpty ? "Document" : (file.filename as NSString).lastPathComponent
        let destination = directory.appendingPathComponent(name)
        try file.data.write(to: destination, options: .atomic)
        IntentRouter.shared.pendingFiles.append(destination)
        return .result()
    }
}

struct BasirShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ConvertLatestFileIntent(),
            phrases: [
                "Convert the last file with \(.applicationName)",
                "Convert a file with \(.applicationName)",
                "حوّل آخر ملف ب\(.applicationName)"
            ]
        )
        AppShortcut(
            intent: OpenLatestResultIntent(),
            phrases: [
                "Open the last result in \(.applicationName)",
                "Open my latest \(.applicationName) file",
                "افتح آخر نتيجة في \(.applicationName)"
            ]
        )
        AppShortcut(
            intent: StartGuidedCaptureIntent(),
            phrases: [
                "Scan a document with \(.applicationName)",
                "صوّر مستندًا ب\(.applicationName)"
            ]
        )
        AppShortcut(
            intent: ReadLatestResultIntent(),
            phrases: [
                "Read my latest \(.applicationName) result",
                "اقرأ آخر نتيجة في \(.applicationName)"
            ]
        )
        AppShortcut(
            intent: TranslateFileIntent(),
            phrases: [
                "Translate a file with \(.applicationName)",
                "ترجم ملفًا ب\(.applicationName)"
            ]
        )
    }
}
