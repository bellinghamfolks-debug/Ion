import Foundation

struct BasirServerStatus: Sendable {
    let apiVersion: String
    let apiContract: String
    let capabilities: Set<String>
    let latencyMilliseconds: Int
    let authenticated: Bool
}

actor ProxyClient {
    private struct JobCreationRequest: Encodable {
        let filename: String
        let contentType: String
        let contentLength: Int64
        let sourceSHA256: String
        let operation: String
        let mode: String
        let targetLanguage: String
        let interfaceLanguage: String
        let pageSelection: String
        let outputName: String?
        let preferredModel: String

        enum CodingKeys: String, CodingKey {
            case filename
            case contentType = "content_type"
            case contentLength = "content_length"
            case sourceSHA256 = "source_sha256"
            case operation, mode
            case targetLanguage = "target_language"
            case interfaceLanguage = "interface_language"
            case pageSelection = "page_selection"
            case outputName = "output_name"
            case preferredModel = "preferred_model"
        }
    }

    private struct JobCreationResponse: Decodable {
        let jobID: String
        let uploadURL: URL?
        let uploadMethod: String?
        let uploadHeaders: [String: String]?
        let resume: Bool

        enum CodingKeys: String, CodingKey {
            case jobID = "job_id"
            case uploadURL = "upload_url"
            case uploadMethod = "upload_method"
            case uploadHeaders = "upload_headers"
            case resume
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            jobID = try values.decode(String.self, forKey: .jobID)
            uploadURL = try values.decodeIfPresent(URL.self, forKey: .uploadURL)
            uploadMethod = try values.decodeIfPresent(String.self, forKey: .uploadMethod)
            uploadHeaders = try values.decodeIfPresent([String: String].self, forKey: .uploadHeaders)
            resume = try values.decodeIfPresent(Bool.self, forKey: .resume) ?? false
        }
    }

    private struct CommitRequest: Encodable {
        let sourceSHA256: String
        let contentLength: Int64

        enum CodingKeys: String, CodingKey {
            case sourceSHA256 = "source_sha256"
            case contentLength = "content_length"
        }
    }

    private struct QualityMetrics: Decodable {
        var retainedPageNumbers: [Int]? = nil
        var skippedBlankPageNumbers: [Int]? = nil
        var fallbackPageNumbers: [Int]? = nil
        var relaxedLayoutPageNumbers: [Int]? = nil
        var sourcePageAccountingExact: Bool? = nil
        var sourcePageNumberingExact: Bool? = nil
        var sourcePages: Int? = nil
        var expectedRenderedPages: Int? = nil
        var expectedNativeTables: Int? = nil
        var sourceUniqueImages: Int? = nil
        var artifactBytes: Int? = nil
        var artifactMembers: Int? = nil
        var artifactTextCharacters: Int? = nil
        var artifactTables: Int? = nil
        var artifactDrawings: Int? = nil
        var artifactMissingAltText: Int? = nil
        var conversionEngine: String? = nil
        var naturalMarkdownEngine: Bool? = nil
        var parallelWorkers: Int? = nil
        var detailReviewedPages: Int? = nil
        var handwritingReviewedPages: Int? = nil
        var visualReviewedPages: Int? = nil
        var visualsWithoutModelDescription: Int? = nil

        enum CodingKeys: String, CodingKey {
            case retainedPageNumbers = "retained_page_numbers"
            case skippedBlankPageNumbers = "skipped_blank_page_numbers"
            case fallbackPageNumbers = "fallback_page_numbers"
            case relaxedLayoutPageNumbers = "relaxed_layout_page_numbers"
            case sourcePageAccountingExact = "source_page_accounting_exact"
            case sourcePageNumberingExact = "source_page_numbering_exact"
            case sourcePages = "source_pages"
            case expectedRenderedPages = "expected_rendered_pages"
            case expectedNativeTables = "expected_native_tables"
            case sourceUniqueImages = "source_unique_images"
            case artifactBytes = "artifact_bytes"
            case artifactMembers = "artifact_members"
            case artifactTextCharacters = "artifact_text_characters"
            case artifactTables = "artifact_tables"
            case artifactDrawings = "artifact_drawings"
            case artifactMissingAltText = "artifact_missing_alt_text"
            case conversionEngine = "conversion_engine"
            case naturalMarkdownEngine = "natural_markdown_engine"
            case parallelWorkers = "parallel_workers"
            case detailReviewedPages = "detail_reviewed_pages"
            case handwritingReviewedPages = "handwriting_reviewed_pages"
            case visualReviewedPages = "visual_reviewed_pages"
            case visualsWithoutModelDescription = "visuals_without_model_description"
        }

        var isNaturalMarkdownEngine: Bool {
            naturalMarkdownEngine == true
                || conversionEngine?.lowercased().hasPrefix("natural_markdown") == true
        }
    }

    private struct JobStatusResponse: Decodable {
        let status: String
        let current: Int
        let total: Int
        let succeeded: Int
        let detail: String?
        let error: String?
        let failedItems: [Int]
        let skippedBlankItems: [Int]
        let qualityStatus: String?
        let qualityScore: Double?
        let qualityWarnings: [String]
        let qualityMetrics: QualityMetrics?
        let requestedModel: String?
        let executedModel: String?
        let resultURL: String?

        enum CodingKeys: String, CodingKey {
            case status, current, total, succeeded, detail, error
            case failedItems = "failed_items"
            case skippedBlankItems = "skipped_blank_items"
            case qualityStatus = "quality_status"
            case qualityScore = "quality_score"
            case qualityWarnings = "quality_warnings"
            case qualityMetrics = "quality_metrics"
            case requestedModel = "requested_model"
            case executedModel = "executed_model"
            case resultURL = "result_url"
        }
    }

    private static let maximumResponseBytes = 250 * 1024 * 1024
    private static let retryableCodes = Set([408, 425, 429, 500, 502, 503, 504])
    private let configuration: ServerConfiguration
    private let session: URLSession

    init(configuration: ServerConfiguration) {
        self.configuration = configuration
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 900
        config.waitsForConnectivity = true
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.httpMaximumConnectionsPerHost = 2
        session = URLSession(configuration: config)
    }

    func testConnection() async throws -> BasirServerStatus {
        let base = try secureBaseURL()
        var request = URLRequest(url: base.appendingPathComponent("/api/health"))
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        applyServerHeaders(to: &request, requestID: UUID().uuidString)
        let start = ContinuousClock.now
        let (data, response) = try await session.data(for: request)
        let elapsed = start.duration(to: .now)
        guard let http = response as? HTTPURLResponse else {
            throw BasirError.invalidResponse("Missing health response.")
        }
        try Self.validateHTTP(http, data: data)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let version = (json?["api_version"] as? String)
            ?? http.value(forHTTPHeaderField: "X-Basir-API-Version")
            ?? "unknown"
        let contract = (json?["api_contract"] as? String)
            ?? http.value(forHTTPHeaderField: "X-Basir-API-Contract")
            ?? ""
        let list = (json?["capabilities"] as? [String])
            ?? http.value(forHTTPHeaderField: "X-Basir-Capabilities")?
                .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            ?? []
        let components = elapsed.components
        let milliseconds = max(0, Int(components.seconds * 1_000)
            + Int(components.attoseconds / 1_000_000_000_000_000))
        return BasirServerStatus(
            apiVersion: version,
            apiContract: contract,
            capabilities: Set(list.map { $0.lowercased() }),
            latencyMilliseconds: milliseconds,
            authenticated: true
        )
    }

    func convert(
        sourceURL: URL,
        outputURL: URL,
        options: ConversionOptions,
        requestID: String,
        progress: @escaping @Sendable (ConversionProgress) -> Void,
        logger: DiagnosticLogger
    ) async throws -> ConversionOutcome {
        let serverStatus = try await testConnection()
        guard BasirAPIContract.accepts(
            apiContract: serverStatus.apiContract,
            capabilities: serverStatus.capabilities
        ) else {
            throw BasirError.invalidResponse("The server needs an update before it can accept this file.")
        }

        let base = try secureBaseURL()
        let stableRequestID = requestID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard stableRequestID.count >= 8 else {
            throw BasirError.invalidResponse("The local task identifier is invalid.")
        }
        let checksum = try DocumentInspector.sha256(sourceURL)
        let sourceSize = Int64((try? sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        let sourceDocumentPages: Int = {
            guard sourceURL.pathExtension.lowercased() == "pdf",
                  let metadata = try? DocumentInspector.inspect(sourceURL, includeChecksum: false),
                  let total = metadata.itemCount, total > 0 else { return 0 }
            return total
        }()
        let normalizedPageSelection = PageSelectionNormalizer.normalize(options.pageSelection)
        let expectedSourcePages: Int = {
            guard sourceDocumentPages > 0 else { return 0 }
            return (try? PageSelectionParser.pages(from: normalizedPageSelection, total: sourceDocumentPages).count)
                ?? sourceDocumentPages
        }()
        logger.record("QUALITY sourcePages=\(sourceDocumentPages) selectedPages=\(expectedSourcePages) selection=\(options.pageSelection.isEmpty ? "all" : options.pageSelection) normalizedSelection=\(normalizedPageSelection)")
        let creation = JobCreationRequest(
            filename: sourceURL.lastPathComponent,
            contentType: FileAccess.mimeType(for: sourceURL),
            contentLength: sourceSize,
            sourceSHA256: checksum,
            operation: options.operation.rawValue,
            mode: options.encodedMode,
            targetLanguage: options.targetLanguage?.code ?? "",
            interfaceLanguage: options.interfaceLanguage.rawValue,
            pageSelection: normalizedPageSelection,
            outputName: options.outputName,
            preferredModel: options.effectivePreferredModel
        )

        var createRequest = URLRequest(url: base.appendingPathComponent("/api/jobs"))
        createRequest.httpMethod = "POST"
        createRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        createRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        createRequest.httpBody = try JSONEncoder().encode(creation)
        applyServerHeaders(to: &createRequest, requestID: stableRequestID)
        progress(.init(current: 0, total: 0, stage: .preparing, detail: sourceURL.lastPathComponent))

        let (creationData, creationResponse) = try await retryingData(request: createRequest)
        try Self.validateHTTP(creationResponse, data: creationData)
        let created: JobCreationResponse
        do {
            created = try JSONDecoder().decode(JobCreationResponse.self, from: creationData)
        } catch {
            throw BasirError.invalidResponse("The server did not return valid upload details.")
        }
        guard !created.jobID.isEmpty else {
            throw BasirError.invalidResponse("The server returned an invalid task identifier.")
        }
        if !created.resume {
            guard let uploadURL = created.uploadURL, uploadURL.scheme?.lowercased() == "https" else {
                throw BasirError.invalidResponse("The server returned unsafe upload details.")
            }
            logger.record("job ready requestID=\(stableRequestID) apiJob=\(created.jobID) resumed=false requestedModel=\(options.effectivePreferredModel)")
            progress(.init(current: 0, total: 0, stage: .uploading, detail: sourceURL.lastPathComponent,
                           transferredBytes: 0, totalBytes: sourceSize))
            try await uploadInChunks(
                sourceURL: sourceURL,
                created: created,
                uploadURL: uploadURL,
                totalBytes: sourceSize
            ) { sent in
                progress(.init(current: 0, total: 0, stage: .uploading, detail: sourceURL.lastPathComponent,
                               transferredBytes: sent, totalBytes: sourceSize))
            }

            var commit = URLRequest(url: base.appendingPathComponent("/api/jobs/\(created.jobID)/commit"))
            commit.httpMethod = "POST"
            commit.setValue("application/json", forHTTPHeaderField: "Content-Type")
            commit.setValue("application/json", forHTTPHeaderField: "Accept")
            commit.httpBody = try JSONEncoder().encode(
                CommitRequest(sourceSHA256: checksum, contentLength: sourceSize)
            )
            applyServerHeaders(to: &commit, requestID: stableRequestID)
            let (commitData, commitResponse) = try await retryingData(request: commit)
            try Self.validateHTTP(commitResponse, data: commitData)
        } else {
            logger.record("job ready requestID=\(stableRequestID) apiJob=\(created.jobID) resumed=true requestedModel=\(options.effectivePreferredModel)")
            progress(.init(current: 0, total: 0, stage: .processing, detail: "Resuming server task"))
        }

        var resultPath: String?
        var outcome = ConversionOutcome.complete
        var completed = false
        var naturalEngineResult = false
        var validatedExpectedTables = 0
        var validatedExpectedImages = 0
        var lastServerProgress: ConversionProgress?
        for _ in 0..<10_800 {
            try Task.checkCancellation()
            var statusRequest = URLRequest(url: base.appendingPathComponent("/api/jobs/\(created.jobID)"))
            statusRequest.httpMethod = "GET"
            applyServerHeaders(to: &statusRequest, requestID: stableRequestID)
            let (statusData, statusResponse) = try await retryingData(request: statusRequest)
            try Self.validateHTTP(statusResponse, data: statusData)
            let status: JobStatusResponse
            do {
                status = try JSONDecoder().decode(JobStatusResponse.self, from: statusData)
            } catch {
                throw BasirError.invalidResponse("The server returned an invalid task status.")
            }
            let qualityStatus = status.qualityStatus?.lowercased()
            let qualityScore = status.qualityScore
            let qualityWarnings = status.qualityWarnings
            let qualityMetrics = status.qualityMetrics ?? QualityMetrics()
            let state = status.status.lowercased()
            let current = status.current
            let total = status.total
            let succeeded = status.succeeded
            let failedItems = status.failedItems
            let skippedItems = status.skippedBlankItems
            let serverProgress = ConversionProgress(
                current: current, total: total, stage: .processing,
                detail: status.detail,
                succeeded: succeeded, failed: failedItems.count, skipped: skippedItems.count
            )
            if serverProgress != lastServerProgress {
                lastServerProgress = serverProgress
                progress(serverProgress)
            }
            if ["completed", "complete", "done", "succeeded", "partial"].contains(state) {
                guard let terminalQuality = qualityStatus else {
                    logger.record("QUALITY terminal manifest missing")
                    throw BasirError.invalidResponse("تعذر التحقق من جودة المستند الناتج. لم يتم اعتماد الملف.")
                }
                let retainedNumbers = qualityMetrics.retainedPageNumbers ?? []
                let skippedNumbers = qualityMetrics.skippedBlankPageNumbers ?? skippedItems
                let fallbackNumbers = qualityMetrics.fallbackPageNumbers ?? failedItems
                let relaxedNumbers = qualityMetrics.relaxedLayoutPageNumbers ?? []
                let accountingExact = qualityMetrics.sourcePageAccountingExact
                let numberingExact = qualityMetrics.sourcePageNumberingExact
                let isNaturalEngine = qualityMetrics.isNaturalMarkdownEngine
                logger.record("QUALITY terminal status=\(terminalQuality) score=\(qualityScore ?? -1) warnings=\(qualityWarnings.joined(separator: ",")) engine=\(qualityMetrics.conversionEngine ?? "legacy") natural=\(isNaturalEngine)")
                logger.record("QUALITY pages retained=\(retainedNumbers) skippedBlank=\(skippedNumbers) fallback=\(fallbackNumbers) relaxedLayout=\(relaxedNumbers) accountingExact=\(accountingExact.map(String.init) ?? "nil") numberingExact=\(numberingExact.map(String.init) ?? "nil")")
                guard terminalQuality == "passed" else {
                    throw BasirError.conversionFailed("لم يصل المستند الناتج إلى مستوى الجودة الآمن للاعتماد. لم يتم حفظ نتيجة ناقصة أو مشوهة.")
                }
                if expectedSourcePages > 0 {
                    if isNaturalEngine {
                        guard Set(skippedNumbers) == Set(skippedItems),
                              Set(fallbackNumbers) == Set(failedItems),
                              BasirAPIContract.naturalPageAccountingIsValid(
                                expectedSelectedPages: expectedSourcePages,
                                retained: retainedNumbers,
                                skippedBlank: skippedNumbers,
                                failed: fallbackNumbers
                              ) else {
                            throw BasirError.invalidResponse("The natural-engine source-page accounting is inconsistent.")
                        }
                        // The server has already structurally validated this DOCX.
                        // Do not re-apply legacy PageIR physical-page/table/image
                        // assumptions to a natural Markdown result.
                        validatedExpectedTables = 0
                        validatedExpectedImages = 0
                    } else {
                        let expectedResultPages = max(0, expectedSourcePages - skippedItems.count)
                        guard qualityMetrics.sourcePages == expectedSourcePages,
                              qualityMetrics.expectedRenderedPages == expectedResultPages else {
                            throw BasirError.invalidResponse("The quality manifest source-page accounting is inconsistent.")
                        }
                        let requiresExactSourceIdentity = options.operation == .convert && options.outputMode != .simple
                        if requiresExactSourceIdentity {
                            guard accountingExact == true, numberingExact == true else {
                                throw BasirError.invalidResponse("The quality manifest source-page identity or numbering is inconsistent.")
                            }
                        }
                        let expectedTables = qualityMetrics.expectedNativeTables ?? 0
                        let sourceUniqueImages = qualityMetrics.sourceUniqueImages ?? 0
                        validatedExpectedTables = max(0, expectedTables)
                        validatedExpectedImages = max(0, sourceUniqueImages)
                    }
                }
                let artifactBytes = qualityMetrics.artifactBytes ?? 0
                let artifactMembers = qualityMetrics.artifactMembers ?? 0
                let artifactText = qualityMetrics.artifactTextCharacters ?? 0
                let artifactTables = qualityMetrics.artifactTables ?? 0
                let artifactDrawings = qualityMetrics.artifactDrawings ?? 0
                let artifactMissingAlt = qualityMetrics.artifactMissingAltText ?? -1
                guard artifactBytes > 0, artifactMembers >= 3, artifactMissingAlt == 0,
                      artifactText > 0 || artifactTables > 0 || artifactDrawings > 0 else {
                    throw BasirError.invalidResponse("The quality manifest Word-package integrity is inconsistent.")
                }
                resultPath = status.resultURL
                let requestedModel = status.requestedModel ?? options.effectivePreferredModel
                let executedModel = status.executedModel
                logger.record("job model requestID=\(stableRequestID) requested=\(requestedModel) executed=\(executedModel ?? "unknown") workers=\(qualityMetrics.parallelWorkers ?? 0) detailReviews=\(qualityMetrics.detailReviewedPages ?? 0) handwritingReviews=\(qualityMetrics.handwritingReviewedPages ?? 0) visualReviews=\(qualityMetrics.visualReviewedPages ?? 0)")
                outcome = ConversionOutcome(
                    succeededItems: succeeded,
                    failedItems: failedItems,
                    skippedBlankItems: skippedItems,
                    requestedModel: requestedModel,
                    executedModel: executedModel
                )
                naturalEngineResult = isNaturalEngine
                completed = true
                break
            }
            if ["failed", "cancelled", "canceled"].contains(state) {
                throw BasirError.conversionFailed(
                    status.error ?? "The server could not complete this task."
                )
            }
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
        guard completed else {
            throw BasirError.conversionFailed("The server did not finish the task within the allowed time.")
        }

        let resultURL: URL
        if let resultPath, let absolute = URL(string: resultPath), absolute.scheme == "https" {
            resultURL = absolute
        } else {
            resultURL = base.appendingPathComponent("/api/jobs/\(created.jobID)/result")
        }
        var download = URLRequest(url: resultURL)
        download.httpMethod = "GET"
        download.setValue("application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                          forHTTPHeaderField: "Accept")
        if resultURL.host == base.host {
            applyServerHeaders(to: &download, requestID: stableRequestID)
        }
        progress(.init(current: 0, total: 0, stage: .downloading, detail: nil))
        let (temporary, downloadResponse) = try await BackgroundTransferCoordinator.shared.download(
            request: download
        ) { received, total in
            progress(.init(current: 0, total: 0, stage: .downloading, detail: nil,
                           transferredBytes: received, totalBytes: total))
        }
        defer { try? FileManager.default.removeItem(at: temporary) }
        try validateDownloadedHTTP(downloadResponse, temporary: temporary)
        try validateResultResponse(downloadResponse)
        let expectedResultPages = naturalEngineResult
            ? 0
            : max(0, expectedSourcePages - outcome.skippedBlankItems.count)
        try verifyAndMove(
            temporary: temporary, response: downloadResponse, outputURL: outputURL,
            expectedPages: expectedResultPages, expectedTables: validatedExpectedTables,
            expectedImages: validatedExpectedImages
        )
        logger.record("job completed requestID=\(stableRequestID) naturalEngine=\(naturalEngineResult)")
        progress(.init(current: 1, total: 1, stage: .done, detail: nil))
        return outcome
    }

    private func uploadInChunks(
        sourceURL: URL,
        created: JobCreationResponse,
        uploadURL: URL,
        totalBytes: Int64,
        progress: @escaping @Sendable (Int64) -> Void
    ) async throws {
        guard totalBytes > 0 else { throw BasirError.emptyDocument }
        guard (created.uploadMethod?.uppercased() ?? "PUT") == "PUT" else {
            throw BasirError.invalidResponse("The server returned an unsupported upload method.")
        }
        let chunkSize = 8 * 1024 * 1024
        let input = try FileHandle(forReadingFrom: sourceURL)
        defer { try? input.close() }
        var offset: Int64 = 0

        while offset < totalBytes {
            try Task.checkCancellation()
            try input.seek(toOffset: UInt64(offset))
            guard let chunk = try input.read(upToCount: chunkSize), !chunk.isEmpty else {
                throw BasirError.invalidResponse("The source file ended before upload completed.")
            }
            let chunkOffset = offset
            let end = chunkOffset + Int64(chunk.count) - 1
            let chunkURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("BasirUploadChunk-\(UUID().uuidString)")
            try chunk.write(to: chunkURL, options: [.atomic, .completeFileProtectionUnlessOpen])
            defer { try? FileManager.default.removeItem(at: chunkURL) }

            var request = URLRequest(url: uploadURL)
            request.httpMethod = "PUT"
            request.timeoutInterval = 24 * 60 * 60
            request.setValue(FileAccess.mimeType(for: sourceURL), forHTTPHeaderField: "Content-Type")
            request.setValue(String(chunk.count), forHTTPHeaderField: "Content-Length")
            request.setValue("bytes \(chunkOffset)-\(end)/\(totalBytes)", forHTTPHeaderField: "Content-Range")
            created.uploadHeaders?.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }

            let (data, response) = try await retryingBackgroundUpload(
                request: request,
                fileURL: chunkURL
            ) { sent, _ in
                progress(min(totalBytes, chunkOffset + sent))
            }
            let isFinalChunk = end + 1 == totalBytes
            if isFinalChunk {
                try Self.validateHTTP(response, data: data)
            } else if response.statusCode != 308 {
                throw Self.httpError(response, data: data)
            }
            offset = end + 1
            progress(offset)
        }
    }

    private func retryingBackgroundUpload(
        request: URLRequest,
        fileURL: URL,
        progress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws -> (Data, HTTPURLResponse) {
        var lastError: Error?
        for attempt in 0..<4 {
            try Task.checkCancellation()
            do {
                let result = try await BackgroundTransferCoordinator.shared.upload(
                    request: request,
                    fromFile: fileURL,
                    progress: progress
                )
                if Self.retryableCodes.contains(result.1.statusCode), attempt < 3 {
                    lastError = Self.httpError(result.1, data: result.0)
                    try await Self.wait(attempt: attempt, response: result.1)
                    continue
                }
                return result
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                guard attempt < 3, Self.isRetryable(error) else { throw error }
                try await Self.wait(attempt: attempt, response: nil)
            }
        }
        throw lastError ?? BasirError.conversionFailed("Upload failed after retries.")
    }

    private func retryingData(request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var lastError: Error?
        for attempt in 0..<4 {
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw BasirError.invalidResponse("Missing HTTP response.")
                }
                if Self.retryableCodes.contains(http.statusCode), attempt < 3 {
                    lastError = Self.httpError(http, data: data)
                    try await Self.wait(attempt: attempt, response: http)
                    continue
                }
                return (data, http)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                guard attempt < 3, Self.isRetryable(error) else { throw error }
                try await Self.wait(attempt: attempt, response: nil)
            }
        }
        throw lastError ?? BasirError.conversionFailed("Request failed after retries.")
    }

    private func secureBaseURL() throws -> URL {
        guard let secure = configuration.secureBaseURL else { throw BasirError.invalidServerURL }
        var value = secure.absoluteString
        while value.hasSuffix("/") { value.removeLast() }
        guard let result = URL(string: value), result.scheme?.lowercased() == "https" else {
            throw BasirError.invalidServerURL
        }
        return result
    }

    private func applyServerHeaders(to request: inout URLRequest, requestID: String) {
        request.setValue("Basir-iOS/3.0.0", forHTTPHeaderField: "User-Agent")
        request.setValue(requestID, forHTTPHeaderField: "X-Request-ID")
        request.setValue(requestID, forHTTPHeaderField: "Idempotency-Key")
        request.setValue("3.0", forHTTPHeaderField: "X-Basir-Client-Version")
        request.setValue(configuration.clientToken, forHTTPHeaderField: "X-Basir-Client-Token")
    }

    private func validateDownloadedHTTP(_ response: HTTPURLResponse, temporary: URL) throws {
        guard (200..<300).contains(response.statusCode) else {
            let data = (try? Data(contentsOf: temporary, options: [.mappedIfSafe])) ?? Data()
            throw Self.httpError(response, data: Data(data.prefix(64 * 1024)))
        }
    }

    private func validateResultResponse(_ response: HTTPURLResponse) throws {
        if let value = response.value(forHTTPHeaderField: "Content-Length"),
           let length = Int64(value), length > Int64(Self.maximumResponseBytes) {
            throw BasirError.conversionFailed("The server response exceeded the safe size limit.")
        }
    }

    private func verifyAndMove(
        temporary: URL, response: HTTPURLResponse, outputURL: URL,
        expectedPages: Int, expectedTables: Int, expectedImages: Int
    ) throws {
        do {
            try DocxBuilder.validate(url: temporary, expectedPages: expectedPages, expectedTables: expectedTables, expectedImages: expectedImages)
        } catch {
            let type = response.value(forHTTPHeaderField: "Content-Type")?
                .split(separator: ";").first.map(String.init)?.lowercased() ?? "missing"
            if type.contains("json") || type.hasPrefix("text/") || type == "missing" {
                throw BasirError.invalidServerContentType(type)
            }
            throw error
        }
        let actualChecksum = try DocumentInspector.sha256(temporary).lowercased()
        if let expected = response.value(forHTTPHeaderField: "X-Content-SHA256")?.lowercased(),
           !expected.isEmpty,
           actualChecksum != expected {
            throw BasirError.checksumMismatch
        }
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        try FileManager.default.moveItem(at: temporary, to: outputURL)
        try FileAccess.protect(outputURL, excludedFromBackup: false)
    }

    private static func validateHTTP(_ response: HTTPURLResponse, data: Data) throws {
        guard (200..<300).contains(response.statusCode) else {
            throw httpError(response, data: data)
        }
    }

    private static func httpError(_ response: HTTPURLResponse, data: Data) -> Error {
        if response.statusCode == 401 || response.statusCode == 403 {
            return BasirError.authenticationFailed
        }
        if response.statusCode == 429 {
            return BasirError.rateLimited(retryAfter(response))
        }
        var message = String(data: data.prefix(600), encoding: .utf8) ?? ""
        message = message.replacingOccurrences(of: #"[\r\n]+"#, with: " ", options: .regularExpression)
        return BasirError.conversionFailed("Server HTTP \(response.statusCode): \(message)")
    }

    private static func isRetryable(_ error: Error) -> Bool {
        if let url = error as? URLError {
            return [.cancelled, .timedOut, .networkConnectionLost, .notConnectedToInternet,
                    .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed].contains(url.code)
        }
        if let basirError = error as? BasirError, case .rateLimited = basirError {
            return true
        }
        return false
    }

    private static func retryAfter(_ response: HTTPURLResponse) -> TimeInterval? {
        guard let raw = response.value(forHTTPHeaderField: "Retry-After") else { return nil }
        if let seconds = TimeInterval(raw) { return max(0, seconds) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter.date(from: raw).map { max(0, $0.timeIntervalSinceNow) }
    }

    private static func wait(attempt: Int, response: HTTPURLResponse?) async throws {
        let base = response.flatMap(retryAfter) ?? pow(2, Double(attempt + 1))
        let jitter = Double.random(in: 0.78...1.22)
        let seconds = min(60, max(0.25, base * jitter))
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

}
