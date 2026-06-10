import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum GeminiError: Error {
    case missingApiKey
    case http(status: Int, body: String)
    case decode(String)
    case network(Error)
    case cancelled
}

struct GeminiClient {
    static let baseURL = "https://generativelanguage.googleapis.com/v1beta"
    static let uploadBaseURL = "https://generativelanguage.googleapis.com/upload/v1beta/files"
    static let maxOutputTokens = 65_536
    static let maxInlineImageBytes = 15 * 1_024 * 1_024
    static let maxInlineImagesBytes = 30 * 1_024 * 1_024
    static let maxUserMessageBytes = 2 * 1_024 * 1_024
    static let maxSystemInstructionBytes = 256 * 1_024
    static let userAgent = "Basir-iOS/4.4.0"

    static func generateResult(
        apiKey: String,
        model: String,
        systemText: String,
        userMessage: String,
        imageData: Data?,
        mimeType: String?,
        policy: AITaskPolicy,
        responseSchemaOverride: [String: Any]? = nil,
        includeResponseSchema: Bool = true
    ) async throws -> AIGenerationResult {
        try validateTextEnvelope(systemText: systemText, userMessage: userMessage)
        var parts: [[String: Any]] = [["text": userMessage]]
        if let imageData {
            let resolvedMime = mimeType?.isEmpty == false ? mimeType! : "image/jpeg"
            try validateInlineImage(imageData, mimeType: resolvedMime)
            parts.append(inlinePart(data: imageData, mimeType: resolvedMime))
        }
        let body = generationBody(
            systemText: systemText,
            userParts: parts,
            maxOutputTokens: policy.maxOutputTokens,
            responseSchema: includeResponseSchema ? (responseSchemaOverride ?? policy.responseSchema) : nil,
            temperature: policy.temperature,
            thinkingLevel: policy.thinkingLevel
        )
        let json = try await post(
            model: model,
            apiKey: apiKey,
            body: body,
            timeout: policy.timeoutSeconds
        )
        return try extractGenerationResult(from: json)
    }

    static func generateText(
        apiKey: String,
        model: String,
        systemText: String,
        userMessage: String
    ) async throws -> String {
        try validateTextEnvelope(systemText: systemText, userMessage: userMessage)
        let body = generationBody(
            systemText: systemText,
            userParts: [["text": userMessage]],
            maxOutputTokens: 16_384,
            responseSchema: nil
        )
        return try extractTextResponse(from: await post(model: model, apiKey: apiKey, body: body))
    }

    static func generateWithImage(
        apiKey: String,
        model: String,
        systemText: String,
        userMessage: String,
        imageData: Data,
        mimeType: String
    ) async throws -> String {
        try validateTextEnvelope(systemText: systemText, userMessage: userMessage)
        try validateInlineImage(imageData, mimeType: mimeType)
        let body = generationBody(
            systemText: systemText,
            userParts: [["text": userMessage], inlinePart(data: imageData, mimeType: mimeType)],
            maxOutputTokens: 16_384,
            responseSchema: nil
        )
        return try extractTextResponse(from: await post(model: model, apiKey: apiKey, body: body))
    }

    static func generateJsonStringWithImage(
        apiKey: String,
        model: String,
        systemText: String,
        userMessage: String,
        imageData: Data,
        mimeType: String,
        maxOutputTokens: Int = 1_024,
        responseSchema: [String: Any]? = nil
    ) async throws -> String {
        try validateTextEnvelope(systemText: systemText, userMessage: userMessage)
        try validateInlineImage(imageData, mimeType: mimeType)
        let body = generationBody(
            systemText: systemText,
            userParts: [["text": userMessage], inlinePart(data: imageData, mimeType: mimeType)],
            maxOutputTokens: maxOutputTokens,
            responseSchema: responseSchema
        )
        return try extractTextResponse(from: await post(model: model, apiKey: apiKey, body: body))
    }

    static func generateJsonStringWithImages(
        apiKey: String,
        model: String,
        systemText: String,
        userMessage: String,
        images: [Data],
        mimeType: String,
        maxOutputTokens: Int = maxOutputTokens,
        responseSchema: [String: Any]? = nil
    ) async throws -> String {
        try validateTextEnvelope(systemText: systemText, userMessage: userMessage)
        guard !images.isEmpty else { throw GeminiError.decode("no images supplied") }
        guard images.reduce(0, { $0 + $1.count }) <= maxInlineImagesBytes else {
            throw GeminiError.decode("combined images exceed the safe request limit")
        }
        try images.forEach { try validateInlineImage($0, mimeType: mimeType) }
        var parts: [[String: Any]] = [["text": userMessage]]
        parts.append(contentsOf: images.map { inlinePart(data: $0, mimeType: mimeType) })
        let body = generationBody(
            systemText: systemText,
            userParts: parts,
            maxOutputTokens: maxOutputTokens,
            responseSchema: responseSchema
        )
        return try extractTextResponse(from: await post(model: model, apiKey: apiKey, body: body))
    }

    static func generateJsonWithImage(
        apiKey: String,
        model: String,
        systemText: String,
        userMessage: String,
        imageData: Data,
        mimeType: String,
        maxOutputTokens: Int = 1_024,
        responseSchema: [String: Any]? = nil
    ) async throws -> [String: Any] {
        let text = try await generateJsonStringWithImage(
            apiKey: apiKey,
            model: model,
            systemText: systemText,
            userMessage: userMessage,
            imageData: imageData,
            mimeType: mimeType,
            maxOutputTokens: maxOutputTokens,
            responseSchema: responseSchema
        )
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GeminiError.decode("response was not valid JSON")
        }
        return object
    }

    struct UploadedFile {
        let name: String
        let uri: String
        let mimeType: String
    }

    static func uploadFile(
        apiKey: String,
        fileURL: URL,
        mimeType: String,
        displayName: String = "basir-document"
    ) async throws -> UploadedFile {
        try validate(apiKey)
        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let size = values.fileSize, size > 0 else {
            throw GeminiError.decode("upload source is not a readable file")
        }
        let uploadURL = try await startResumableUpload(
            apiKey: apiKey,
            byteCount: size,
            mimeType: mimeType,
            displayName: displayName
        )
        var request = finalizeUploadRequest(url: uploadURL, byteCount: size, mimeType: mimeType)
        request.timeoutInterval = 600
        let response = try await NetworkTransport.upload(for: request, fromFile: fileURL)
        return try parseUploadedFile(response, fallbackMimeType: mimeType)
    }

    static func uploadFile(
        apiKey: String,
        data: Data,
        mimeType: String,
        displayName: String = "basir-document"
    ) async throws -> UploadedFile {
        try validate(apiKey)
        guard !data.isEmpty else { throw GeminiError.decode("upload data was empty") }
        let uploadURL = try await startResumableUpload(
            apiKey: apiKey,
            byteCount: data.count,
            mimeType: mimeType,
            displayName: displayName
        )
        let request = finalizeUploadRequest(url: uploadURL, byteCount: data.count, mimeType: mimeType)
        let response = try await NetworkTransport.upload(for: request, from: data)
        return try parseUploadedFile(response, fallbackMimeType: mimeType)
    }

    static func fileState(apiKey: String, name: String) async throws -> String {
        try validate(apiKey)
        let url = try fileResourceURL(name: name)
        var request = authorizedRequest(url: url, apiKey: apiKey)
        request.timeoutInterval = 30
        let response = try await NetworkTransport.data(for: request)
        try requireSuccess(response)
        guard let object = try? JSONSerialization.jsonObject(with: response.data) as? [String: Any] else {
            throw GeminiError.decode("file state response was not JSON")
        }
        return object["state"] as? String ?? ""
    }

    static func waitForFileActive(
        apiKey: String,
        name: String,
        maxWaitSeconds: Double = 120
    ) async throws {
        let started = Date()
        var delay: UInt64 = 1_000_000_000
        while Date().timeIntervalSince(started) < maxWaitSeconds {
            try Task.checkCancellation()
            let state = try await fileState(apiKey: apiKey, name: name)
            if state == "ACTIVE" { return }
            if state == "FAILED" { throw GeminiError.decode("Gemini failed to process the uploaded file") }
            try await Task.sleep(nanoseconds: delay)
            delay = min(delay * 2, 4_000_000_000)
        }
        throw GeminiError.decode("file processing timeout")
    }

    static func deleteUploadedFile(apiKey: String, name: String) async {
        guard !apiKey.isEmpty, let url = try? fileResourceURL(name: name) else { return }
        var request = authorizedRequest(url: url, apiKey: apiKey)
        request.httpMethod = "DELETE"
        request.timeoutInterval = 30
        _ = try? await NetworkTransport.data(for: request)
    }

    static func generateJsonStringWithFile(
        apiKey: String,
        model: String,
        systemText: String,
        userMessage: String,
        fileUri: String,
        fileMimeType: String,
        maxOutputTokens: Int = maxOutputTokens,
        responseSchema: [String: Any]? = nil
    ) async throws -> String {
        try validateTextEnvelope(systemText: systemText, userMessage: userMessage)
        let body = generationBody(
            systemText: systemText,
            userParts: [
                ["text": userMessage],
                ["fileData": ["fileUri": fileUri, "mimeType": fileMimeType]]
            ],
            maxOutputTokens: maxOutputTokens,
            responseSchema: responseSchema
        )
        return try extractTextResponse(from: await post(
            model: model,
            apiKey: apiKey,
            body: body,
            timeout: 300
        ))
    }

    // Internal for deterministic unit tests.
    static func generationBody(
        systemText: String,
        userParts: [[String: Any]],
        maxOutputTokens: Int,
        responseSchema: [String: Any]?,
        temperature: Double? = nil,
        thinkingLevel: AIThinkingLevel? = nil
    ) -> [String: Any] {
        [
            "system_instruction": ["parts": [["text": systemText]]],
            "contents": [["role": "user", "parts": userParts]],
            "generationConfig": structuredGenerationConfig(
                maxOutputTokens: maxOutputTokens,
                schema: responseSchema,
                temperature: temperature,
                thinkingLevel: thinkingLevel
            )
        ]
    }

    static func structuredGenerationConfig(
        maxOutputTokens: Int,
        schema: [String: Any]?,
        temperature: Double? = nil,
        thinkingLevel: AIThinkingLevel? = nil
    ) -> [String: Any] {
        var config: [String: Any] = [
            "maxOutputTokens": min(max(1, maxOutputTokens), Self.maxOutputTokens)
        ]
        if let temperature {
            config["temperature"] = min(max(temperature, 0.0), 2.0)
        }
        if let thinkingLevel {
            config["thinkingConfig"] = ["thinkingLevel": thinkingLevel.rawValue]
        }
        if let schema {
            config["responseFormat"] = [
                "text": [
                    "mimeType": "application/json",
                    "schema": normalizedJsonSchema(schema)
                ]
            ]
        }
        return config
    }

    static func normalizedJsonSchema(_ value: Any) -> Any {
        if let dictionary = value as? [String: Any] {
            var result: [String: Any] = [:]
            for (key, item) in dictionary {
                if key == "type", let type = item as? String {
                    result[key] = type.lowercased()
                } else {
                    result[key] = normalizedJsonSchema(item)
                }
            }
            return result
        }
        if let array = value as? [Any] {
            return array.map(normalizedJsonSchema)
        }
        return value
    }

    static func makeGenerateRequest(
        model: String,
        apiKey: String,
        body: [String: Any],
        timeout: TimeInterval = 120
    ) throws -> URLRequest {
        try validate(apiKey)
        guard model.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil,
              let url = URL(string: "\(baseURL)/models/\(model):generateContent") else {
            throw GeminiError.decode("invalid Gemini model")
        }
        var request = authorizedRequest(url: url, apiKey: apiKey)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw GeminiError.decode("could not encode request")
        }
        return request
    }

    static func shouldTryNextModel(after error: Error) -> Bool {
        guard let gemini = error as? GeminiError else { return false }
        switch gemini {
        case .network:
            return true
        case let .http(status, _):
            return status == 404 || status == 408 || status == 409 || status == 429 || (500...599).contains(status)
        case let .decode(message):
            let lower = message.lowercased()
            return lower.contains("empty response") || lower.contains("overloaded") || lower.contains("unavailable")
        case .missingApiKey, .cancelled:
            return false
        }
    }

    private static func post(
        model: String,
        apiKey: String,
        body: [String: Any],
        timeout: TimeInterval = 120
    ) async throws -> [String: Any] {
        try Task.checkCancellation()
        let request = try makeGenerateRequest(model: model, apiKey: apiKey, body: body, timeout: timeout)
        let response = try await NetworkTransport.data(for: request)
        try requireSuccess(response)
        guard let object = try? JSONSerialization.jsonObject(with: response.data) as? [String: Any] else {
            throw GeminiError.decode("response was not JSON")
        }
        return object
    }

    private static func inlinePart(data: Data, mimeType: String) -> [String: Any] {
        ["inlineData": ["mimeType": mimeType, "data": data.base64EncodedString()]]
    }

    private static func extractTextResponse(from json: [String: Any]) throws -> String {
        try extractGenerationResult(from: json).text
    }

    static func extractGenerationResult(from json: [String: Any]) throws -> AIGenerationResult {
        if let feedback = json["promptFeedback"] as? [String: Any],
           let reason = feedback["blockReason"] as? String {
            throw GeminiError.decode("blocked: \(reason)")
        }
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            throw GeminiError.decode(message)
        }
        guard let candidates = json["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            throw GeminiError.decode("empty response")
        }
        let joined = parts.compactMap { $0["text"] as? String }.joined()
        guard !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let reason = first["finishReason"] as? String ?? "unknown"
            throw GeminiError.decode("empty response; finish reason: \(reason)")
        }
        let usageObject = json["usageMetadata"] as? [String: Any] ?? [:]
        let usage = AIUsageMetadata(
            promptTokenCount: usageObject["promptTokenCount"] as? Int,
            candidatesTokenCount: usageObject["candidatesTokenCount"] as? Int,
            totalTokenCount: usageObject["totalTokenCount"] as? Int,
            thoughtsTokenCount: usageObject["thoughtsTokenCount"] as? Int,
            cachedContentTokenCount: usageObject["cachedContentTokenCount"] as? Int
        )
        return AIGenerationResult(
            text: joined,
            modelVersion: json["modelVersion"] as? String,
            usage: usage
        )
    }

    private static func startResumableUpload(
        apiKey: String,
        byteCount: Int,
        mimeType: String,
        displayName: String
    ) async throws -> URL {
        try validate(apiKey)
        try validateMimeType(mimeType)
        guard let url = URL(string: uploadBaseURL) else { throw GeminiError.decode("invalid upload URL") }
        var request = authorizedRequest(url: url, apiKey: apiKey)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("resumable", forHTTPHeaderField: "X-Goog-Upload-Protocol")
        request.setValue("start", forHTTPHeaderField: "X-Goog-Upload-Command")
        request.setValue(String(byteCount), forHTTPHeaderField: "X-Goog-Upload-Header-Content-Length")
        request.setValue(mimeType, forHTTPHeaderField: "X-Goog-Upload-Header-Content-Type")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        let safeName = String(displayName.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.prefix(200))
        request.httpBody = try JSONSerialization.data(withJSONObject: ["file": ["display_name": safeName]])

        let response = try await NetworkTransport.data(for: request)
        try requireSuccess(response)
        guard let value = response.response.value(forHTTPHeaderField: "X-Goog-Upload-URL"),
              let uploadURL = URL(string: value),
              uploadURL.scheme?.lowercased() == "https" else {
            throw GeminiError.decode("upload session URL was missing")
        }
        return uploadURL
    }

    private static func finalizeUploadRequest(url: URL, byteCount: Int, mimeType: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        request.setValue(String(byteCount), forHTTPHeaderField: "Content-Length")
        request.setValue("0", forHTTPHeaderField: "X-Goog-Upload-Offset")
        request.setValue("upload, finalize", forHTTPHeaderField: "X-Goog-Upload-Command")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    private static func parseUploadedFile(
        _ response: NetworkResponse,
        fallbackMimeType: String
    ) throws -> UploadedFile {
        try requireSuccess(response)
        guard let object = try? JSONSerialization.jsonObject(with: response.data) as? [String: Any],
              let file = object["file"] as? [String: Any],
              let uri = file["uri"] as? String,
              !uri.isEmpty else {
            throw GeminiError.decode("upload response missing file URI")
        }
        return UploadedFile(
            name: file["name"] as? String ?? "",
            uri: uri,
            mimeType: file["mimeType"] as? String ?? fallbackMimeType
        )
    }

    private static func authorizedRequest(url: URL, apiKey: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    private static func fileResourceURL(name: String) throws -> URL {
        guard name.range(of: #"^files/[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil,
              let root = URL(string: baseURL) else {
            throw GeminiError.decode("invalid uploaded file name")
        }
        return name.split(separator: "/").reduce(root) { $0.appendingPathComponent(String($1)) }
    }

    private static func requireSuccess(_ response: NetworkResponse) throws {
        guard (200..<300).contains(response.statusCode) else {
            AppLogger.networkError("Gemini HTTP \(response.statusCode)")
            throw GeminiError.http(
                status: response.statusCode,
                body: NetworkTransport.boundedBody(response.data)
            )
        }
    }

    private static func validateInlineImage(_ data: Data, mimeType: String) throws {
        guard !data.isEmpty else { throw GeminiError.decode("image data was empty") }
        guard data.count <= maxInlineImageBytes else {
            throw GeminiError.decode("image exceeds the safe inline request limit")
        }
        try validateMimeType(mimeType)
        guard mimeType.lowercased().hasPrefix("image/") else {
            throw GeminiError.decode("inline media must be an image")
        }
    }

    private static func validateMimeType(_ mimeType: String) throws {
        guard !mimeType.isEmpty,
              mimeType.count <= 100,
              mimeType.range(of: #"^[A-Za-z0-9.+-]+/[A-Za-z0-9.+-]+$"#, options: .regularExpression) != nil else {
            throw GeminiError.decode("invalid MIME type")
        }
    }

    static func validateTextEnvelope(systemText: String, userMessage: String) throws {
        guard systemText.utf8.count <= maxSystemInstructionBytes else {
            throw GeminiError.decode("system instruction exceeds the safe request limit")
        }
        guard userMessage.utf8.count <= maxUserMessageBytes else {
            throw GeminiError.decode("request text exceeds the safe request limit")
        }
    }

    private static func validate(_ apiKey: String) throws {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GeminiError.missingApiKey
        }
    }
}

protocol AiProvider {
    func ask(
        task: TaskKind,
        input: String,
        instruction: String?,
        language: AppLanguage,
        imageData: Data?,
        mimeType: String?
    ) async throws -> String
}

struct GeminiAiProvider: AiProvider {
    let settings: BasirSettings

    init(settings: BasirSettings) { self.settings = settings }

    func ask(
        task: TaskKind,
        input: String,
        instruction: String?,
        language: AppLanguage,
        imageData: Data?,
        mimeType: String?
    ) async throws -> String {
        let key = KeychainStore.geminiKey()
        guard !key.isEmpty else { throw GeminiError.missingApiKey }
        let configuration = await MainActor.run {
            let policy = settings.policy(for: task)
            return (
                policy,
                policy.modelCandidates(
                    quickQuality: settings.quickQuality,
                    documentQuality: settings.docQuality
                )
            )
        }
        let policy = configuration.0
        let models = configuration.1
        let requestID = UUID().uuidString
        var lastError: Error = GeminiError.decode("all configured models failed")
        var globalAttempt = 0

        for (modelIndex, model) in models.enumerated() {
            var repairReason: String?
            for localAttempt in 1...policy.attemptsPerModel {
                try Task.checkCancellation()
                globalAttempt += 1
                let systemText = GeminiPrompts.systemPrompt(
                    for: language,
                    task: task,
                    instruction: instruction,
                    repairReason: repairReason
                )
                let userMessage = GeminiPrompts.userMessage(
                    task: task,
                    input: input,
                    hasImage: imageData != nil
                )
                let started = Date()
                do {
                    let schemaOverride = task == .convert && imageData != nil
                        ? AIResponseSchemas.documentPage : nil
                    let hasSchema = (schemaOverride ?? policy.responseSchema) != nil
                    let generation: AIGenerationResult
                    do {
                        generation = try await GeminiClient.generateResult(
                            apiKey: key,
                            model: model,
                            systemText: systemText,
                            userMessage: userMessage,
                            imageData: imageData,
                            mimeType: mimeType,
                            policy: policy,
                            responseSchemaOverride: schemaOverride
                        )
                    } catch {
                        // The provider rejected the structured-output schema
                        // itself (e.g. HTTP 400). Retry the same model once
                        // without the schema; the prompt still requests the
                        // JSON shape and the validator parses it leniently.
                        guard hasSchema, AIExecutionDecision.isStructuredSchemaRejection(error) else { throw error }
                        generation = try await GeminiClient.generateResult(
                            apiKey: key,
                            model: model,
                            systemText: systemText,
                            userMessage: userMessage,
                            imageData: imageData,
                            mimeType: mimeType,
                            policy: policy,
                            responseSchemaOverride: schemaOverride,
                            includeResponseSchema: false
                        )
                    }
                    let validated = try AIResponseValidator.validate(
                        generation.text,
                        task: task,
                        sourceInput: input,
                        policy: policy,
                        responseSchemaOverride: schemaOverride
                    )
                    await recordMetric(
                        requestID: requestID,
                        task: task,
                        transport: "direct",
                        requestedModel: model,
                        generation: generation,
                        started: started,
                        attempt: globalAttempt,
                        success: true,
                        error: nil
                    )
                    return validated
                } catch is CancellationError {
                    throw GeminiError.cancelled
                } catch {
                    lastError = error
                    await recordMetric(
                        requestID: requestID,
                        task: task,
                        transport: "direct",
                        requestedModel: model,
                        generation: nil,
                        started: started,
                        attempt: globalAttempt,
                        success: false,
                        error: error
                    )
                    if localAttempt < policy.attemptsPerModel,
                       policy.repairEnabled,
                       AIExecutionDecision.shouldRetrySameModel(after: error) {
                        repairReason = AIExecutionDecision.boundedFailureReason(error)
                        try Task.checkCancellation()
                        try await Task.sleep(nanoseconds: UInt64(localAttempt) * 450_000_000)
                        continue
                    }
                    break
                }
            }
            guard modelIndex < models.count - 1,
                  AIExecutionDecision.shouldTryFallback(after: lastError) else { throw lastError }
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        throw lastError
    }

    private func recordMetric(
        requestID: String,
        task: TaskKind,
        transport: String,
        requestedModel: String,
        generation: AIGenerationResult?,
        started: Date,
        attempt: Int,
        success: Bool,
        error: Error?
    ) async {
        let shouldRecord = await MainActor.run { !settings.privacyMode }
        guard shouldRecord else { return }
        let usage = generation?.usage ?? .empty
        await AIEngineMetricsStore.shared.record(AIEngineMetric(
            timestamp: Date(),
            requestID: requestID,
            task: task.rawValue,
            transport: transport,
            requestedModel: requestedModel,
            executedModel: generation?.modelVersion,
            durationMilliseconds: max(0, Int(Date().timeIntervalSince(started) * 1_000)),
            attempt: attempt,
            success: success,
            failureCategory: error.map { AIExecutionDecision.boundedFailureReason($0) },
            promptTokens: usage.promptTokenCount,
            outputTokens: usage.candidatesTokenCount,
            thoughtsTokens: usage.thoughtsTokenCount,
            totalTokens: usage.totalTokenCount
        ))
    }
}
