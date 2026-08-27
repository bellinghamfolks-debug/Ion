#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import sys


root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()


def load(relative: str) -> str:
    return (root / relative).read_text(encoding="utf-8")


def save(relative: str, content: str) -> None:
    (root / relative).write_text(content, encoding="utf-8")


def replace_once(content: str, old: str, new: str, label: str) -> str:
    count = content.count(old)
    if count != 1:
        raise SystemExit(f"R9 {label}: expected exactly one match, found {count}")
    return content.replace(old, new, 1)


# Make one app job keep one idempotency key across retries and relaunches. The
# backend derives a stable API job ID from this value, so a network interruption
# resumes the same logical conversion instead of silently creating duplicates.
engine_path = "BasirConvert/Services/ConversionEngine.swift"
engine = load(engine_path)
engine = replace_once(
    engine,
    """        logger: DiagnosticLogger,
        checkpointDirectory: URL? = nil
""",
    """        logger: DiagnosticLogger,
        requestID: String,
        checkpointDirectory: URL? = nil
""",
    "conversion-engine request ID signature",
)
engine = replace_once(
    engine,
    """            options: options,
            progress: progress,
            logger: logger
""",
    """            options: options,
            requestID: requestID,
            progress: progress,
            logger: logger
""",
    "conversion-engine request ID forwarding",
)
save(engine_path, engine)

view_model_path = "BasirConvert/ViewModels/AppViewModel.swift"
view_model = load(view_model_path)
view_model = replace_once(
    view_model,
    """                    configuration: configuration,
                    progress: { [weak self] update in
""",
    """                    configuration: configuration,
                    requestID: snapshot.requestID,
                    progress: { [weak self] update in
""",
    "app-job stable request ID",
)

# A route/DNS/server failure is not proof that the device is offline. Only move
# a job to Waiting for Network when NWPathMonitor independently says the path is
# unavailable. Policy waits (Wi-Fi/Low Data Mode) remain explicit exceptions.
old_network_classifier = """    private static func isNetworkWaitError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
                 .cannotFindHost, .dnsLookupFailed, .dataNotAllowed:
                return true
            default:
                return false
            }
        }
        guard let basir = error as? BasirError else { return false }
        switch basir {
        case .networkUnavailable, .wifiRequired, .constrainedNetwork:
            return true
        default:
            return false
        }
    }
"""
new_network_classifier = """    private static func isNetworkWaitError(_ error: Error) -> Bool {
        if let basir = error as? BasirError {
            switch basir {
            case .networkUnavailable, .wifiRequired, .constrainedNetwork:
                return true
            default:
                break
            }
        }
        guard !NetworkMonitor.shared.snapshot.isConnected,
              let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
             .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            return true
        default:
            return false
        }
    }
"""
view_model = replace_once(
    view_model,
    old_network_classifier,
    new_network_classifier,
    "network-wait evidence",
)

# Gate haptics and spoken progress on a genuine logical advance. Stage speech
# already has a separate de-duplicator.
old_progress = """        if update.total > 0 {
            let previous = lastAnnouncedProgress[jobID]
            let changed = previous?.current != update.current || previous?.total != update.total
            if changed {
                lastAnnouncedProgress[jobID] = (update.current, update.total)
                if (update.current == 1 || update.current == update.total || update.current % 5 == 0),
                   let l10n {
                    UIAccessibility.post(
                        notification: .announcement,
                        argument: l10n.t("تمت معالجة \\(update.current) من \\(update.total).",
                                         "Processed \\(update.current) of \\(update.total).")
                    )
                }
            }
        }
"""
new_progress = """        var didAdvanceLogicalProgress = false
        if update.total > 0 {
            let previous = lastAnnouncedProgress[jobID]
            let changed = previous?.current != update.current || previous?.total != update.total
            if changed {
                didAdvanceLogicalProgress = true
                lastAnnouncedProgress[jobID] = (update.current, update.total)
                if (update.current == 1 || update.current == update.total || update.current % 5 == 0),
                   let l10n {
                    UIAccessibility.post(
                        notification: .announcement,
                        argument: l10n.t("تمت معالجة \\(update.current) من \\(update.total).",
                                         "Processed \\(update.current) of \\(update.total).")
                    )
                }
            }
        }
"""
view_model = replace_once(view_model, old_progress, new_progress, "progress de-duplication")
view_model = replace_once(
    view_model,
    """        if update.current > 0, update.current % 10 == 0 {
            OperationFeedback.play(.progress, theme: settings?.soundTheme ?? .off)
        }
""",
    """        if didAdvanceLogicalProgress, update.current > 0, update.current % 10 == 0 {
            OperationFeedback.play(.progress, theme: settings?.soundTheme ?? .off)
        }
""",
    "progress haptic de-duplication",
)
save(view_model_path, view_model)

proxy_path = "BasirConvert/Services/ProxyClient.swift"
proxy = load(proxy_path)
proxy = replace_once(
    proxy,
    """        let jobID: String
        let uploadURL: URL
        let uploadMethod: String?
        let uploadHeaders: [String: String]?
""",
    """        let jobID: String
        let uploadURL: URL?
        let uploadMethod: String?
        let uploadHeaders: [String: String]?
        let resume: Bool?
""",
    "resumable creation response",
)
proxy = replace_once(
    proxy,
    """            case uploadMethod = "upload_method"
            case uploadHeaders = "upload_headers"
""",
    """            case uploadMethod = "upload_method"
            case uploadHeaders = "upload_headers"
            case resume
""",
    "resumable creation coding key",
)
proxy = replace_once(
    proxy,
    """        outputURL: URL,
        options: ConversionOptions,
        progress: @escaping @Sendable (ConversionProgress) -> Void,
""",
    """        outputURL: URL,
        options: ConversionOptions,
        requestID: String,
        progress: @escaping @Sendable (ConversionProgress) -> Void,
""",
    "proxy stable request ID signature",
)
proxy = replace_once(
    proxy,
    '            "adaptive_fidelity_repair"\n',
    '            "adaptive_fidelity_repair", "pdf_structural_geometry",\n'
    '            "geometry_validated_native_tables", "source_page_layout",\n'
    '            "nonexpanding_image_alt_text", "resumable_jobs"\n',
    "R9 capabilities",
)
proxy = proxy.replace('minimum: "2.6.0"', 'minimum: "2.7.0"')
proxy = proxy.replace('required=2.6.0', 'required=2.7.0')
proxy = replace_once(
    proxy,
    """        let base = try secureBaseURL()
        let requestID = UUID().uuidString
""",
    """        let base = try secureBaseURL()
        guard UUID(uuidString: requestID) != nil else {
            throw BasirError.invalidResponse("The task identifier is invalid.")
        }
""",
    "stable request ID use",
)
old_transfer_start = """        guard created.uploadURL.scheme?.lowercased() == "https", !created.jobID.isEmpty else {
            throw BasirError.invalidResponse("The server returned unsafe upload details.")
        }
        logger.record("job created requestID=\\(requestID) apiJob=\\(created.jobID)")

        progress(.init(current: 0, total: 0, stage: .uploading, detail: sourceURL.lastPathComponent,
                       transferredBytes: 0, totalBytes: sourceSize))
"""
new_transfer_start = """        guard !created.jobID.isEmpty else {
            throw BasirError.invalidResponse("The server returned an invalid task checkpoint.")
        }
        let resumingExistingJob = created.resume == true
        if !resumingExistingJob {
            guard created.uploadURL?.scheme?.lowercased() == "https" else {
                throw BasirError.invalidResponse("The server returned unsafe upload details.")
            }
        }
        logger.record("job ready requestID=\\(requestID) apiJob=\\(created.jobID) resumed=\\(resumingExistingJob)")

        if !resumingExistingJob {
            progress(.init(current: 0, total: 0, stage: .uploading, detail: sourceURL.lastPathComponent,
                           transferredBytes: 0, totalBytes: sourceSize))
"""
proxy = replace_once(proxy, old_transfer_start, new_transfer_start, "resume transfer branch")
proxy = replace_once(
    proxy,
    """        try Self.validateHTTP(commitResponse, data: commitData)

        var resultPath: String?
""",
    """            try Self.validateHTTP(commitResponse, data: commitData)
        } else {
            logger.record("RESUME polling existing apiJob=\\(created.jobID)")
        }

        var resultPath: String?
""",
    "resume transfer branch close",
)
proxy = replace_once(
    proxy,
    """        guard totalBytes > 0 else { throw BasirError.emptyDocument }
        guard (created.uploadMethod?.uppercased() ?? "PUT") == "PUT" else {
""",
    """        guard totalBytes > 0 else { throw BasirError.emptyDocument }
        guard let uploadURL = created.uploadURL, uploadURL.scheme?.lowercased() == "https" else {
            throw BasirError.invalidResponse("The upload checkpoint is missing.")
        }
        guard (created.uploadMethod?.uppercased() ?? "PUT") == "PUT" else {
""",
    "resumable upload URL unwrap",
)
proxy = replace_once(
    proxy,
    "var request = URLRequest(url: created.uploadURL)",
    "var request = URLRequest(url: uploadURL)",
    "resumable upload URL use",
)
proxy = replace_once(
    proxy,
    """        var completed = false
        var lastServerProgress: ConversionProgress?
""",
    """        var completed = false
        var validatedExpectedTables = 0
        var validatedExpectedImages = 0
        var validatedExpectedImageInstances = 0
        var lastServerProgress: ConversionProgress?
""",
    "validated structural expectations",
)

old_terminal_guard = """                guard terminalQuality == "passed" else {
                    throw BasirError.conversionFailed("لم يصل المستند الناتج إلى مستوى الجودة الآمن للاعتماد. لم يتم حفظ نتيجة ناقصة أو مشوهة.")
                }
                resultPath = object?["result_url"] as? String
"""
new_terminal_guard = """                guard terminalQuality == "passed", failedItems.isEmpty else {
                    throw BasirError.conversionFailed("لم يصل المستند الناتج إلى مستوى الجودة الآمن للاعتماد. لم يتم حفظ نتيجة ناقصة أو مشوهة.")
                }
                if expectedSourcePages > 0 {
                    let expectedResultPages = max(0, expectedSourcePages - skippedItems.count)
                    guard Self.integer(qualityMetrics["source_pages"]) == expectedSourcePages,
                          Self.integer(qualityMetrics["expected_rendered_pages"]) == expectedResultPages,
                          Self.integer(qualityMetrics["rendered_pages"]) == expectedResultPages else {
                        throw BasirError.invalidResponse("The quality manifest page geometry is inconsistent.")
                    }
                    let expectedTables = Self.integer(qualityMetrics["expected_native_tables"]) ?? -1
                    let resultTables = Self.integer(qualityMetrics["result_native_tables"]) ?? -1
                    let sourceImages = Self.integer(qualityMetrics["source_images"]) ?? -1
                    let sourceUniqueImages = Self.integer(qualityMetrics["source_unique_images"]) ?? -1
                    let resultImages = Self.integer(qualityMetrics["result_images"]) ?? -1
                    let resultImageDrawings = Self.integer(qualityMetrics["result_image_drawings"]) ?? -1
                    let missingAlt = Self.integer(qualityMetrics["images_missing_alt_text"]) ?? -1
                    if options.outputMode != .simple && options.outputMode != .descriptionsOnly {
                        guard expectedTables >= 0, resultTables >= expectedTables else {
                            throw BasirError.invalidResponse("The quality manifest table counts are inconsistent.")
                        }
                        let expectedColumns = Self.integerArray(qualityMetrics["expected_table_columns"]) ?? []
                        let resultColumns = Self.integerArray(qualityMetrics["result_table_columns"]) ?? []
                        guard resultColumns.count >= expectedColumns.count,
                              Array(resultColumns.prefix(expectedColumns.count)) == expectedColumns else {
                            throw BasirError.invalidResponse("The quality manifest table geometry is inconsistent.")
                        }
                        validatedExpectedTables = expectedTables
                    }
                    if options.effectiveEmbedVisuals {
                        guard sourceImages >= 0, sourceUniqueImages >= 0,
                              resultImages >= sourceUniqueImages,
                              resultImageDrawings >= sourceImages, missingAlt == 0 else {
                            throw BasirError.invalidResponse("The quality manifest image counts are inconsistent.")
                        }
                        validatedExpectedImages = sourceUniqueImages
                        validatedExpectedImageInstances = sourceImages
                    }
                }
                resultPath = object?["result_url"] as? String
"""
proxy = replace_once(proxy, old_terminal_guard, new_terminal_guard, "terminal structural manifest")
proxy = replace_once(
    proxy,
    """            outputURL: outputURL,
            expectedPages: expectedResultPages
""",
    """            outputURL: outputURL,
            expectedPages: expectedResultPages,
            expectedTables: validatedExpectedTables,
            expectedImages: validatedExpectedImages,
            expectedImageInstances: validatedExpectedImageInstances
""",
    "DOCX structural validation call",
)
proxy = replace_once(
    proxy,
    """        outputURL: URL,
        expectedPages: Int
""",
    """        outputURL: URL,
        expectedPages: Int,
        expectedTables: Int,
        expectedImages: Int,
        expectedImageInstances: Int
""",
    "DOCX structural validation signature",
)
proxy = replace_once(
    proxy,
    "try DocxBuilder.validate(url: temporary, expectedPages: expectedPages)",
    "try DocxBuilder.validate(url: temporary, expectedPages: expectedPages, expectedTables: expectedTables, expectedImages: expectedImages, expectedImageInstances: expectedImageInstances)",
    "DOCX structural validator invocation",
)

# Never remove a previously valid result before the replacement is ready.
proxy = replace_once(
    proxy,
    """        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        try FileManager.default.moveItem(at: temporary, to: outputURL)
""",
    """        if FileManager.default.fileExists(atPath: outputURL.path) {
            _ = try FileManager.default.replaceItemAt(
                outputURL,
                withItemAt: temporary,
                backupItemName: nil,
                options: []
            )
        } else {
            try FileManager.default.moveItem(at: temporary, to: outputURL)
        }
""",
    "atomic result publication",
)

# Retrying creation/commit/status was already present; apply the same bounded
# policy to downloads, including retryable HTTP responses.
old_download = """    private func downloadResult(
        request: URLRequest,
        logger: DiagnosticLogger,
        progress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws -> (URL, HTTPURLResponse) {
        do {
            return try await BackgroundTransferCoordinator.shared.download(
                request: request,
                progress: progress
            )
        } catch let urlError as URLError where Self.isBackgroundFileStagingError(urlError) {
            logger.record("DOWNLOAD background-transfer fallback urlCode=\\(urlError.code.rawValue)")
            let (temporary, response) = try await session.download(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw BasirError.invalidResponse("Missing HTTP response.")
            }
            let expected = max(0, http.expectedContentLength)
            let actual = Int64((try? temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            progress(actual, expected > 0 ? expected : actual)
            return (temporary, http)
        }
    }
"""
new_download = """    private func downloadResult(
        request: URLRequest,
        logger: DiagnosticLogger,
        progress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws -> (URL, HTTPURLResponse) {
        var lastError: Error?
        for attempt in 0..<4 {
            try Task.checkCancellation()
            do {
                let result = try await downloadResultOnce(request: request, logger: logger, progress: progress)
                logger.record("DOWNLOAD attempt=\\(attempt + 1) status=\\(result.1.statusCode)")
                if Self.retryableCodes.contains(result.1.statusCode), attempt < 3 {
                    lastError = Self.httpError(result.1, data: Data())
                    try? FileManager.default.removeItem(at: result.0)
                    try await Self.wait(attempt: attempt, response: result.1)
                    continue
                }
                return result
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                logger.recordError(error, context: "download attempt \\(attempt + 1)")
                lastError = error
                guard attempt < 3, Self.isRetryable(error) else { throw error }
                try await Self.wait(attempt: attempt, response: nil)
            }
        }
        throw lastError ?? BasirError.conversionFailed("Download failed after retries.")
    }

    private func downloadResultOnce(
        request: URLRequest,
        logger: DiagnosticLogger,
        progress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws -> (URL, HTTPURLResponse) {
        do {
            return try await BackgroundTransferCoordinator.shared.download(
                request: request,
                progress: progress
            )
        } catch let urlError as URLError where Self.isBackgroundFileStagingError(urlError) {
            logger.record("DOWNLOAD background-transfer fallback urlCode=\\(urlError.code.rawValue)")
            let (temporary, response) = try await session.download(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw BasirError.invalidResponse("Missing HTTP response.")
            }
            let expected = max(0, http.expectedContentLength)
            let actual = Int64((try? temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            progress(actual, expected > 0 ? expected : actual)
            return (temporary, http)
        }
    }
"""
proxy = replace_once(proxy, old_download, new_download, "bounded download retry")

integer_helper = """    private static func integer(_ value: Any?) -> Int? {
        if let integer = value as? Int { return integer }
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String { return Int(text) }
        return nil
    }
"""
integer_helpers = integer_helper + """
    private static func integerArray(_ value: Any?) -> [Int]? {
        if let values = value as? [Int] { return values }
        if let values = value as? [NSNumber] { return values.map(\\.intValue) }
        if let values = value as? [Any] {
            let parsed = values.compactMap(Self.integer)
            return parsed.count == values.count ? parsed : nil
        }
        return nil
    }
"""
proxy = replace_once(proxy, integer_helper, integer_helpers, "quality integer arrays")
proxy = replace_once(
    proxy,
    "    // BASIR_RELIABILITY_GUARD_R8: server 2.6.0 + adaptive repair + fail-closed manifest\n",
    """    // BASIR_RELIABILITY_GUARD_R8: server 2.7.0 + adaptive repair + fail-closed manifest
    // BASIR_RELIABILITY_GUARD_R9: stable resume + structural manifest + atomic result
""",
    "R9 marker",
)
save(proxy_path, proxy)

builder_path = "BasirConvert/Services/DocxBuilder.swift"
builder = load(builder_path)
builder = replace_once(
    builder,
    """        expectedTables: Int = 0,
        expectedImages: Int = 0
""",
    """        expectedTables: Int = 0,
        expectedImages: Int = 0,
        expectedImageInstances: Int = 0
""",
    "image-instance validation signature",
)
builder = replace_once(
    builder,
    """        if tables < expectedTables {
            throw BasirError.conversionFailed("Expected Word tables are missing from the generated DOCX.")
        }
""",
    """        if tables < expectedTables {
            throw BasirError.conversionFailed("Expected Word tables are missing from the generated DOCX.")
        }
        if expectedTables > 0, occurrences(of: "<w:tblHeader", in: xml) < expectedTables {
            throw BasirError.conversionFailed("Expected accessible table headers are missing from the generated DOCX.")
        }
""",
    "accessible native table headers",
)
builder = replace_once(
    builder,
    """            let pages = occurrences(of: "<w:br w:type=\\\"page\\\"/>", in: xml) + 1
            if pages < expectedPages {
""",
    """            let explicitPageBreaks = occurrences(of: "<w:br w:type=\\\"page\\\"/>", in: xml)
            let sectionPages = max(1, occurrences(of: "<w:sectPr", in: xml))
            let pages = explicitPageBreaks + sectionPages
            if pages < expectedPages {
""",
    "section-aware page validation",
)
builder = replace_once(
    builder,
    """        if expectedImages > 0 {
""",
    """        if max(expectedImages, expectedImageInstances) > 0 {
""",
    "image-instance validation activation",
)
builder = replace_once(
    builder,
    """            let altTexts = occurrences(of: "<wp:docPr ", in: xml)
            let media = archive.filter { $0.path.hasPrefix("word/media/") && $0.type == .file }.count
            guard drawings >= expectedImages, altTexts >= expectedImages,
""",
    """            let altTexts = occurrences(of: " descr=\\\"", in: xml)
                - occurrences(of: " descr=\\\"\\\"", in: xml)
            let media = archive.filter { $0.path.hasPrefix("word/media/") && $0.type == .file }.count
            guard drawings >= max(expectedImages, expectedImageInstances),
                  altTexts >= max(expectedImages, expectedImageInstances),
""",
    "non-empty image Alt Text",
)
save(builder_path, builder)

checks = {
    proxy_path: [
        "BASIR_RELIABILITY_GUARD_R9",
        'minimum: "2.7.0"',
        '"pdf_structural_geometry"',
        '"geometry_validated_native_tables"',
        '"nonexpanding_image_alt_text"',
        '"resumable_jobs"',
        'qualityMetrics["result_native_tables"]',
        'qualityMetrics["source_unique_images"]',
        'qualityMetrics["result_image_drawings"]',
        "failedItems.isEmpty",
        "downloadResultOnce",
        "replaceItemAt",
        "requestID: String",
        "resumingExistingJob",
    ],
    view_model_path: [
        "requestID: snapshot.requestID",
        "guard !NetworkMonitor.shared.snapshot.isConnected",
        "didAdvanceLogicalProgress",
    ],
    builder_path: [
        "Expected accessible table headers are missing",
        "expectedImageInstances: Int = 0",
        "sectionPages = max(1",
        'occurrences(of: " descr=\\\"", in: xml)',
    ],
}
for relative, needles in checks.items():
    final = load(relative)
    for needle in needles:
        if needle not in final:
            raise SystemExit(f"R9 reliability gate failed: {needle!r} missing from {relative}")

if 'minimum: "2.6.0"' in load(proxy_path):
    raise SystemExit("R9 stale 2.6.0 minimum remains")

print("BASIR_RELIABILITY_GUARD=GEOMETRY_RESUME_ATOMIC_R9")
