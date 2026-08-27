#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()


def load(rel: str) -> str:
    return (root / rel).read_text(encoding="utf-8")


def save(rel: str, text: str) -> None:
    (root / rel).write_text(text, encoding="utf-8")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


# A persistent logger: every event is appended immediately to the per-job log
# and to one rolling app-wide log. It deliberately redacts tokens, signed-query
# values and the app container path before anything can be shared.
diagnostic_swift = r'''import Foundation

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
        record("SESSION START sourceType=\(sourceType.isEmpty ? \"unknown\" : sourceType) operation=\(options.operation.rawValue) mode=\(options.encodedMode)")
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
        let signature = "\(progress.stage.rawValue)|\(progress.current)|\(progress.total)|\(byteBucket)|\(progress.succeeded)|\(progress.failed)|\(progress.detail ?? \"\")"
        lock.lock()
        let changed = signature != lastProgressSignature
        if changed { lastProgressSignature = signature }
        lock.unlock()
        guard changed else { return }
        record("PROGRESS stage=\(progress.stage.rawValue) current=\(progress.current) total=\(progress.total) transferred=\(progress.transferredBytes) totalBytes=\(progress.totalBytes) succeeded=\(progress.succeeded) failed=\(progress.failed) detail=\(progress.detail ?? \"\")")
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
'''
save("BasirConvert/Services/DiagnosticLogger.swift", diagnostic_swift)

# Ensure diagnostic files exist as soon as a task is queued, so they can be
# shared while the task is still running or waiting.
rel = "BasirConvert/Services/FileAccess.swift"
s = load(rel)
s = replace_once(
    s,
    '        return root.appendingPathComponent("\\(stem)-\\(formatter.string(from: Date())).log")\n',
    '        let url = root.appendingPathComponent("\\(stem)-\\(formatter.string(from: Date())).log")\n        if !FileManager.default.fileExists(atPath: url.path) {\n            FileManager.default.createFile(atPath: url.path, contents: Data())\n        }\n        return url\n',
    "create diagnostic file early",
)
save(rel, s)

# App lifecycle, queue state, network changes and progress are recorded in the
# same live logger. The global log also catches failures before a job logger is
# available (for example source staging/import errors).
rel = "BasirConvert/ViewModels/AppViewModel.swift"
s = load(rel)
s = replace_once(
    s,
    '    private var networkLossTask: Task<Void, Never>?\n',
    '    private var networkLossTask: Task<Void, Never>?\n    private var activeLogger: DiagnosticLogger?\n',
    "active logger property",
)
s = replace_once(
    s,
    '        self.outputLibrary = outputLibrary\n        lastConfiguration = settings.configuration\n',
    '        self.outputLibrary = outputLibrary\n        DiagnosticLogger.recordGlobal("APP attached notifications=\\(settings.notificationsEnabled) automaticResume=\\(settings.automaticResume) wifiOnly=\\(settings.wifiOnly) allowLowData=\\(settings.allowLowData)")\n        lastConfiguration = settings.configuration\n',
    "app attach diagnostic",
)
s = s.replace(
    '            } catch {\n                self?.externalImportError = error.localizedDescription\n            }\n',
    '            } catch {\n                DiagnosticLogger.recordGlobal("IMPORT shared-inbox failed type=\\(String(reflecting: type(of: error))) description=\\(error.localizedDescription)")\n                self?.externalImportError = error.localizedDescription\n            }\n',
    1,
)
s = s.replace(
    '            } catch {\n                self?.externalImportTask = nil\n                self?.externalImportError = Self.localized(error, l10n: l10n)\n            }\n',
    '            } catch {\n                DiagnosticLogger.recordGlobal("IMPORT staging failed type=\\(String(reflecting: type(of: error))) description=\\(error.localizedDescription)")\n                self?.externalImportTask = nil\n                self?.externalImportError = Self.localized(error, l10n: l10n)\n            }\n',
    1,
)
s = s.replace(
    '                } catch {\n                    externalImportError = Self.localized(error, l10n: l10n)\n                }\n',
    '                } catch {\n                    DiagnosticLogger.recordGlobal("QUEUE source-prepare failed type=\\(String(reflecting: type(of: error))) description=\\(error.localizedDescription)")\n                    externalImportError = Self.localized(error, l10n: l10n)\n                }\n',
    1,
)
s = replace_once(
    s,
    '''            let logger = DiagnosticLogger(
                sourceName: snapshot.sourceName,
                options: snapshot.options
            )
''',
    '''            let logger = DiagnosticLogger(
                sourceName: snapshot.sourceName,
                options: snapshot.options,
                destinationURL: snapshot.diagnosticURL
            )
            activeLogger = logger
            logger.record("JOB appJob=\\(jobID.uuidString) clientRequest=\\(snapshot.requestID) status=running")
            if let metadata = snapshot.sourceMetadata {
                logger.record("SOURCE contentType=\\(metadata.contentType) bytes=\\(metadata.byteCount) items=\\(metadata.itemCount ?? -1) pixels=\\(metadata.pixelWidth ?? -1)x\\(metadata.pixelHeight ?? -1) checksumPrefix=\\((metadata.checksum ?? \"none\").prefix(16))")
            }
            logger.recordNetwork(NetworkMonitor.shared.snapshot, reason: "job-start")
''',
    "logger initialization",
)
s = replace_once(
    s,
    '        jobs[index].progress = update\n        jobs[index].updatedAt = Date()\n',
    '        jobs[index].progress = update\n        activeLogger?.recordProgress(update)\n        jobs[index].updatedAt = Date()\n',
    "progress diagnostic",
)
s = s.replace(
    '        logger?.record("FAILED error=\\(error.localizedDescription)")\n',
    '        logger?.recordError(error, context: "job-finish")\n        DiagnosticLogger.recordGlobal("JOB failed appJob=\\(jobID.uuidString) type=\\(String(reflecting: type(of: error))) description=\\(error.localizedDescription)")\n',
    1,
)
s = replace_once(
    s,
    '        if allowNext { processNextIfPossible() }\n',
    '        activeLogger = nil\n        if allowNext { processNextIfPossible() }\n',
    "clear active logger",
)
s = replace_once(
    s,
    '    private func networkDidChange(_ snapshot: NetworkSnapshot) {\n',
    '    private func networkDidChange(_ snapshot: NetworkSnapshot) {\n        DiagnosticLogger.recordGlobal("NETWORK connected=\\(snapshot.isConnected) wifi=\\(snapshot.usesWiFi) expensive=\\(snapshot.isExpensive) constrained=\\(snapshot.isConstrained)")\n        activeLogger?.recordNetwork(snapshot, reason: "path-change")\n',
    "network diagnostic",
)
s = s.replace(
    '        pauseRequested = true\n',
    '        activeLogger?.record("USER pause requested")\n        pauseRequested = true\n',
    1,
)
s = s.replace(
    '        let wasRunning = jobs[index].status == .running\n',
    '        let wasRunning = jobs[index].status == .running\n        activeLogger?.record("USER cancel requested status=\\(jobs[index].status.rawValue)")\n',
    1,
)
save(rel, s)

# End-to-end request diagnostics. We log HTTP phase/status, safe source metadata,
# service-side progress transitions, transfer fallback use, result size/type and
# validation. No authentication value or signed URL query is ever logged.
rel = "BasirConvert/Services/ProxyClient.swift"
s = load(rel)
s = replace_once(
    s,
    '        let serverStatus = try await testConnection()\n',
    '''        logger.record("PREFLIGHT begin")
        let serverStatus: BasirServerStatus
        do {
            serverStatus = try await testConnection()
            logger.record("PREFLIGHT ok apiVersion=\\(serverStatus.apiVersion) latencyMs=\\(serverStatus.latencyMilliseconds) capabilities=\\(serverStatus.capabilities.sorted().joined(separator: ","))")
        } catch {
            logger.recordError(error, context: "preflight")
            throw error
        }
''',
    "preflight diagnostic",
)
s = replace_once(
    s,
    '        let sourceSize = Int64((try? sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)\n',
    '        let sourceSize = Int64((try? sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)\n        logger.record("SOURCE prepared extension=\\(sourceURL.pathExtension.lowercased()) mime=\\(FileAccess.mimeType(for: sourceURL)) bytes=\\(sourceSize) sha256Prefix=\\(checksum.prefix(16))")\n',
    "source metadata diagnostic",
)
s = s.replace(
    '        let (creationData, creationResponse) = try await retryingData(request: createRequest)\n        try Self.validateHTTP(creationResponse, data: creationData)\n',
    '        let (creationData, creationResponse) = try await retryingData(request: createRequest, logger: logger, phase: "create")\n        logger.record("HTTP create finalStatus=\\(creationResponse.statusCode) bytes=\\(creationData.count)")\n        try Self.validateHTTP(creationResponse, data: creationData)\n',
    1,
)
s = replace_once(
    s,
    '''        try await uploadInChunks(
            sourceURL: sourceURL,
            created: created,
            totalBytes: sourceSize
        ) { sent in
''',
    '''        logger.record("UPLOAD begin bytes=\\(sourceSize)")
        try await uploadInChunks(
            sourceURL: sourceURL,
            created: created,
            totalBytes: sourceSize,
            logger: logger
        ) { sent in
''',
    "upload call diagnostic",
)
s = s.replace(
    '        }\n\n        var commit = URLRequest',
    '        }\n        logger.record("UPLOAD complete bytes=\\(sourceSize)")\n\n        var commit = URLRequest',
    1,
)
s = s.replace(
    '        let (commitData, commitResponse) = try await retryingData(request: commit)\n        try Self.validateHTTP(commitResponse, data: commitData)\n',
    '        let (commitData, commitResponse) = try await retryingData(request: commit, logger: logger, phase: "commit")\n        logger.record("HTTP commit finalStatus=\\(commitResponse.statusCode) bytes=\\(commitData.count)")\n        try Self.validateHTTP(commitResponse, data: commitData)\n',
    1,
)
s = s.replace(
    '            let (statusData, statusResponse) = try await retryingData(request: statusRequest)\n',
    '            let (statusData, statusResponse) = try await retryingData(request: statusRequest, logger: logger, phase: "status")\n',
    1,
)
s = replace_once(
    s,
    '''            if serverProgress != lastServerProgress {
                lastServerProgress = serverProgress
                progress(serverProgress)
            }
''',
    '''            if serverProgress != lastServerProgress {
                lastServerProgress = serverProgress
                logger.record("STATUS state=\\(state) current=\\(current) total=\\(total) succeeded=\\(succeeded) failed=\\(failedItems.count) skipped=\\(skippedItems.count) detail=\\(serverProgress.detail ?? \"\")")
                progress(serverProgress)
            }
''',
    "status transition diagnostic",
)
s = s.replace(
    '            if ["failed", "cancelled", "canceled"].contains(state) {\n                throw BasirError.conversionFailed(\n',
    '            if ["failed", "cancelled", "canceled"].contains(state) {\n                logger.record("STATUS terminalFailure state=\\(state) error=\\((object?[\"error\"] as? String) ?? \"missing\")")\n                throw BasirError.conversionFailed(\n',
    1,
)
s = s.replace(
    '        let (temporary, downloadResponse) = try await downloadResult(\n            request: download\n',
    '        logger.record("DOWNLOAD begin direct=\\(resultURL.host != base.host)")\n        let (temporary, downloadResponse) = try await downloadResult(\n            request: download, logger: logger\n',
    1,
)
s = replace_once(
    s,
    '        try validateDownloadedHTTP(downloadResponse, temporary: temporary)\n        try validateResultResponse(downloadResponse)\n        try verifyAndMove(temporary: temporary, response: downloadResponse, outputURL: outputURL)\n',
    '''        let downloadedBytes = Int64((try? temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        logger.record("DOWNLOAD response status=\\(downloadResponse.statusCode) bytes=\\(downloadedBytes) contentType=\\(downloadResponse.value(forHTTPHeaderField: \"Content-Type\") ?? \"missing\") contentLength=\\(downloadResponse.value(forHTTPHeaderField: \"Content-Length\") ?? \"missing\") checksumHeader=\\(downloadResponse.value(forHTTPHeaderField: \"X-Content-SHA256\") != nil)")
        try validateDownloadedHTTP(downloadResponse, temporary: temporary)
        try validateResultResponse(downloadResponse)
        logger.record("RESULT validating DOCX")
        try verifyAndMove(temporary: temporary, response: downloadResponse, outputURL: outputURL)
        let finalBytes = Int64((try? outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        logger.record("RESULT valid bytes=\\(finalBytes)")
''',
    "download validation diagnostic",
)
s = replace_once(
    s,
    '''    private func uploadInChunks(
        sourceURL: URL,
        created: JobCreationResponse,
        totalBytes: Int64,
        progress: @escaping @Sendable (Int64) -> Void
''',
    '''    private func uploadInChunks(
        sourceURL: URL,
        created: JobCreationResponse,
        totalBytes: Int64,
        logger: DiagnosticLogger,
        progress: @escaping @Sendable (Int64) -> Void
''',
    "upload signature logger",
)
s = s.replace(
    '            let (data, response) = try await retryingBackgroundUpload(\n                request: request,\n                fileURL: chunkURL\n',
    '            logger.record("UPLOAD chunk offset=\\(chunkOffset) end=\\(end) bytes=\\(chunk.count)")\n            let (data, response) = try await retryingBackgroundUpload(\n                request: request,\n                fileURL: chunkURL,\n                logger: logger\n',
    1,
)
s = replace_once(
    s,
    '''    private func retryingBackgroundUpload(
        request: URLRequest,
        fileURL: URL,
        progress: @escaping @Sendable (Int64, Int64) -> Void
''',
    '''    private func retryingBackgroundUpload(
        request: URLRequest,
        fileURL: URL,
        logger: DiagnosticLogger,
        progress: @escaping @Sendable (Int64, Int64) -> Void
''',
    "background upload logger signature",
)
s = s.replace(
    '                } catch let urlError as URLError where Self.isBackgroundFileStagingError(urlError) {\n',
    '                } catch let urlError as URLError where Self.isBackgroundFileStagingError(urlError) {\n                    logger.record("UPLOAD background-transfer fallback urlCode=\\(urlError.code.rawValue)")\n',
    1,
)
s = s.replace(
    '                if Self.retryableCodes.contains(result.1.statusCode), attempt < 3 {\n',
    '                logger.record("UPLOAD attempt=\\(attempt + 1) status=\\(result.1.statusCode) responseBytes=\\(result.0.count)")\n                if Self.retryableCodes.contains(result.1.statusCode), attempt < 3 {\n',
    1,
)
s = s.replace(
    '            } catch {\n                lastError = error\n                guard attempt < 3, Self.isRetryable(error) else { throw error }\n',
    '            } catch {\n                logger.recordError(error, context: "upload attempt \\(attempt + 1)")\n                lastError = error\n                guard attempt < 3, Self.isRetryable(error) else { throw error }\n',
    1,
)
s = replace_once(
    s,
    '''    private func downloadResult(
        request: URLRequest,
        progress: @escaping @Sendable (Int64, Int64) -> Void
''',
    '''    private func downloadResult(
        request: URLRequest,
        logger: DiagnosticLogger,
        progress: @escaping @Sendable (Int64, Int64) -> Void
''',
    "download logger signature",
)
s = s.replace(
    '        } catch let urlError as URLError where Self.isBackgroundFileStagingError(urlError) {\n            let (temporary, response) = try await session.download(for: request)\n',
    '        } catch let urlError as URLError where Self.isBackgroundFileStagingError(urlError) {\n            logger.record("DOWNLOAD background-transfer fallback urlCode=\\(urlError.code.rawValue)")\n            let (temporary, response) = try await session.download(for: request)\n',
    1,
)
s = replace_once(
    s,
    '    private func retryingData(request: URLRequest) async throws -> (Data, HTTPURLResponse) {\n',
    '    private func retryingData(request: URLRequest, logger: DiagnosticLogger? = nil, phase: String = "request") async throws -> (Data, HTTPURLResponse) {\n',
    "retrying data logger signature",
)
s = s.replace(
    '                if Self.retryableCodes.contains(http.statusCode), attempt < 3 {\n',
    '                logger?.record("HTTP phase=\\(phase) attempt=\\(attempt + 1) status=\\(http.statusCode) bytes=\\(data.count) path=\\(request.url?.path ?? \"unknown\")")\n                if Self.retryableCodes.contains(http.statusCode), attempt < 3 {\n',
    1,
)
# The second generic catch belongs to retryingData after the first replacement above.
needle = '''            } catch {
                lastError = error
                guard attempt < 3, Self.isRetryable(error) else { throw error }
                try await Self.wait(attempt: attempt, response: nil)
            }
        }
        throw lastError ?? BasirError.conversionFailed("Request failed after retries.")
'''
replacement = '''            } catch {
                logger?.recordError(error, context: "HTTP \\(phase) attempt \\(attempt + 1)")
                lastError = error
                guard attempt < 3, Self.isRetryable(error) else { throw error }
                try await Self.wait(attempt: attempt, response: nil)
            }
        }
        throw lastError ?? BasirError.conversionFailed("Request failed after retries.")
'''
s = replace_once(s, needle, replacement, "retrying data error diagnostic")
# Dynamic client version makes Cloud logs correlate with the actual installed IPA.
s = replace_once(
    s,
    '''        request.setValue("Basir-iOS/2.1.0", forHTTPHeaderField: "User-Agent")
        request.setValue(requestID, forHTTPHeaderField: "X-Request-ID")
        request.setValue(requestID, forHTTPHeaderField: "Idempotency-Key")
        request.setValue("2.1", forHTTPHeaderField: "X-Basir-Client-Version")
''',
    '''        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        request.setValue("Basir-iOS/\\(version) (\\(build))", forHTTPHeaderField: "User-Agent")
        request.setValue(requestID, forHTTPHeaderField: "X-Request-ID")
        request.setValue(requestID, forHTTPHeaderField: "Idempotency-Key")
        request.setValue(version, forHTTPHeaderField: "X-Basir-Client-Version")
''',
    "dynamic client version",
)
save(rel, s)

# The task screen can share the live log during every state, not only after a
# failure/completion. VoiceOver gets a clear, stable action label.
rel = "BasirConvert/Views/JobView.swift"
s = load(rel)
s = replace_once(
    s,
    '''            HStack {
                Button { viewModel.pause() } label: {
''',
    '''            helpLink
            HStack {
                Button { viewModel.pause() } label: {
''',
    "running diagnostics link",
)
s = replace_once(
    s,
    '''            .buttonStyle(.borderedProminent).tint(BasirPalette.cyan)
        }
        .glassSurface(accent: .orange)
    }

    private var pausedContent''',
    '''            .buttonStyle(.borderedProminent).tint(BasirPalette.cyan)
            helpLink
        }
        .glassSurface(accent: .orange)
    }

    private var pausedContent''',
    "waiting diagnostics link",
)
s = replace_once(
    s,
    '''            .buttonStyle(.bordered).tint(.red)
        }
        .glassSurface(accent: .orange)
    }

    private func completedContent''',
    '''            .buttonStyle(.bordered).tint(.red)
            helpLink
        }
        .glassSurface(accent: .orange)
    }

    private func completedContent''',
    "paused diagnostics link",
)
s = replace_once(
    s,
    '''        if let diagnostic = viewModel.diagnosticURL {
            ShareLink(item: diagnostic) {
                Label(l10n.t("مشاركة معلومات المساعدة", "Share support information"), systemImage: "lifepreserver")
            }
            .buttonStyle(.bordered).tint(BasirPalette.cyan)
        }
''',
    '''        if let diagnostic = viewModel.diagnosticURL {
            VStack(alignment: .leading, spacing: 6) {
                ShareLink(item: diagnostic) {
                    Label(l10n.t("مشاركة سجل التشخيص", "Share diagnostic log"), systemImage: "waveform.path.ecg.rectangle")
                }
                .buttonStyle(.bordered).tint(BasirPalette.cyan)
                Text(l10n.t("يُحدّث السجل تلقائيًا أثناء تنفيذ المهمة ويخفي رموز الدخول والبيانات الحساسة.",
                            "The log updates automatically while the task runs and redacts access credentials."))
                    .font(.caption)
                    .foregroundStyle(BasirPalette.tertiaryText)
            }
        }
''',
    "diagnostic share label",
)
save(rel, s)

# A global rolling diagnostic log is also shareable from Settings. This catches
# import/network failures that happen before an individual task can start.
rel = "BasirConvert/Views/SettingsView.swift"
s = load(rel)
if "diagnosticsCard" not in s:
    s = replace_once(
        s,
        '                        networkCard\n                        documentCard\n',
        '                        networkCard\n                        diagnosticsCard\n                        documentCard\n',
        "settings diagnostic card placement",
    )
    anchor = '    private var documentCard: some View {'
    card = r'''    private var diagnosticsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassSectionTitle(title: l10n.t("التشخيص", "Diagnostics"), systemImage: "waveform.path.ecg.rectangle")
            Text(l10n.t(
                "يسجل بصير مراحل اختيار الملف والنقل والمعالجة والتنزيل والأخطاء بشكل مستمر. يتم إخفاء رموز الدخول تلقائيًا.",
                "Basir continuously records file selection, transfer, processing, download, and error stages. Access credentials are automatically redacted."
            ))
            .font(.footnote)
            .foregroundStyle(BasirPalette.secondaryText)
            if let log = DiagnosticLogger.globalLogURL() {
                ShareLink(item: log) {
                    Label(l10n.t("مشاركة سجل التشخيص الكامل", "Share full diagnostic log"), systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(BasirPalette.cyan)
            }
        }
        .glassSurface()
    }

'''
    s = replace_once(s, anchor, card + anchor, "settings diagnostic card body")
save(rel, s)

# Build gates: diagnostics must remain persistent, live-shareable and connected
# to the actual request pipeline.
checks = {
    "BasirConvert/Services/DiagnosticLogger.swift": ["Basir-live.log", "recordProgress", "recordNetwork", "recordError", "[REDACTED]"],
    "BasirConvert/ViewModels/AppViewModel.swift": ["activeLogger", "recordProgress(update)", "recordNetwork(snapshot", "recordGlobal"],
    "BasirConvert/Services/ProxyClient.swift": ["PREFLIGHT begin", "HTTP create finalStatus", "STATUS state=", "DOWNLOAD response", "RESULT valid", "X-Basir-Client-Version"],
    "BasirConvert/Views/JobView.swift": ["مشاركة سجل التشخيص", "يُحدّث السجل تلقائيًا"],
    "BasirConvert/Views/SettingsView.swift": ["diagnosticsCard", "مشاركة سجل التشخيص الكامل"],
}
for rel, needles in checks.items():
    text = load(rel)
    for needle in needles:
        if needle not in text:
            raise SystemExit(f"diagnostic gate failed: {needle!r} missing from {rel}")

print("BASIR_DIAGNOSTICS=CONTINUOUS_END_TO_END_R5")
