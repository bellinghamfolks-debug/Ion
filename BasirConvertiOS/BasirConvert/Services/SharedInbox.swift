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


/// YouTube links shared into Basir from another app (the share extension
/// keeps them in the app group). The newest one opens the video description.
enum SharedLinks {
    static let folderName = "SharedLinks"

    static func takeLatestVideo() -> String? {
        guard let group = FileAccess.sharedContainerURL() else { return nil }
        let folder = group.appendingPathComponent(folderName, isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { return nil }
        let newest = files.max { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return da < db
        }
        let link = newest.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        files.forEach { try? FileManager.default.removeItem(at: $0) }
        return link.flatMap(YouTubeLink.watchURL(from:))
    }
}
