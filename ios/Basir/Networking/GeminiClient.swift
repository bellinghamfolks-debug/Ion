// GeminiClient.swift
// REST client for Google's Gemini API.
//
// Direct mode only in this scaffold; proxy mode follows the same shape
// (just a different base URL + auth header) and can be added later.
//
// Mirrors GeminiDirectClient.java with two simplifications:
//   - async/await instead of HttpURLConnection on a background thread
//   - URLSession is platform-managed (no manual connection pooling)
//
// What it does NOT yet implement:
//   - Files API upload (uploadFile / waitForFileActive) — needed for
//     batched PDF conversion only
//   - Retry policy with exponential backoff
//   - Chunked streaming responses (for very long generations)
//
// Those are well-defined deltas a later phase can fold in.

import Foundation
import UIKit

enum GeminiError: Error {
    case missingApiKey
    case http(status: Int, body: String)
    case decode(String)
    case network(Error)
    case cancelled
}

struct GeminiClient {
    static let baseURL = "https://generativelanguage.googleapis.com/v1beta"
    static let maxOutputTokens = 16384

    // MARK: - Text-only request

    static func generateText(
        apiKey: String,
        model: String,
        systemText: String,
        userMessage: String
    ) async throws -> String {
        try validate(apiKey)
        let body: [String: Any] = [
            "system_instruction": [
                "parts": [["text": systemText]]
            ],
            "contents": [[
                "role": "user",
                "parts": [["text": userMessage]]
            ]],
            "generationConfig": [
                "maxOutputTokens": maxOutputTokens,
                "temperature": 0.4
            ]
        ]
        let json = try await post(model: model, apiKey: apiKey, body: body)
        return try extractTextResponse(from: json)
    }

    // MARK: - Image + text request

    static func generateWithImage(
        apiKey: String,
        model: String,
        systemText: String,
        userMessage: String,
        imageData: Data,
        mimeType: String
    ) async throws -> String {
        try validate(apiKey)
        let base64 = imageData.base64EncodedString()
        let body: [String: Any] = [
            "system_instruction": [
                "parts": [["text": systemText]]
            ],
            "contents": [[
                "role": "user",
                "parts": [
                    ["text": userMessage],
                    ["inlineData": [
                        "mimeType": mimeType,
                        "data": base64
                    ]]
                ]
            ]],
            "generationConfig": [
                "maxOutputTokens": maxOutputTokens,
                "temperature": 0.3
            ]
        ]
        let json = try await post(model: model, apiKey: apiKey, body: body)
        return try extractTextResponse(from: json)
    }

    // MARK: - JSON-mode image request (v3.2 — live scene guidance)

    /// JSON-mode variant that returns the response as a raw String
    /// (the JSON text). Lets the AiProvider abstraction keep its
    /// `String` return type while the caller decides when to parse.
    /// Used by the Direct provider's `.liveScene` branch.
    static func generateJsonStringWithImage(
        apiKey: String,
        model: String,
        systemText: String,
        userMessage: String,
        imageData: Data,
        mimeType: String,
        maxOutputTokens: Int = 1024
    ) async throws -> String {
        try validate(apiKey)
        let base64 = imageData.base64EncodedString()
        let body: [String: Any] = [
            "system_instruction": [
                "parts": [["text": systemText]]
            ],
            "contents": [[
                "role": "user",
                "parts": [
                    ["text": userMessage],
                    ["inlineData": [
                        "mimeType": mimeType,
                        "data": base64
                    ]]
                ]
            ]],
            "generationConfig": [
                "maxOutputTokens": maxOutputTokens,
                "temperature": 0.2,
                "responseMimeType": "application/json"
            ]
        ]
        let json = try await post(model: model, apiKey: apiKey, body: body)
        return try extractTextResponse(from: json)
    }

    /// JSON-mode generation with MULTIPLE images in one request. Used by
    /// the structured document converter so Gemini sees a whole batch of
    /// pages together and produces CONSISTENT table schemas across them
    /// (the single-image path processed each page in isolation, so the
    /// model invented a different column layout per page). Fewer, larger
    /// calls are also cheaper than one-call-per-page.
    static func generateJsonStringWithImages(
        apiKey: String,
        model: String,
        systemText: String,
        userMessage: String,
        images: [Data],
        mimeType: String,
        maxOutputTokens: Int = maxOutputTokens
    ) async throws -> String {
        try validate(apiKey)
        var parts: [[String: Any]] = [["text": userMessage]]
        for img in images {
            parts.append(["inlineData": [
                "mimeType": mimeType,
                "data": img.base64EncodedString()
            ]])
        }
        let body: [String: Any] = [
            "system_instruction": ["parts": [["text": systemText]]],
            "contents": [["role": "user", "parts": parts]],
            "generationConfig": [
                "maxOutputTokens": maxOutputTokens,
                "temperature": 0.2,
                "responseMimeType": "application/json"
            ]
        ]
        let json = try await post(model: model, apiKey: apiKey, body: body)
        return try extractTextResponse(from: json)
    }

    /// Mirrors GeminiDirectClient.generateJsonWithImage on Android.
    /// Asks Gemini for application/json output so the response can be
    /// parsed deterministically — used by the Live Scene Guidance loop
    /// where every 2 seconds we need {hazard, path, scene} not prose.
    static func generateJsonWithImage(
        apiKey: String,
        model: String,
        systemText: String,
        userMessage: String,
        imageData: Data,
        mimeType: String,
        maxOutputTokens: Int = 1024
    ) async throws -> [String: Any] {
        try validate(apiKey)
        let base64 = imageData.base64EncodedString()
        let body: [String: Any] = [
            "system_instruction": [
                "parts": [["text": systemText]]
            ],
            "contents": [[
                "role": "user",
                "parts": [
                    ["text": userMessage],
                    ["inlineData": [
                        "mimeType": mimeType,
                        "data": base64
                    ]]
                ]
            ]],
            "generationConfig": [
                "maxOutputTokens": maxOutputTokens,
                "temperature": 0.2,
                "responseMimeType": "application/json"
            ]
        ]
        let json = try await post(model: model, apiKey: apiKey, body: body)
        let text = try extractTextResponse(from: json)
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GeminiError.decode("response was not JSON: \(text.prefix(120))")
        }
        return obj
    }

    // MARK: - Internals

    private static func post(model: String,
                              apiKey: String,
                              body: [String: Any],
                              timeout: TimeInterval = 120) async throws -> [String: Any] {
        let urlString = "\(baseURL)/models/\(model):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw GeminiError.http(status: 0, body: "Invalid URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("Basir-iOS/3.2.0", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = timeout

        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw GeminiError.decode("could not encode request: \(error.localizedDescription)")
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw GeminiError.network(error)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let bodyString = String(data: data, encoding: .utf8) ?? ""
        if !(200..<300).contains(status) {
            throw GeminiError.http(status: status, body: bodyString)
        }
        guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GeminiError.decode("response was not JSON")
        }
        return parsed
    }

    /// Pulls the first candidate's text out of a Gemini response payload.
    /// Matches the path used by GeminiDirectClient.extractTextFromResponse
    /// on Android.
    private static func extractTextResponse(from json: [String: Any]) throws -> String {
        if let candidates = json["candidates"] as? [[String: Any]],
           let first = candidates.first,
           let content = first["content"] as? [String: Any],
           let parts = content["parts"] as? [[String: Any]] {
            let texts = parts.compactMap { $0["text"] as? String }
            let joined = texts.joined()
            if !joined.isEmpty { return joined }
        }
        // Surface the safety block reason or any error message Google sent,
        // rather than returning an empty string the user can't act on.
        if let prompt = json["promptFeedback"] as? [String: Any],
           let block = prompt["blockReason"] as? String {
            throw GeminiError.decode("blocked: \(block)")
        }
        if let err = json["error"] as? [String: Any],
           let msg = err["message"] as? String {
            throw GeminiError.decode(msg)
        }
        throw GeminiError.decode("empty response")
    }

    private static func validate(_ apiKey: String) throws {
        guard !apiKey.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw GeminiError.missingApiKey
        }
    }

    // MARK: - Files API (ports GeminiDirectClient upload/wait/fileData)

    struct UploadedFile {
        let name: String      // e.g. "files/abc123"
        let uri: String       // full URI used in fileData.fileUri
        let mimeType: String
    }

    /// Upload raw bytes to the Gemini Files API (the same "raw" protocol
    /// Android uses). The file is processed server-side and is then
    /// referenceable by URI across many generateContent calls for ~48h.
    static func uploadFile(apiKey: String, data: Data,
                           mimeType: String,
                           displayName: String = "basir-doc") async throws -> UploadedFile {
        try validate(apiKey)
        let urlString = "https://generativelanguage.googleapis.com/upload/v1beta/files?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw GeminiError.http(status: 0, body: "Invalid upload URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 600
        req.setValue("raw", forHTTPHeaderField: "X-Goog-Upload-Protocol")
        req.setValue(mimeType, forHTTPHeaderField: "X-Goog-Upload-Header-Content-Type")
        req.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        req.setValue(displayName, forHTTPHeaderField: "X-Goog-File-Display-Name")
        req.setValue("Basir-iOS/3.2.0", forHTTPHeaderField: "User-Agent")

        let (respData, response): (Data, URLResponse)
        do {
            (respData, response) = try await URLSession.shared.upload(for: req, from: data)
        } catch {
            throw GeminiError.network(error)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let bodyString = String(data: respData, encoding: .utf8) ?? ""
        guard (200..<300).contains(status) else {
            throw GeminiError.http(status: status, body: bodyString)
        }
        guard let obj = try? JSONSerialization.jsonObject(with: respData) as? [String: Any],
              let file = obj["file"] as? [String: Any],
              let uri = file["uri"] as? String, !uri.isEmpty else {
            throw GeminiError.decode("upload response missing file uri")
        }
        let name = file["name"] as? String ?? ""
        let mt = file["mimeType"] as? String ?? mimeType
        return UploadedFile(name: name, uri: uri, mimeType: mt)
    }

    /// Current processing state of an uploaded file (PROCESSING/ACTIVE/FAILED).
    static func fileState(apiKey: String, name: String) async throws -> String {
        guard !name.isEmpty else { return "" }
        let urlString = "\(baseURL)/\(name)?key=\(apiKey)"
        guard let url = URL(string: urlString) else { return "" }
        var req = URLRequest(url: url)
        req.timeoutInterval = 30
        req.setValue("Basir-iOS/3.2.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return "" }
        return obj["state"] as? String ?? ""
    }

    /// Poll until the uploaded file becomes ACTIVE (or the budget runs out).
    /// Gemini cannot reference a file in generateContent until it is ACTIVE.
    static func waitForFileActive(apiKey: String, name: String,
                                  maxWaitSeconds: Double = 60) async throws {
        let start = Date()
        var delay: UInt64 = 1_000_000_000   // 1s
        while Date().timeIntervalSince(start) < maxWaitSeconds {
            let state = try await fileState(apiKey: apiKey, name: name)
            if state == "ACTIVE" { return }
            if state == "FAILED" {
                throw GeminiError.decode("Gemini failed to process the uploaded file")
            }
            try? await Task.sleep(nanoseconds: delay)
            delay = min(delay * 2, 4_000_000_000)
        }
    }

    /// generateContent in JSON mode referencing a previously-uploaded file
    /// by URI (so a PDF is uploaded once and reused across page-range
    /// batches — exactly the Android batched-conversion pipeline).
    static func generateJsonStringWithFile(
        apiKey: String,
        model: String,
        systemText: String,
        userMessage: String,
        fileUri: String,
        fileMimeType: String,
        maxOutputTokens: Int = maxOutputTokens
    ) async throws -> String {
        try validate(apiKey)
        let body: [String: Any] = [
            "system_instruction": ["parts": [["text": systemText]]],
            "contents": [[
                "role": "user",
                "parts": [
                    ["text": userMessage],
                    ["fileData": ["fileUri": fileUri, "mimeType": fileMimeType]]
                ]
            ]],
            "generationConfig": [
                "maxOutputTokens": maxOutputTokens,
                "temperature": 0.2,
                "responseMimeType": "application/json"
            ]
        ]
        // Referencing a multi-page PDF makes the model ingest the whole
        // file, so give it generous time before the request times out.
        let json = try await post(model: model, apiKey: apiKey, body: body, timeout: 300)
        return try extractTextResponse(from: json)
    }
}

// MARK: - High-level Provider abstraction

/// Mirrors AiProvider on Android. Calling code just does:
///   try await GeminiAiProvider().ask(task: .ask, input: q, ...)
/// without knowing whether the underlying transport is Direct or Proxy.
protocol AiProvider {
    func ask(task: TaskKind,
             input: String,
             instruction: String?,
             language: AppLanguage,
             imageData: Data?,
             mimeType: String?) async throws -> String
}

struct GeminiAiProvider: AiProvider {
    let settings: BasirSettings

    // No `= .shared` default: that expression is @MainActor-isolated and
    // referencing it from this nonisolated init is an error under Swift 6.
    // AiProviderFactory (which IS @MainActor) passes `.shared` explicitly.
    init(settings: BasirSettings) {
        self.settings = settings
    }

    func ask(task: TaskKind,
             input: String,
             instruction: String?,
             language: AppLanguage,
             imageData: Data?,
             mimeType: String?) async throws -> String {
        let key = KeychainStore.geminiKey()
        guard !key.isEmpty else { throw GeminiError.missingApiKey }
        let model = await MainActor.run { settings.modelFor(task: task) }
        let systemText = GeminiPrompts.systemPrompt(for: language, instruction: instruction)
        // v3.2 — Live scene guidance carries its prompt as `input`
        // (not `instruction`) so the proxy sees the full structured
        // prompt verbatim. The JSON-mode response is requested
        // server-side by responseMimeType=application/json.
        if task == .liveScene, let imageData, let mimeType {
            return try await GeminiClient.generateJsonStringWithImage(
                apiKey: key, model: model,
                systemText: systemText, userMessage: input,
                imageData: imageData, mimeType: mimeType,
                maxOutputTokens: 1024)
        }
        let userMessage = GeminiPrompts.userMessage(
            task: task, input: input,
            instruction: instruction,
            hasImage: imageData != nil
        )
        if let imageData, let mimeType {
            return try await GeminiClient.generateWithImage(
                apiKey: key, model: model,
                systemText: systemText, userMessage: userMessage,
                imageData: imageData, mimeType: mimeType
            )
        }
        return try await GeminiClient.generateText(
            apiKey: key, model: model,
            systemText: systemText, userMessage: userMessage
        )
    }
}
