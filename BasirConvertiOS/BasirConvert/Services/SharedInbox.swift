import Foundation

enum SharedInbox {
    static let folderName = "SharedIncoming"

    static func takeAll() throws -> [URL] {
        var directories: [URL] = []
        if let group = FileAccess.sharedContainerURL() {
            let sharedInbox = group.appendingPathComponent(folderName, isDirectory: true)
            try FileManager.default.createDirectory(at: sharedInbox, withIntermediateDirectories: true)
            directories.append(sharedInbox)
        }
        if let systemInbox = FileAccess.documentsInboxURL() {
            directories.append(systemInbox)
        }

        var imported: [URL] = []
        for directory in directories {
            imported.append(contentsOf: try takeAll(from: directory))
        }
        return imported
    }

    static func takeAll(from inbox: URL) throws -> [URL] {
        let candidates = try FileManager.default.contentsOfDirectory(
            at: inbox,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ).filter { SupportedInput.operations(for: $0).isEmpty == false }

        var imported: [URL] = []
        for source in candidates {
            do {
                let staged = try FileAccess.stageExternalSource(source)
                imported.append(staged.source)
                try? FileManager.default.removeItem(at: source)
            } catch {
                continue
            }
        }
        return imported
    }
}

