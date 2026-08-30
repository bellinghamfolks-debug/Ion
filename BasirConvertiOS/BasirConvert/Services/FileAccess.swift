import Foundation

enum FileAccess {
    static let maximumSourceBytes: Int64 = 400 * 1024 * 1024
    static let appGroupIdentifier = "group.com.basir.convert.ios"
    private static let externalImportRootName = "BasirIncoming"

    static func makeJobDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BasirJobs", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let job = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: job, withIntermediateDirectories: true)
        try protect(job, excludedFromBackup: true)
        return job
    }

    static func makePersistentJobDirectory(id: UUID) throws -> URL {
        let root = try applicationSupportDirectory()
            .appendingPathComponent("Basir Jobs", isDirectory: true)
        try createProtectedDirectory(root, excludedFromBackup: true)
        let job = root.appendingPathComponent(id.uuidString, isDirectory: true)
        try createProtectedDirectory(job, excludedFromBackup: true)
        return job
    }

    static func persistentJobsDirectory() throws -> URL {
        let root = try applicationSupportDirectory()
            .appendingPathComponent("Basir Jobs", isDirectory: true)
        try createProtectedDirectory(root, excludedFromBackup: true)
        return root
    }

    static func incomingDirectory() throws -> URL {
        let root = try applicationSupportDirectory()
            .appendingPathComponent(externalImportRootName, isDirectory: true)
        try createProtectedDirectory(root, excludedFromBackup: true)
        return root
    }

    /// Returns the shared container granted by the active signature. Some
    /// re-signing services rewrite entitlement values, so the signed
    /// entitlement is checked before the project's original identifier.
    static func sharedContainerURL() -> URL? {
        let signedGroups = runtimeApplicationGroups()
        let candidates = signedGroups + [appGroupIdentifier]
        var visited = Set<String>()
        for identifier in candidates where visited.insert(identifier).inserted {
            if let url = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: identifier
            ) {
                return url
            }
        }
        return nil
    }

    static func documentsInboxURL() -> URL? {
        guard let documents = try? FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        let inbox = documents.appendingPathComponent("Inbox", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: inbox.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        return inbox
    }

    /// Creates an app-owned copy as soon as iOS hands Basir a file from
    /// another app. This prevents a temporary provider URL from expiring while
    /// the user chooses between conversion and translation.
    static func stageExternalSource(_ source: URL) throws -> (container: URL, source: URL) {
        let root = try incomingDirectory()

        let container = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
            try protect(container, excludedFromBackup: true)
            let staged = try materializeSecurityScoped(source, into: container)
            return (container, staged)
        } catch {
            try? FileManager.default.removeItem(at: container)
            throw error
        }
    }

    static func removeExternalImportDirectory(_ directory: URL) {
        guard let root = try? incomingDirectory().standardizedFileURL else { return }
        let candidate = directory.standardizedFileURL
        guard candidate.deletingLastPathComponent() == root,
              candidate.lastPathComponent != ".",
              candidate.lastPathComponent != ".." else { return }
        try? FileManager.default.removeItem(at: candidate)
    }

    /// Copies a document-picker URL while its security-scoped permission is
    /// active. The conversion then owns a stable local file even if the source
    /// provider goes offline or iOS suspends its file-provider extension.
    static func materializeSecurityScoped(_ source: URL, into directory: URL) throws -> URL {
        let didAccess = source.startAccessingSecurityScopedResource()
        defer { if didAccess { source.stopAccessingSecurityScopedResource() } }

        let fallbackName = "document.\(source.pathExtension.isEmpty ? "bin" : source.pathExtension)"
        let name = sanitizeFilename(source.lastPathComponent.isEmpty ? fallbackName : source.lastPathComponent)
        let destination = directory.appendingPathComponent(name)
        var coordinationError: NSError?
        var copyError: Error?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: source, options: [], error: &coordinationError) { readableURL in
            do {
                let values = try readableURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard values.isRegularFile != false else {
                    throw BasirError.invalidFileContent
                }
                let byteCount = Int64(values.fileSize ?? 0)
                guard byteCount > 0 else { throw BasirError.emptyDocument }
                guard byteCount <= maximumSourceBytes else {
                    throw BasirError.fileTooLarge(byteCount)
                }
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: readableURL, to: destination)
                try protect(destination, excludedFromBackup: true)
                try validateSignature(of: destination)
            } catch {
                copyError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let copyError { throw copyError }
        return destination
    }

    static func outputDirectory() throws -> URL {
        let documents = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = documents.appendingPathComponent("Basir Outputs", isDirectory: true)
        try createProtectedDirectory(root, excludedFromBackup: false)
        return root
    }

    static func outputURL(for source: URL, options: ConversionOptions) throws -> URL {
        let root = try outputDirectory()

        var stem = options.outputName?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? source.deletingPathExtension().lastPathComponent
        stem = sanitizeFilename(stem)
        if stem.isEmpty { stem = "Basir document" }
        let suffix: String
        if options.operation == .translate, let language = options.targetLanguage {
            suffix = " (\(language.englishName))"
        } else {
            suffix = " (Word)"
        }
        var candidate = root.appendingPathComponent(stem + suffix).appendingPathExtension("docx")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = root.appendingPathComponent("\(stem)\(suffix) \(counter)").appendingPathExtension("docx")
            counter += 1
        }
        return candidate
    }

    static func listOutputs() throws -> [URL] {
        let root = try outputDirectory()
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        return try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension.lowercased() == "docx" }
        .sorted {
            let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhs > rhs
        }
    }

    static func renameOutput(_ source: URL, to proposedName: String) throws -> URL {
        let root = try outputDirectory().standardizedFileURL
        let standardized = source.standardizedFileURL
        guard standardized.deletingLastPathComponent() == root else {
            throw BasirError.invalidFileContent
        }
        var name = sanitizeFilename(proposedName)
        if name.lowercased().hasSuffix(".docx") { name.removeLast(5) }
        guard !name.isEmpty else { throw BasirError.emptyDocument }
        var destination = root.appendingPathComponent(name).appendingPathExtension("docx")
        var counter = 2
        while FileManager.default.fileExists(atPath: destination.path), destination != standardized {
            destination = root.appendingPathComponent("\(name) \(counter)").appendingPathExtension("docx")
            counter += 1
        }
        guard destination != standardized else { return standardized }
        try FileManager.default.moveItem(at: standardized, to: destination)
        let oldSidecar = sidecarURL(for: standardized)
        if FileManager.default.fileExists(atPath: oldSidecar.path) {
            try? FileManager.default.moveItem(at: oldSidecar, to: sidecarURL(for: destination))
        }
        return destination
    }

    static func deleteOutput(_ url: URL) throws {
        let root = try outputDirectory().standardizedFileURL
        let standardized = url.standardizedFileURL
        guard standardized.deletingLastPathComponent() == root else {
            throw BasirError.invalidFileContent
        }
        if FileManager.default.fileExists(atPath: standardized.path) {
            try FileManager.default.removeItem(at: standardized)
        }
        try? FileManager.default.removeItem(at: sidecarURL(for: standardized))
    }

    static func sidecarURL(for output: URL) -> URL {
        output.deletingPathExtension().appendingPathExtension("basir.json")
    }

    static func persistImportedData(_ data: Data, preferredName: String) throws -> URL {
        guard !data.isEmpty else { throw BasirError.emptyDocument }
        guard data.count <= maximumSourceBytes else { throw BasirError.fileTooLarge(Int64(data.count)) }
        let container = try incomingDirectory()
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try createProtectedDirectory(container, excludedFromBackup: true)
        let safeName = sanitizeFilename(preferredName)
        let destination = container.appendingPathComponent(safeName.isEmpty ? "image.jpg" : safeName)
        try data.write(to: destination, options: [.atomic, .completeFileProtectionUnlessOpen])
        return destination
    }

    static func diagnosticURL(for source: URL) throws -> URL {
        let documents = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = documents.appendingPathComponent("Basir Diagnostics", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try protect(root, excludedFromBackup: true)
        let stem = sanitizeFilename(source.deletingPathExtension().lastPathComponent)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let url = root.appendingPathComponent("\(stem)-\(formatter.string(from: Date())).log")
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: Data())
        }
        return url
    }

    static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "pdf": return "application/pdf"
        case "pptx": return "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        case "ppt": return "application/vnd.ms-powerpoint"
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "doc": return "application/msword"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "heic", "heif": return "image/heic"
        case "tif", "tiff": return "image/tiff"
        case "bmp": return "image/bmp"
        case "jpg", "jpeg": return "image/jpeg"
        case "m4a": return "audio/mp4"
        case "mp3": return "audio/mpeg"
        case "wav": return "audio/wav"
        case "aac": return "audio/aac"
        case "flac": return "audio/flac"
        case "ogg", "opus": return "audio/ogg"
        case "caf": return "audio/x-caf"
        case "aif", "aiff": return "audio/aiff"
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        default: return "application/octet-stream"
        }
    }

    static func sanitizeFilename(_ name: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:?%*|\"<>\n\r\t")
        let pieces = name.components(separatedBy: forbidden)
        let cleaned = pieces.joined(separator: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(cleaned.prefix(180))
    }

    static func protect(_ url: URL, excludedFromBackup: Bool) throws {
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUnlessOpen],
            ofItemAtPath: url.path
        )
        var mutableURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = excludedFromBackup
        try mutableURL.setResourceValues(values)
    }

    private static func applicationSupportDirectory() throws -> URL {
        try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
    }

    private static func createProtectedDirectory(_ url: URL, excludedFromBackup: Bool) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try protect(url, excludedFromBackup: excludedFromBackup)
    }

    private static func runtimeApplicationGroups() -> [String] {
        // Xcode 26 no longer exposes SecTask entitlement inspection to Swift.
        // FileAccess already falls back to the declared App Group identifier.
        return []
    }

    static func validateSignature(of url: URL) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let header = try handle.read(upToCount: 1_024) ?? Data()
        let extensionName = url.pathExtension.lowercased()

        let valid: Bool
        switch extensionName {
        case "pdf":
            valid = header.range(of: Data("%PDF-".utf8)) != nil
        case "pptx", "docx":
            valid = header.starts(with: [0x50, 0x4B, 0x03, 0x04])
        case "ppt", "doc":
            valid = header.starts(with: [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1])
        case "jpg", "jpeg":
            valid = header.starts(with: [0xFF, 0xD8, 0xFF])
        case "png":
            valid = header.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        case "gif":
            valid = header.starts(with: Data("GIF87a".utf8))
                || header.starts(with: Data("GIF89a".utf8))
        case "webp":
            valid = header.count >= 12
                && String(data: header.prefix(4), encoding: .ascii) == "RIFF"
                && String(data: header.dropFirst(8).prefix(4), encoding: .ascii) == "WEBP"
        case "heic", "heif":
            let brand = header.count >= 12
                ? String(data: header.dropFirst(8).prefix(4), encoding: .ascii)?.lowercased()
                : nil
            valid = header.count >= 12
                && String(data: header.dropFirst(4).prefix(4), encoding: .ascii) == "ftyp"
                && ["heic", "heix", "hevc", "hevx", "mif1", "msf1"].contains(brand ?? "")
        case "tif", "tiff":
            valid = header.starts(with: [0x49, 0x49, 0x2A, 0x00])
                || header.starts(with: [0x4D, 0x4D, 0x00, 0x2A])
        case "bmp":
            valid = header.starts(with: [0x42, 0x4D])
        case "m4a", "mp4", "mov":
            valid = header.count >= 12
                && String(data: header.dropFirst(4).prefix(4), encoding: .ascii) == "ftyp"
        case "mp3":
            valid = header.starts(with: Data("ID3".utf8))
                || (header.count >= 2 && header[0] == 0xFF && (header[1] & 0xE0) == 0xE0)
        case "wav":
            valid = header.count >= 12
                && String(data: header.prefix(4), encoding: .ascii) == "RIFF"
                && String(data: header.dropFirst(8).prefix(4), encoding: .ascii) == "WAVE"
        case "aac":
            valid = header.count >= 2 && header[0] == 0xFF && (header[1] & 0xF0) == 0xF0
        case "flac":
            valid = header.starts(with: Data("fLaC".utf8))
        case "ogg", "opus":
            valid = header.starts(with: Data("OggS".utf8))
        case "caf":
            valid = header.starts(with: Data("caff".utf8))
        case "aif", "aiff":
            valid = header.count >= 12
                && String(data: header.prefix(4), encoding: .ascii) == "FORM"
                && ["AIFF", "AIFC"].contains(String(data: header.dropFirst(8).prefix(4), encoding: .ascii) ?? "")
        default:
            valid = false
        }

        guard valid else { throw BasirError.invalidFileContent }
    }
}

