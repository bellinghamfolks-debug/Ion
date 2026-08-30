import Foundation

final class DiagnosticLogger: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    private var destinationURL: URL?
    private var lastProgressSignature = ""
    private var lastNetworkSignature = ""
    private let formatter = ISO8601DateFormatter()
    private static let maximumMemoryLines = 4_000

    init(sourceName: String, options: ConversionOptions, destinationURL: URL? = nil) {
        self.destinationURL = destinationURL
        let sourceType = URL(fileURLWithPath: sourceName).pathExtension.lowercased()
        record("SESSION START sourceType=\(sourceType.isEmpty ? "unknown" : sourceType) operation=\(options.operation.rawValue) mode=\(options.encodedMode)")
        record(Self.environmentSummary())
    }

    func record(_ event: String) {
        let line = "\(formatter.string(from: Date())) \(Self.redact(event))"
        lock.lock()
        lines.append(line)
        if lines.count > Self.maximumMemoryLines {
            lines.removeFirst(lines.count - Self.maximumMemoryLines)
        }
        let destination = destinationURL
        lock.unlock()

        if let destination { Self.append(line: line, to: destination) }
        if let global = Self.globalLogURL(), global != destination {
            Self.append(line: line, to: global)
        }
    }

    func recordProgress(_ progress: ConversionProgress) {
        let byteBucket: Int64
        if progress.totalBytes > 0 {
            byteBucket = min(20, max(0, progress.transferredBytes * 20 / max(1, progress.totalBytes)))
        } else {
            byteBucket = progress.transferredBytes / (4 * 1024 * 1024)
        }
        let signature = "\(progress.stage.rawValue)|\(progress.current)|\(progress.total)|\(byteBucket)|\(progress.succeeded)|\(progress.failed)|\(progress.skipped ?? 0)|\(progress.detail ?? "")"
        lock.lock()
        let changed = signature != lastProgressSignature
        if changed { lastProgressSignature = signature }
        lock.unlock()
        guard changed else { return }
        record("PROGRESS stage=\(progress.stage.rawValue) current=\(progress.current) total=\(progress.total) transferred=\(progress.transferredBytes) totalBytes=\(progress.totalBytes) succeeded=\(progress.succeeded) failed=\(progress.failed) skipped=\(progress.skipped ?? 0) detail=\(progress.detail ?? "")")
    }

    func recordNetwork(_ snapshot: NetworkSnapshot, reason: String) {
        let signature = "\(snapshot.isConnected)|\(snapshot.usesWiFi)|\(snapshot.isExpensive)|\(snapshot.isConstrained)"
        lock.lock()
        let changed = signature != lastNetworkSignature
        if changed { lastNetworkSignature = signature }
        lock.unlock()
        guard changed else { return }
        record("NETWORK reason=\(reason) connected=\(snapshot.isConnected) wifi=\(snapshot.usesWiFi) expensive=\(snapshot.isExpensive) constrained=\(snapshot.isConstrained)")
    }

    func recordError(_ error: Error, context: String) {
        let typeName = String(reflecting: type(of: error))
        if let urlError = error as? URLError {
            record("ERROR context=\(context) type=\(typeName) urlCode=\(urlError.code.rawValue) description=\(urlError.localizedDescription)")
        } else {
            record("ERROR context=\(context) type=\(typeName) description=\(error.localizedDescription)")
        }
    }

    func write(to url: URL) throws {
        lock.lock()
        destinationURL = url
        let snapshot = lines.joined(separator: "\n") + "\n"
        lock.unlock()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(snapshot.utf8).write(to: url, options: .atomic)
    }

    static func recordGlobal(_ event: String) {
        guard let url = globalLogURL() else { return }
        let stamp = ISO8601DateFormatter().string(from: Date())
        append(line: "\(stamp) \(redact(event))", to: url)
    }

    static func globalLogURL() -> URL? {
        do {
            let documents = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let root = documents.appendingPathComponent("Basir Diagnostics", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let url = root.appendingPathComponent("Basir-live.log")
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: Data())
            }
            trimIfNeeded(url)
            return url
        } catch {
            return nil
        }
    }

    private static func environmentSummary() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let locale = Locale.current.identifier
        let freeBytes: Int64 = {
            guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
                  let number = attributes[.systemFreeSize] as? NSNumber else { return -1 }
            return number.int64Value
        }()
        return "ENV appVersion=\(version) build=\(build) os=\(os) locale=\(locale) freeDiskBytes=\(freeBytes)"
    }

    private static func append(line: String, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: Data())
            }
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data((line + "\n").utf8))
            try handle.close()
            trimIfNeeded(url)
        } catch {
            // Diagnostics must never be able to break a conversion.
        }
    }

    private static func trimIfNeeded(_ url: URL) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              size.int64Value > 2 * 1024 * 1024,
              let data = try? Data(contentsOf: url), data.count > 1024 * 1024 else { return }
        let tail = data.suffix(1024 * 1024)
        try? Data(tail).write(to: url, options: .atomic)
    }

    private static func redact(_ text: String) -> String {
        var output = text
        let home = NSHomeDirectory()
        if !home.isEmpty { output = output.replacingOccurrences(of: home, with: "[APP_HOME]") }
        output = output.replacingOccurrences(
            of: #"(?i)(x-basir-client-token|authorization|client[_-]?token)\s*[:=]\s*[^\s,;]+"#,
            with: "$1=[REDACTED]",
            options: .regularExpression
        )
        output = output.replacingOccurrences(
            of: #"(?i)([?&](?:x-goog-[^=]+|signature|credential|token|key)\s*=)[^&\s]+"#,
            with: "$1[REDACTED]",
            options: .regularExpression
        )
        return output
    }
}

