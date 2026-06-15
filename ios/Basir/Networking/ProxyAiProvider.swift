import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct ProxyAiProvider: AiProvider {
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
        let configuration = await MainActor.run {
            let policy = settings.policy(for: task)
            return (
                settings.proxyURL.trimmingCharacters(in: .whitespacesAndNewlines),
                settings.proxyToken.trimmingCharacters(in: .whitespacesAndNewlines),
                policy,
                policy.modelCandidates(
                    quickQuality: settings.quickQuality,
                    documentQuality: settings.docQuality
                )
            )
        }
        guard let url = NetworkTransport.safeProxyEndpoint(from: configuration.0) else {
            throw GeminiError.decode("proxy URL must use HTTPS")
        }
        let policy = configuration.2
        try validateEnvelope(input: input, instruction: instruction, imageData: imageData)

        let requestID = UUID().uuidString
        var lastError: Error = GeminiError.decode("proxy request failed")
        var repairReason: String?
        let hasSchema = (task == .convert && imageData != nil
            ? AIResponseSchemas.documentPage : policy.responseSchema) != nil
        var dropSchema = false

        for attempt in 1...policy.attemptsPerModel {
            try Task.checkCancellation()
            let started = Date()
            do {
                let body = Self.makeBody(
                    task: task,
                    input: input,
                    instruction: instruction,
                    language: language,
                    imageData: imageData,
                    mimeType: mimeType,
                    modelCandidates: configuration.3,
                    policy: policy,
                    requestID: requestID,
                    attempt: attempt,
                    repairReason: repairReason,
                    includeSchema: !dropSchema
                )
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.timeoutInterval = policy.timeoutSeconds
                request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                request.setValue(GeminiClient.userAgent, forHTTPHeaderField: "User-Agent")
                if !configuration.1.isEmpty {
                    request.setValue(configuration.1, forHTTPHeaderField: "X-Basir-Client-Token")
                }
                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                let response = try await NetworkTransport.data(for: request)
                let parsed = try parseResponse(response)
                let schemaOverride = task == .convert && imageData != nil
                    ? AIResponseSchemas.documentPage : nil
                let validated = try AIResponseValidator.validate(
                    parsed.result.text,
                    task: task,
                    sourceInput: input,
                    policy: policy,
                    responseSchemaOverride: schemaOverride
                )
                await recordMetric(
                    requestID: requestID,
                    task: task,
                    generation: parsed.result,
                    started: started,
                    attempt: attempt,
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
                    generation: nil,
                    started: started,
                    attempt: attempt,
                    success: false,
                    error: error
                )
                // If the proxy rejected the structured schema, retry once
                // without it before giving up. The prompt still requests the
                // JSON shape and the validator parses it leniently.
                if hasSchema, !dropSchema, AIExecutionDecision.isStructuredSchemaRejection(error) {
                    dropSchema = true
                    continue
                }
                guard attempt < policy.attemptsPerModel,
                      policy.repairEnabled,
                      AIExecutionDecision.shouldRetrySameModel(after: error) else { throw error }
                repairReason = AIExecutionDecision.boundedFailureReason(error)
                try await Task.sleep(nanoseconds: UInt64(attempt) * 500_000_000)
            }
        }
        throw lastError
    }

    private func validateEnvelope(input: String, instruction: String?, imageData: Data?) throws {
        guard input.utf8.count <= GeminiClient.maxUserMessageBytes else {
            throw GeminiError.decode("request text exceeds the safe proxy limit")
        }
        guard (instruction ?? "").utf8.count <= GeminiClient.maxSystemInstructionBytes else {
            throw GeminiError.decode("proxy instruction exceeds the safe request limit")
        }
        if let imageData, imageData.count > GeminiClient.maxInlineImageBytes {
            throw GeminiError.decode("image exceeds the safe proxy limit")
        }
    }

    static func makeBody(
        task: TaskKind,
        input: String,
        instruction: String?,
        language: AppLanguage,
        imageData: Data?,
        mimeType: String?,
        modelCandidates: [String],
        policy: AITaskPolicy,
        requestID: String,
        attempt: Int,
        repairReason: String?,
        includeSchema: Bool = true
    ) -> [String: Any] {
        let effectiveSchema = includeSchema
            ? (task == .convert && imageData != nil ? AIResponseSchemas.documentPage : policy.responseSchema)
            : nil
        var generation: [String: Any] = [
            "temperature": policy.temperature,
            "max_output_tokens": policy.maxOutputTokens,
            "thinking_level": policy.thinkingLevel.rawValue,
            "timeout_seconds": policy.timeoutSeconds
        ]
        if let effectiveSchema {
            generation["response_format"] = [
                "text": [
                    "mime_type": "application/json",
                    "schema": GeminiClient.normalizedJsonSchema(effectiveSchema)
                ]
            ]
        }
        let boundaryID = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let systemInstruction = GeminiPrompts.systemPrompt(
            for: language,
            task: task,
            instruction: instruction,
            repairReason: repairReason
        )
        let untrustedMessage = GeminiPrompts.userMessage(
            task: task,
            input: input,
            hasImage: imageData != nil,
            boundaryToken: boundaryID
        )
        var body: [String: Any] = [
            "contract_version": AITaskPolicyCatalog.contractVersion,
            "prompt_contract_version": AITaskPolicyCatalog.promptContractVersion,
            "request_id": requestID,
            "attempt": attempt,
            "task": task.rawValue,
            "language": language == .arabic ? "ar" : "en",
            "system_instruction": systemInstruction,
            "untrusted_input": input,
            "untrusted_message": untrustedMessage,
            "model_candidates": modelCandidates,
            "generation_config": generation,
            "validation_profile": policy.validationProfile.rawValue,
            "preserve_critical_tokens": policy.preserveCriticalTokens,
            "repair_enabled": policy.repairEnabled,
            "data_boundary_id": boundaryID
        ]
        // Transitional compatibility fields for an older proxy. Even the
        // legacy pair receives the complete trusted contract and a bounded
        // user message, rather than raw data promoted to an instruction.
        body["input"] = untrustedMessage
        body["instruction"] = systemInstruction
        if let repairReason { body["repair_reason"] = repairReason }
        if let imageData {
            body["image_base64"] = imageData.base64EncodedString()
            body["mime_type"] = mimeType.flatMap { $0.isEmpty ? nil : $0 } ?? "image/jpeg"
        }
        return body
    }

    private func parseResponse(_ response: NetworkResponse) throws -> (result: AIGenerationResult, raw: [String: Any]) {
        guard (200..<300).contains(response.statusCode) else {
            throw GeminiError.http(
                status: response.statusCode,
                body: NetworkTransport.boundedBody(response.data)
            )
        }
        guard let json = try? JSONSerialization.jsonObject(with: response.data) as? [String: Any] else {
            let raw = String(data: response.data, encoding: .utf8) ?? ""
            guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw GeminiError.decode("proxy response was empty")
            }
            return (AIGenerationResult(text: raw, modelVersion: nil, usage: .empty), [:])
        }
        if let error = json["error"] as? String, !error.isEmpty {
            throw GeminiError.http(status: response.statusCode, body: String(error.prefix(2_000)))
        }
        let answer = json["answer"] as? String ?? json["text"] as? String ?? ""
        guard !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GeminiError.decode("proxy response did not contain an answer")
        }
        let usageObject = json["usage_metadata"] as? [String: Any]
            ?? json["usageMetadata"] as? [String: Any]
            ?? [:]
        let usage = AIUsageMetadata(
            promptTokenCount: integer(usageObject, "prompt_token_count", "promptTokenCount"),
            candidatesTokenCount: integer(usageObject, "candidates_token_count", "candidatesTokenCount"),
            totalTokenCount: integer(usageObject, "total_token_count", "totalTokenCount"),
            thoughtsTokenCount: integer(usageObject, "thoughts_token_count", "thoughtsTokenCount"),
            cachedContentTokenCount: integer(usageObject, "cached_content_token_count", "cachedContentTokenCount")
        )
        let model = json["model_version"] as? String ?? json["modelVersion"] as? String
        return (AIGenerationResult(text: answer, modelVersion: model, usage: usage), json)
    }

    private func integer(_ object: [String: Any], _ snake: String, _ camel: String) -> Int? {
        object[snake] as? Int ?? object[camel] as? Int
    }

    private func recordMetric(
        requestID: String,
        task: TaskKind,
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
            transport: "proxy",
            requestedModel: nil,
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
