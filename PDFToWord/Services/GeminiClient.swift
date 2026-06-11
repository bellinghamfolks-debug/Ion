import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

actor GeminiClient {
    private let session: URLSession
    private let decoder = JSONDecoder()
    private static let minimumAcceptanceScore = 0.95
    /// Acceptance gate for the single-pass pipeline. The page is checked
    /// locally against the PDF text layer and on-device OCR; below this the
    /// page is preserved as an image instead of risking invented text.
    private static let singlePassAcceptanceScore = 0.80

    private enum AnalysisPass {
        case primary
        case independent
        case adjudication
    }

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
#if !os(Linux)
            configuration.waitsForConnectivity = true
#endif
            configuration.timeoutIntervalForRequest = 180
            configuration.timeoutIntervalForResource = 240
            configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            configuration.urlCache = nil
            configuration.httpCookieStorage = nil
            self.session = URLSession(configuration: configuration)
        }
    }

    /// Performs both model discovery and a real structured-output request. A model
    /// appearing in the model list alone does not prove that the key, quota and
    /// generation configuration are usable at conversion time.
    func validateKey(_ apiKey: String, model: String) async throws -> [GeminiModelInfo] {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw GeminiError.missingAPIKey }
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000") else {
            throw GeminiError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.setValue(trimmedKey, forHTTPHeaderField: "x-goog-api-key")
        request.timeoutInterval = 30
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GeminiError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw parseAPIError(data: data, response: http)
        }

        let envelope = try decoder.decode(ModelListEnvelope.self, from: data)
        let capable = envelope.models.filter(\.supportsGenerateContent)
        let requested = Self.normalizedModel(model)
        guard !requested.isEmpty,
              capable.contains(where: { $0.shortName == requested }) else {
            throw GeminiError.modelUnavailable(requested.isEmpty ? model : requested)
        }

        try await performStructuredProbe(apiKey: trimmedKey, model: requested)
        return capable.sorted { $0.shortName < $1.shortName }
    }

    func analyzePage(
        pagePDF: Data,
        pageImage: Data?,
        detailTiles: [Data],
        nativeText: String,
        localOCR: LocalOCRReference,
        pageNumber: Int,
        apiKey: String,
        options: ConversionOptions
    ) async throws -> PageAnalysis {
        guard !pagePDF.isEmpty else { throw GeminiError.emptyPageData(pageNumber) }
        guard pagePDF.count < 50 * 1024 * 1024 else { throw GeminiError.fileTooLarge }
        let model = Self.normalizedModel(options.model)
        guard !model.isEmpty else { throw GeminiError.modelUnavailable(options.model) }

        let pageStarted = Date()
        DiagnosticsLog.shared.record("page", "p\(pageNumber) start | model:\(model) | nativeText:\(nativeText.count) chars | image:\(pageImage != nil) | tiles:\(detailTiles.count) | ocrConf:\(String(format: "%.2f", localOCR.averageConfidence))")
        defer {
            DiagnosticsLog.shared.record("page", "p\(pageNumber) done in \(Int(Date().timeIntervalSince(pageStarted) * 1000))ms")
        }

        // Single-pass pipeline (the way fast commercial converters work):
        // one Gemini reading per page, then local verification against the
        // native text layer / on-device OCR, with a whole-page-image fallback
        // when confidence is genuinely low. The previous design ran three
        // sequential model calls per page (primary + independent +
        // adjudication), which took many minutes per page and offered little
        // accuracy benefit over local reference checks.
        var final = try await requestAnalysisPass(
            pagePDF: pagePDF,
            pageImage: pageImage,
            nativeText: nativeText,
            localOCR: localOCR,
            pageNumber: pageNumber,
            apiKey: apiKey,
            options: options,
            model: model,
            pass: .primary
        )

        let confidence = Self.weightedConfidence(final)
        do {
            try Self.validateSemanticQuality(
                analysis: final,
                nativeText: nativeText,
                localOCR: localOCR,
                options: options
            )
        } catch {
            // Semantic verification can fail on malformed text layers, skewed scans,
            // unusual bidirectional ordering, or uncertain handwriting. When a page
            // image is available, preserve the page exactly instead of aborting the
            // entire document or inventing editable text.
            if pageImage != nil {
                final.source = .visualPageFallback
                final.preserveWholePageImage = true
                final.qualityScore = 0
                final.agreementScore = confidence
                final.verificationPasses = 1
                if final.wholePageAltText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    final.wholePageAltText = Self.visualFallbackDescription(
                        analysis: final,
                        pageNumber: pageNumber
                    )
                }
                final.warnings.append(L10n.format(
                    "حُفظت الصفحة %d كصورة كاملة لأن التحقق الدلالي لم ينجح بثقة كافية.",
                    pageNumber
                ))
                final.warnings = Array(Set(final.warnings)).sorted()
                return final
            }
            throw error
        }

        let referenceScore = Self.referenceAgreement(
            analysis: final,
            nativeText: nativeText,
            localOCR: localOCR,
            fallback: confidence
        )
        let qualityScore = 0.75 * referenceScore + 0.25 * confidence

        final.qualityScore = qualityScore
        final.agreementScore = referenceScore
        final.verificationPasses = 1

        if qualityScore >= Self.singlePassAcceptanceScore,
           final.readingOrderConfidence >= Self.singlePassAcceptanceScore {
            final.source = .geminiConsensus
            return final
        }

        // A low-confidence scan must never be converted into invented editable text.
        // Preserve the entire page as a high-resolution image so visual fidelity remains
        // exact, while retaining the adjudicated description as accessible alt text.
        if pageImage != nil {
            final.source = .visualPageFallback
            final.preserveWholePageImage = true
            if final.wholePageAltText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                final.wholePageAltText = Self.visualFallbackDescription(
                    analysis: final,
                    pageNumber: pageNumber
                )
            }
            final.warnings.append(L10n.format(
                "حُفظت الصفحة %d كصورة كاملة لأن دقة النص أو ترتيب القراءة لم يبلغا بوابة القبول.",
                pageNumber
            ))
            final.warnings = Array(Set(final.warnings)).sorted()
            return final
        }

        throw GeminiError.qualityBelowAcceptance(
            page: pageNumber,
            score: qualityScore,
            agreement: referenceScore,
            required: Self.singlePassAcceptanceScore,
            kind: final.contentKind
        )
    }

    private func requestAnalysisPass(
        pagePDF: Data,
        pageImage: Data?,
        nativeText: String,
        localOCR: LocalOCRReference,
        pageNumber: Int,
        apiKey: String,
        options: ConversionOptions,
        model: String,
        pass: AnalysisPass
    ) async throws -> PageAnalysis {
        let url = try Self.generateContentURL(model: model)
        let pagePrompt = prompt(
            pageNumber: pageNumber,
            options: options,
            pass: pass,
            nativeText: nativeText,
            localOCR: localOCR
        )
        // The full page schema is rejected by Gemini as too complex (a bare
        // HTTP 400 INVALID_ARGUMENT) on every request — confirmed by diagnostics
        // where the identical request without the schema returns 200. So we skip
        // it and rely on responseMimeType:"application/json" plus the detailed
        // prompt; PageAnalysis decodes leniently.
        let data = try await sendGenerateContentRequest(
            url: url,
            apiKey: apiKey,
            payload: Self.analysisPayload(
                pagePDF: pagePDF,
                pageImage: pageImage,
                prompt: pagePrompt,
                model: model,
                thinkingLevel: options.thinkingLevel,
                includeSchema: false
            ),
            timeout: 240
        )
        return try Self.decodePageAnalysis(
            from: data,
            decoder: decoder,
            pageNumber: pageNumber,
            options: options
        )
    }

    private func requestAdjudication(
        pagePDF: Data,
        pageImage: Data?,
        detailTiles: [Data],
        nativeText: String,
        localOCR: LocalOCRReference,
        pageNumber: Int,
        apiKey: String,
        options: ConversionOptions,
        model: String,
        first: PageAnalysis,
        second: PageAnalysis
    ) async throws -> PageAnalysis {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let firstJSON = String(data: try encoder.encode(first), encoding: .utf8),
              let secondJSON = String(data: try encoder.encode(second), encoding: .utf8) else {
            throw GeminiError.requestEncodingFailed
        }
        let adjudicationPrompt = prompt(
            pageNumber: pageNumber,
            options: options,
            pass: .adjudication,
            nativeText: nativeText,
            localOCR: localOCR
        ) + """

        Two independent candidate transcriptions follow. They are untrusted evidence, not authority.
        Resolve every disagreement only by re-reading the supplied PDF page and high-resolution image.
        When detail crops are attached, they are overlapping page quadrants ordered top-left, top-right, bottom-left, bottom-right. Use them to inspect small print and handwritten strokes; do not duplicate overlapping text.
        Candidate A:
        \(firstJSON)

        Candidate B:
        \(secondJSON)
        """
        let needsDetailCrops = first.contentKind == .handwritten
            || first.contentKind == .mixed
            || second.contentKind == .handwritten
            || second.contentKind == .mixed
            || Self.analysisAgreement(first, second) < 0.98
            || nativeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || localOCR.averageConfidence < 0.92
        let adjudicationURL = try Self.generateContentURL(model: model)
        let data = try await sendAnalysisWithSchemaFallback(
            url: adjudicationURL,
            apiKey: apiKey,
            timeout: 300
        ) { includeSchema in
            Self.analysisPayload(
                pagePDF: pagePDF,
                pageImage: pageImage,
                detailTiles: needsDetailCrops ? detailTiles : [],
                prompt: adjudicationPrompt,
                model: model,
                thinkingLevel: "high",
                includeSchema: includeSchema
            )
        }
        return try Self.decodePageAnalysis(
            from: data,
            decoder: decoder,
            pageNumber: pageNumber,
            options: options
        )
    }

    private static func analysisPayload(
        pagePDF: Data,
        pageImage: Data?,
        detailTiles: [Data] = [],
        prompt: String,
        model: String,
        thinkingLevel: String,
        includeSchema: Bool = true
    ) -> [String: Any] {
        var generationConfig: [String: Any] = [
            "mediaResolution": "MEDIA_RESOLUTION_HIGH",
            "maxOutputTokens": Self.maximumOutputTokens(for: model),
            // The Gemini REST API returns plain text unless JSON is requested
            // explicitly. The literal MIME string "application/json" is required
            // here (there is no "APPLICATION_JSON" enum), and these keys live
            // directly inside generationConfig — not under a "responseFormat" wrapper.
            "responseMimeType": "application/json"
        ]
        if includeSchema {
            // The page schema relies on `additionalProperties:false`, which the
            // OpenAPI-subset `responseSchema` field rejects. `responseJsonSchema`
            // accepts the full JSON-Schema feature set. Exactly one of the two may
            // be present; the schema-complexity fallback below drops it on a 400.
            generationConfig["responseJsonSchema"] = Self.pageSchema
        }
        if Self.supportsThinkingLevel(model) {
            generationConfig["thinkingConfig"] = [
                "thinkingLevel": Self.normalizedThinkingLevel(thinkingLevel, model: model)
            ]
        }

        var parts: [[String: Any]] = [[
            "inlineData": [
                "mimeType": "application/pdf",
                "data": pagePDF.base64EncodedString()
            ]
        ]]
        if let pageImage, !pageImage.isEmpty {
            parts.append([
                "inlineData": [
                    "mimeType": "image/png",
                    "data": pageImage.base64EncodedString()
                ]
            ])
        }
        for (index, tile) in detailTiles.prefix(4).enumerated() where !tile.isEmpty {
            parts.append(["text": "Overlapping detail crop \(index + 1) of \(min(4, detailTiles.count))."])
            parts.append([
                "inlineData": [
                    "mimeType": "image/png",
                    "data": tile.base64EncodedString()
                ]
            ])
        }
        parts.append(["text": prompt])
        return [
            "contents": [["role": "user", "parts": parts]],
            "generationConfig": generationConfig
        ]
    }

    private static func decodePageAnalysis(
        from data: Data,
        decoder: JSONDecoder,
        pageNumber: Int,
        options: ConversionOptions
    ) throws -> PageAnalysis {
        let text = try Self.extractCandidateText(from: data, decoder: decoder)
        let cleaned = Self.removeCodeFence(from: text)
        guard let json = cleaned.data(using: .utf8), !json.isEmpty else {
            throw GeminiError.emptyModelOutput
        }
        do {
            let decoded = try decoder.decode(PageAnalysis.self, from: json)
            return try Self.normalize(decoded, pageNumber: pageNumber, options: options)
        } catch let error as GeminiError {
            throw error
        } catch {
            throw GeminiError.invalidStructuredOutput(L10n.text("تعذر مطابقة الاستجابة مع مخطط الصفحة المطلوب."))
        }
    }

    private func performStructuredProbe(apiKey: String, model: String) async throws {
        let url = try Self.generateContentURL(model: model)
        var generationConfig: [String: Any] = [
            "responseMimeType": "application/json",
            "responseJsonSchema": [
                "type": "object",
                "additionalProperties": false,
                "properties": ["ok": ["type": "boolean"]],
                "required": ["ok"]
            ],
            // Must comfortably exceed the model's thinking budget: Gemini 3
            // (especially Pro, where "minimal" is promoted to "low") spends
            // hidden thinking tokens before emitting the visible JSON, so a
            // tiny cap finishes as MAX_TOKENS with no output. The schema keeps
            // the actual answer to a few tokens regardless.
            "maxOutputTokens": 4096
        ]
        if Self.supportsThinkingLevel(model) {
            generationConfig["thinkingConfig"] = ["thinkingLevel": Self.normalizedThinkingLevel("minimal", model: model)]
        }

        let payload: [String: Any] = [
            "contents": [[
                "role": "user",
                "parts": [["text": "Return {\"ok\":true}. Return no other content."]]
            ]],
            "generationConfig": generationConfig
        ]

        // The probe must tolerate transient provider overload (HTTP 503 /
        // "high demand"), which is unrelated to the key or model validity.
        var lastError: Error = GeminiError.structuredOutputProbeFailed
        for attempt in 1...3 {
            do {
                let data = try await sendGenerateContentRequest(
                    url: url,
                    apiKey: apiKey,
                    payload: payload,
                    timeout: 45
                )
                let text = try Self.extractCandidateText(from: data, decoder: decoder)
                let cleaned = Self.removeCodeFence(from: text)
                guard let json = cleaned.data(using: .utf8),
                      let probe = try? decoder.decode(StructuredProbe.self, from: json),
                      probe.ok else {
                    throw GeminiError.structuredOutputProbeFailed
                }
                return
            } catch let error as GeminiError where Self.isTransient(error) && attempt < 3 {
                lastError = error
                let seconds = min(error.retryAfter ?? Double(attempt * 2), 8)
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
        }
        throw lastError
    }

    /// Transient, retryable provider conditions (overload / rate limit /
    /// temporary 5xx) as opposed to a genuine key or model problem.
    private static func isTransient(_ error: GeminiError) -> Bool {
        switch error {
        case .modelUnavailable:
            return true
        case .httpStatus(let status, _, _):
            return status == 429 || (500...599).contains(status)
        default:
            return false
        }
    }

    /// Sends a page-analysis request and, if the provider rejects the request
    /// with a bare INVALID_ARGUMENT (the full structured-output page schema can
    /// exceed Gemini's schema-complexity limit), retries once without the
    /// schema. The prompt already specifies the exact JSON structure and the
    /// response is decoded leniently, so the conversion still proceeds.
    private func sendAnalysisWithSchemaFallback(
        url: URL,
        apiKey: String,
        timeout: TimeInterval,
        makePayload: (_ includeSchema: Bool) -> [String: Any]
    ) async throws -> Data {
        do {
            return try await sendGenerateContentRequest(url: url, apiKey: apiKey, payload: makePayload(true), timeout: timeout)
        } catch let error as GeminiError where Self.isInvalidArgument(error) {
            return try await sendGenerateContentRequest(url: url, apiKey: apiKey, payload: makePayload(false), timeout: timeout)
        }
    }

    private static func isInvalidArgument(_ error: GeminiError) -> Bool {
        guard case let .httpStatus(status, message, _) = error, status == 400 else { return false }
        let lower = message.lowercased()
        return lower.contains("invalid argument")
            || lower.contains("invalid_argument")
            || lower.contains("schema")
            || lower.contains("response_json_schema")
            || lower.contains("responsejsonschema")
            || lower.contains("unknown name")
    }

    private func sendGenerateContentRequest(
        url: URL,
        apiKey: String,
        payload: [String: Any],
        timeout: TimeInterval
    ) async throws -> Data {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw GeminiError.missingAPIKey }
        let body: Data
        do {
            body = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            throw GeminiError.requestEncodingFailed
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(trimmedKey, forHTTPHeaderField: "x-goog-api-key")

        let endpoint = url.lastPathComponent
        let hasSchema = ((payload["generationConfig"] as? [String: Any])?["responseJsonSchema"]) != nil
        let thinking = ((payload["generationConfig"] as? [String: Any])?["thinkingConfig"] as? [String: Any])?["thinkingLevel"] as? String ?? "default"
        DiagnosticsLog.shared.record("gemini→", "POST \(endpoint) | body \(body.count / 1024)KB | schema:\(hasSchema) | thinking:\(thinking) | timeout:\(Int(timeout))s")
        let started = Date()
        do {
            let (data, response) = try await session.data(for: request)
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            guard let http = response as? HTTPURLResponse else {
                DiagnosticsLog.shared.record("gemini✗", "non-HTTP response after \(ms)ms")
                throw GeminiError.invalidResponse
            }
            guard (200..<300).contains(http.statusCode) else {
                let err = parseAPIError(data: data, response: http)
                DiagnosticsLog.shared.record("gemini✗", "HTTP \(http.statusCode) after \(ms)ms | \(Self.boundedBody(data))")
                throw err
            }
            let finish = Self.finishReasonHint(data)
            DiagnosticsLog.shared.record("gemini✓", "HTTP \(http.statusCode) in \(ms)ms | \(data.count / 1024)KB\(finish.isEmpty ? "" : " | finish:\(finish)")")
            return data
        } catch let error as GeminiError {
            throw error
        } catch {
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            DiagnosticsLog.shared.record("gemini✗", "transport error after \(ms)ms | \(error.localizedDescription)")
            throw error
        }
    }

    /// A bounded excerpt of a response/error body for diagnostics (never the key).
    private static func boundedBody(_ data: Data) -> String {
        let raw = String(data: data.prefix(600), encoding: .utf8) ?? "<binary \(data.count) bytes>"
        return raw.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
    }

    /// Extracts a finishReason from a candidates response, if present.
    private static func finishReasonHint(_ data: Data) -> String {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = obj["candidates"] as? [[String: Any]],
              let reason = candidates.first?["finishReason"] as? String else { return "" }
        return reason
    }

    private func prompt(
        pageNumber: Int,
        options: ConversionOptions,
        pass: AnalysisPass,
        nativeText: String,
        localOCR: LocalOCRReference
    ) -> String {
        let passInstruction: String
        switch pass {
        case .primary:
            passInstruction = "Perform the first forensic transcription and layout reconstruction. Inspect the complete page before emitting any block."
        case .independent:
            passInstruction = "Perform an independent second reconstruction. Re-read every character, table edge, formatting change and spatial region without trusting the first pass."
        case .adjudication:
            passInstruction = "Act as the final adjudicator. Resolve every disagreement from the visual page itself, character by character and cell by cell."
        }

        var instructions = """
        Convert page \(pageNumber) into a lossless, editable, reading-order representation for Microsoft Word.
        \(passInstruction)

        NON-NEGOTIABLE TRANSCRIPTION RULES
        1. Preserve every visible character exactly: Arabic diacritics, hamza forms, punctuation, symbols, checkboxes, non-breaking hyphens, repeated spaces, identifiers, URLs, e-mail addresses, paths, dates, times, currency and decimal separators. Never translate, summarize, normalize, silently correct or infer missing text.
        2. Put blocks in the true reading order. For multi-column pages, finish the first logical column before the next. Place side boxes only where they occur in the intended reading sequence. Set readingOrderConfidence honestly.
        3. Preserve bidirectional text. Split mixed Arabic/Latin content into runs whenever direction or formatting changes. A run's text must concatenate exactly to the block text. Never reverse identifiers such as AX19, telephone numbers, URLs, file paths or monetary values.
        4. Preserve inline formatting in runs: bold, italic, underline, strike, highlight, text color, exact font size when visually clear, superscript and subscript. Preserve Unicode symbols literally. Use runs=[] only when the block has no editable text.
        5. Headings, paragraphs, quotations, captions, text boxes, equations, form fields, headers, footers, watermarks and footnotes must remain distinct block types. Use bookmark for stable section anchors. Use keepWithNext for headings and captions that belong to the following object.
        6. For lists, emit one block per item with type bullet or numbered. Set listLevel from 0 through 8, listStyle, and listStart. Do not type the generated bullet/number into text unless it is visibly part of the source content rather than list numbering.
        7. For tables, use tableCells as the authoritative structure. Set zero-based row and column, rowSpan, columnSpan, header status and alignment. Preserve empty cells. Set tableRowCount, tableColumnCount and repeatHeaderRows. Never invent a table for a form, stamp, signature or merely aligned prose. Legacy rows should contain a simple rectangular text view of the same table for verification.
        8. A merged cell appears once at its top-left origin with its full rowSpan and columnSpan. Do not duplicate its text into covered cells. Preserve logical relationships between multi-level headers and values.
        9. For equations, use type equation and encode superscripts/subscripts in runs. Preserve a bounding box so the renderer can fall back to the visual crop if the equation cannot be represented safely.
        10. For rotated or freely positioned text, use type textBox, set rotationDegrees, exact boundingBox and editable runs. Do not move edge labels into unrelated paragraphs.
        11. Headers and footers must be identified only as header/footer blocks. A watermark is one watermark block, never repeated between body paragraphs.
        12. Footnote body blocks use type footnote and footnoteID. The exact reference position in body text is represented by a run with the same footnoteReferenceID and normally empty text.
        13. External links use linkURL on the linked run while preserving the visible link text. Internal references use internalLink matching a block bookmark.
        14. Treat handwriting and scans as first-class sources. Never replace an uncertain stroke with a plausible word. If the page is too faint, skewed, damaged or spatially complex to reconstruct at 95% confidence, set preserveWholePageImage=true and provide a precise wholePageAltText. Still transcribe only text that is genuinely readable.
        15. Set contentKind to printed, handwritten, mixed, imageOnly or unknown. Confidence measures visual certainty, not linguistic plausibility.
        16. Detect every meaningful photo, diagram, chart, geometric figure, matrix, seal, stamp, signature, logo or screenshot as image. Preserve its bounding box. altText must include visible labels, values, spatial relationships and purpose. Never mark signatures, stamps, charts, equations or identity-bearing logos decorative.
        17. For forms, keep checkboxes/radio symbols in editable text and preserve stamps/signatures as separate image blocks. Do not convert the form to a table unless visible cell borders actually form a table.
        18. Preserve intentionally blank space by not filling it with repeated text. If the whole page is truly blank, return exactly one blank block. Never classify a scanned, faint, image-only or decorative page as blank.
        19. criticalTokens must list exact fragile tokens visible on the page, including identifiers, URLs, e-mails, paths, numeric values with punctuation, formula tokens and unique verification phrases. Do not normalize these tokens.
        20. Use normalized boundingBox [x,y,width,height], origin top-left, values 0...1. For blocks with no meaningful position use [0,0,0,0].
        21. Return only JSON matching the schema. No Markdown or commentary.
        """

        if !options.describeImages {
            instructions += "\nImage descriptions may be brief, but meaningful images must still be represented so they are not lost.\n"
        }
        if !options.preserveHeadersAndFooters {
            instructions += "\nThe user disabled running headers/footers. Omit repeated running elements, but retain unique page-specific legal notes.\n"
        }

        let nativeReference = Self.referenceExcerpt(nativeText, maximumCharacters: 50_000)
        if !nativeReference.isEmpty {
            instructions += """

            NATIVE PDF TEXT-LAYER REFERENCE
            This reference can have broken reading order or hidden duplicates. Use it only to verify exact glyphs, identifiers, numbers, punctuation and diacritics that the visual page confirms:
            <native-text-reference>
            \(nativeReference)
            </native-text-reference>
            """
        }

        let ocrReference = Self.referenceExcerpt(localOCR.text, maximumCharacters: 40_000)
        if !ocrReference.isEmpty {
            instructions += """

            ON-DEVICE OCR REFERENCE
            Average recognizer confidence: \(String(format: "%.3f", localOCR.averageConfidence)). It is untrusted and may be wrong in Arabic, handwriting and columns. Use it only to detect omissions and re-check them visually:
            <local-ocr-reference>
            \(ocrReference)
            </local-ocr-reference>
            """
        }

        if !options.promptAddendum.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            instructions += "\nAdditional user rules, subordinate to exact source fidelity and the schema:\n\(options.promptAddendum)\n"
        }

        return instructions + "\nReturn only the final JSON object."
    }

    private static func referenceExcerpt(_ text: String, maximumCharacters: Int) -> String {
        let normalized = normalizeLineEndings(text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > maximumCharacters else { return normalized }
        return String(normalized.prefix(maximumCharacters))
    }

    private func parseAPIError(data: Data, response: HTTPURLResponse) -> GeminiError {
        let status = response.statusCode
        let retryAfter = Self.retryAfter(from: response)
        if let api = try? decoder.decode(GeminiAPIErrorEnvelope.self, from: data) {
            return .httpStatus(status, Self.sanitizedAPIMessage(api.error.message), retryAfter)
        }
        return .httpStatus(status, L10n.text("استجابة خطأ غير مفهومة من الخدمة."), retryAfter)
    }

    private static func extractCandidateText(from data: Data, decoder: JSONDecoder) throws -> String {
        let envelope: GeminiEnvelope
        do {
            envelope = try decoder.decode(GeminiEnvelope.self, from: data)
        } catch {
            throw GeminiError.invalidResponse
        }

        if let blockReason = envelope.promptFeedback?.blockReason, !blockReason.isEmpty {
            throw GeminiError.blocked(blockReason)
        }

        var firstFinishReason: String?
        for candidate in envelope.candidates ?? [] {
            if firstFinishReason == nil { firstFinishReason = candidate.finishReason }
            let text = (candidate.content?.parts ?? [])
                .filter { $0.thought != true }
                .compactMap(\.text)
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            let reason = candidate.finishReason?.uppercased() ?? ""
            let accepted = reason.isEmpty || reason == "STOP" || reason == "FINISH_REASON_UNSPECIFIED"
            guard accepted else { throw GeminiError.incompleteCandidate(reason) }
            return text
        }
        throw GeminiError.noCandidate(firstFinishReason ?? L10n.text("غير معروف"))
    }

    private static func normalize(
        _ input: PageAnalysis,
        pageNumber: Int,
        options: ConversionOptions
    ) throws -> PageAnalysis {
        var warnings = input.warnings
        var blocks: [DocumentBlock] = []
        blocks.reserveCapacity(min(input.blocks.count, 800))
        var nextFootnoteID = 1

        if input.pageNumber != pageNumber {
            warnings.append(L10n.format("صُحح رقم الصفحة الذي أعاده النموذج من %d إلى %d.", input.pageNumber, pageNumber))
        }
        if input.blocks.count > 800 {
            throw GeminiError.excessiveBlockCount(page: pageNumber, count: input.blocks.count)
        }

        for var block in input.blocks {
            block.text = cleanSourceText(block.text)
            block.altText = cleanSourceText(block.altText).trimmingCharacters(in: .whitespacesAndNewlines)
            block.runs = Array(block.runs.prefix(1_500)).map(normalizeRun)
            let runText = block.runs.map(\.text).joined()
            if !runText.isEmpty {
                if !block.text.isEmpty && block.text != runText {
                    warnings.append(L10n.format("صُحح عدم تطابق التنسيق الداخلي مع نص كتلة في الصفحة %d.", pageNumber))
                }
                block.text = runText
            } else if !block.text.isEmpty,
                      block.type != .table,
                      block.type != .image,
                      block.type != .pageImage,
                      block.type != .watermark {
                block.runs = [TextRun(text: block.text, direction: block.direction)]
            }

            block.rows = block.rows.prefix(300).map { row in
                Array(row.prefix(120)).map { cleanSourceText($0) }
            }
            block.tableCells = Array(block.tableCells.prefix(5_000)).map(normalizeCell)
            block.confidence = min(1, max(0, block.confidence.isFinite ? block.confidence : 0))
            block.boundingBox = normalizedBox(block.boundingBox)
            block.listLevel = max(0, min(8, block.listLevel))
            block.listStart = max(1, block.listStart)
            block.rotationDegrees = min(360, max(-360, block.rotationDegrees.isFinite ? block.rotationDegrees : 0))
            block.bookmark = sanitizedBookmark(block.bookmark)
            block.footnoteID = max(0, block.footnoteID)

            switch block.type {
            case .blank:
                blocks.append(DocumentBlock(type: .blank, confidence: block.confidence))

            case .image, .pageImage, .watermark:
                if block.type != .watermark,
                   options.describeImages,
                   !block.isDecorative,
                   block.altText.isEmpty {
                    warnings.append(L10n.format("لم يُنشأ وصف بديل لعنصر بصري في الصفحة %d.", pageNumber))
                    block.altText = L10n.format("عنصر بصري في الصفحة %d لم يتمكن النموذج من وصفه بدقة.", pageNumber)
                }
                if block.type != .pageImage,
                   options.embedImages,
                   block.boundingBox.allSatisfy({ $0 == 0 }) {
                    warnings.append(L10n.format("تعذر تحديد موضع عنصر بصري في الصفحة %d، لذلك قد يظهر وصفه دون تضمين قصاصته.", pageNumber))
                }
                blocks.append(block)

            case .table:
                if block.tableCells.isEmpty, !block.rows.isEmpty {
                    block.tableCells = cellsFromLegacyRows(block.rows)
                }
                let inferredRows = max(block.tableRowCount, (block.tableCells.map { $0.row + $0.rowSpan }.max() ?? 0), block.rows.count)
                let inferredColumns = max(block.tableColumnCount, (block.tableCells.map { $0.column + $0.columnSpan }.max() ?? 0), block.rows.map(\.count).max() ?? 0)
                block.tableRowCount = min(300, max(0, inferredRows))
                block.tableColumnCount = min(120, max(0, inferredColumns))
                block.repeatHeaderRows = min(block.tableRowCount, max(0, block.repeatHeaderRows))
                try validateTableGeometry(block, pageNumber: pageNumber)
                if block.rows.isEmpty {
                    block.rows = legacyRows(from: block)
                }
                let containsContent = block.tableCells.contains { !$0.text.isEmpty || !$0.runs.isEmpty }
                    || block.rows.flatMap { $0 }.contains { !$0.isEmpty }
                if containsContent {
                    blocks.append(block)
                } else {
                    warnings.append(L10n.format("أُزيل جدول فارغ أعاده النموذج في الصفحة %d.", pageNumber))
                }

            case .footnote:
                if block.footnoteID == 0 {
                    block.footnoteID = nextFootnoteID
                }
                nextFootnoteID = max(nextFootnoteID, block.footnoteID + 1)
                if !block.text.isEmpty { blocks.append(block) }

            case .separator:
                blocks.append(block)

            case .textBox, .equation, .formField:
                if !block.text.isEmpty || !block.runs.isEmpty || block.boundingBox[2] > 0.01 {
                    blocks.append(block)
                }

            default:
                if !block.text.isEmpty || !block.runs.isEmpty { blocks.append(block) }
            }
        }

        let blankCount = blocks.filter { $0.type == .blank }.count
        if blankCount > 0 && blocks.count > blankCount {
            blocks.removeAll { $0.type == .blank }
            warnings.append(L10n.format("أُزيل تصنيف فارغ متعارض مع محتوى الصفحة %d.", pageNumber))
        }

        guard !blocks.isEmpty else { throw GeminiError.emptyPageAnalysis(pageNumber) }
        if blocks.allSatisfy({ $0.type == .blank }) {
            blocks = [DocumentBlock(type: .blank, confidence: blocks.map(\.confidence).max() ?? 1)]
        }

        let language = input.detectedLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        var searchablePieces: [String] = []
        searchablePieces.reserveCapacity(blocks.count)
        for block in blocks {
            let runText = block.runs.map(\.text).joined()
            let rowText = block.rows.flatMap { $0 }.joined(separator: " ")
            let cellText = block.tableCells.map(\.text).joined(separator: " ")
            searchablePieces.append([block.text, runText, rowText, cellText].joined(separator: " "))
        }
        let searchableText = searchablePieces.joined(separator: " ")
        let inferredDirection: TextDirection = XML.containsArabic(searchableText) ? .rtl : input.direction
        let criticalTokens = Array(Set(input.criticalTokens.map {
            cleanSourceText($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty })).sorted()

        return PageAnalysis(
            pageNumber: pageNumber,
            detectedLanguage: language.isEmpty ? "und" : language,
            direction: inferredDirection,
            blocks: blocks,
            source: .gemini,
            warnings: Array(Set(warnings)).sorted(),
            contentKind: input.contentKind,
            qualityScore: 0,
            agreementScore: 0,
            verificationPasses: 1,
            preserveWholePageImage: input.preserveWholePageImage,
            wholePageAltText: cleanSourceText(input.wholePageAltText).trimmingCharacters(in: .whitespacesAndNewlines),
            readingOrderConfidence: min(1, max(0, input.readingOrderConfidence)),
            criticalTokens: criticalTokens
        )
    }

    private static func normalizeRun(_ input: TextRun) -> TextRun {
        var run = input
        run.text = cleanSourceText(run.text)
        run.highlightColor = normalizedHexColor(run.highlightColor)
        run.textColor = normalizedHexColor(run.textColor)
        run.fontSize = min(200, max(0, run.fontSize))
        run.linkURL = cleanSourceText(run.linkURL).trimmingCharacters(in: .whitespacesAndNewlines)
        run.internalLink = sanitizedBookmark(run.internalLink)
        run.footnoteReferenceID = max(0, run.footnoteReferenceID)
        return run
    }

    private static func normalizeCell(_ input: TableCell) -> TableCell {
        var cell = input
        cell.row = max(0, min(299, cell.row))
        cell.column = max(0, min(119, cell.column))
        cell.rowSpan = max(1, min(300 - cell.row, cell.rowSpan))
        cell.columnSpan = max(1, min(120 - cell.column, cell.columnSpan))
        cell.text = cleanSourceText(cell.text)
        cell.runs = Array(cell.runs.prefix(1_000)).map(normalizeRun)
        let runText = cell.runs.map(\.text).joined()
        if !runText.isEmpty {
            cell.text = runText
        } else if !cell.text.isEmpty {
            cell.runs = [TextRun(text: cell.text)]
        }
        cell.boundingBox = normalizedBox(cell.boundingBox)
        return cell
    }

    private static func cellsFromLegacyRows(_ rows: [[String]]) -> [TableCell] {
        rows.enumerated().flatMap { rowIndex, row in
            row.enumerated().map { columnIndex, text in
                TableCell(row: rowIndex, column: columnIndex, text: text)
            }
        }
    }

    private static func legacyRows(from block: DocumentBlock) -> [[String]] {
        guard block.tableRowCount > 0, block.tableColumnCount > 0 else { return [] }
        var rows = Array(
            repeating: Array(repeating: "", count: block.tableColumnCount),
            count: block.tableRowCount
        )
        for cell in block.tableCells where cell.row < rows.count && cell.column < rows[cell.row].count {
            rows[cell.row][cell.column] = cell.text
        }
        return rows
    }

    private static func validateTableGeometry(_ block: DocumentBlock, pageNumber: Int) throws {
        guard block.tableRowCount > 0, block.tableColumnCount > 0 else {
            throw GeminiError.invalidTableGeometry(page: pageNumber)
        }
        var occupied: Set<Int> = []
        for cell in block.tableCells {
            guard cell.row + cell.rowSpan <= block.tableRowCount,
                  cell.column + cell.columnSpan <= block.tableColumnCount else {
                throw GeminiError.invalidTableGeometry(page: pageNumber)
            }
            for row in cell.row..<(cell.row + cell.rowSpan) {
                for column in cell.column..<(cell.column + cell.columnSpan) {
                    let key = row * 1_000 + column
                    guard occupied.insert(key).inserted else {
                        throw GeminiError.overlappingTableCells(page: pageNumber, row: row, column: column)
                    }
                }
            }
        }
    }

    private static func cleanSourceText(_ text: String) -> String {
        normalizeLineEndings(text)
            .replacingOccurrences(of: "\u{0000}", with: "")
            .trimmingCharacters(in: .newlines)
    }

    private static func normalizedHexColor(_ value: String) -> String {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
            .uppercased()
        guard cleaned.count == 6,
              cleaned.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789ABCDEF").contains($0) }) else {
            return ""
        }
        return cleaned
    }

    private static func sanitizedBookmark(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        var output = trimmed.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "_" { return Character(String(scalar)) }
            return "_"
        }
        if output.first?.isNumber == true { output.insert("B", at: 0) }
        return String(output.prefix(40))
    }

    private static func validateSemanticQuality(
        analysis: PageAnalysis,
        nativeText: String,
        localOCR: LocalOCRReference,
        options: ConversionOptions
    ) throws {
        guard options.strictCompletenessCheck else { return }
        let extractedText = analysisComparableText(analysis, includeImageDescriptions: false)
        let extractedCount = significantCharacterCount(extractedText)

        if analysis.preserveWholePageImage {
            // Visual preservation is the safe result for an uncertain scan. Still reject
            // pathological duplicated text so hidden or auxiliary content cannot explode.
            if duplicateLineInflation(candidate: extractedText, reference: nativeText) > 3.0 {
                throw GeminiError.duplicateContent(page: analysis.pageNumber)
            }
            return
        }

        guard analysis.readingOrderConfidence >= 0.90 else {
            throw GeminiError.lowReadingOrderConfidence(
                page: analysis.pageNumber,
                score: analysis.readingOrderConfidence
            )
        }

        let nativeCount = significantCharacterCount(nativeText)
        if nativeCount >= 40 {
            let ratio = Double(extractedCount) / Double(max(1, nativeCount))
            let requiredCoverage = max(0.90, options.minimumCoverageRatio)
            guard ratio >= requiredCoverage else {
                throw GeminiError.insufficientCoverage(
                    page: analysis.pageNumber,
                    ratio: ratio,
                    required: requiredCoverage
                )
            }
            guard ratio <= 2.15 else {
                throw GeminiError.excessiveExpansion(page: analysis.pageNumber, ratio: ratio)
            }

            let nativeTokens = normalizedTokens(nativeText)
            let extractedTokens = normalizedTokens(extractedText)
            if nativeTokens.count >= 8 {
                let overlap = multisetRecall(reference: nativeTokens, candidate: extractedTokens)
                let requiredOverlap = 0.90
                guard overlap >= requiredOverlap else {
                    throw GeminiError.lowTextOverlap(
                        page: analysis.pageNumber,
                        ratio: overlap,
                        required: requiredOverlap
                    )
                }
            }

            let referenceCritical = extractCriticalTokens(nativeText)
            try validateCriticalTokens(
                declared: analysis.criticalTokens,
                reference: referenceCritical,
                candidateText: extractedText,
                pageNumber: analysis.pageNumber
            )

            if duplicateLineInflation(candidate: extractedText, reference: nativeText) > 1.6 {
                throw GeminiError.duplicateContent(page: analysis.pageNumber)
            }
            return
        }

        let ocrCount = significantCharacterCount(localOCR.text)
        if ocrCount >= 25, localOCR.averageConfidence >= 0.85 {
            let similarity = referenceTextSimilarity(extractedText, localOCR.text)
            guard similarity >= 0.78 else {
                throw GeminiError.lowTextOverlap(
                    page: analysis.pageNumber,
                    ratio: similarity,
                    required: 0.78
                )
            }
            let referenceCritical = extractCriticalTokens(localOCR.text)
            try validateCriticalTokens(
                declared: analysis.criticalTokens,
                reference: referenceCritical,
                candidateText: extractedText,
                pageNumber: analysis.pageNumber
            )
        }
    }

    private static func validateCriticalTokens(
        declared: [String],
        reference: [String],
        candidateText: String,
        pageNumber: Int
    ) throws {
        let candidates = Array(Set(reference + declared)).filter { token in
            token.count >= 3 && token.count <= 300
        }
        for token in candidates {
            if !candidateText.contains(token) {
                throw GeminiError.missingCriticalToken(page: pageNumber, token: String(token.prefix(80)))
            }
        }
    }

    private static func extractCriticalTokens(_ text: String) -> [String] {
        let patterns = [
            #"https?://[^\s<>]+"#,
            #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#,
            #"(?:[A-Za-z0-9._\-]+/){2,}[A-Za-z0-9._\-]+"#,
            #"(?<![\p{L}\p{N}])[A-Za-z\p{L}]*\d[A-Za-z\p{L}\d]*(?:[-_./:+][A-Za-z\p{L}\d]+)+(?![\p{L}\p{N}])"#,
            #"(?<!\d)\d{1,3}(?:,\d{3})+(?:\.\d+)?(?!\d)"#,
            #"(?<!\d)\d+\.\d+(?!\d)"#,
            #"[☐☒☑◉○✓✗★♠∞≥≤≠±×÷√πΩ↔←→¶§™®©]+"#
        ]
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var tokens: [String] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: text, range: range) {
                guard let swiftRange = Range(match.range, in: text) else { continue }
                let token = String(text[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !token.isEmpty { tokens.append(token) }
            }
        }
        return Array(Set(tokens)).sorted()
    }

    private static func duplicateLineInflation(candidate: String, reference: String) -> Double {
        func duplicateBurden(_ value: String) -> Int {
            var counts: [String: Int] = [:]
            for rawLine in normalizeLineEndings(value).split(separator: "\n", omittingEmptySubsequences: true) {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard significantCharacterCount(line) >= 8 else { continue }
                counts[line, default: 0] += 1
            }
            return counts.values.reduce(0) { $0 + max(0, $1 - 1) }
        }
        let candidateBurden = duplicateBurden(candidate)
        let referenceBurden = duplicateBurden(reference)
        return Double(candidateBurden + 1) / Double(referenceBurden + 1)
    }

    private static func analysisAgreement(_ lhs: PageAnalysis, _ rhs: PageAnalysis) -> Double {
        let leftText = analysisComparableText(lhs, includeImageDescriptions: false)
        let rightText = analysisComparableText(rhs, includeImageDescriptions: false)
        let textScore = textSimilarity(leftText, rightText)
        let structureScore = textSimilarity(structureSignature(lhs), structureSignature(rhs))

        let leftVisuals = visualDescriptionText(lhs)
        let rightVisuals = visualDescriptionText(rhs)
        let hasVisuals = !leftVisuals.isEmpty || !rightVisuals.isEmpty
        let visualScore = hasVisuals ? textSimilarity(leftVisuals, rightVisuals) : 1
        let hasSubstantialText = max(
            significantCharacterCount(leftText),
            significantCharacterCount(rightText)
        ) >= 20

        var score: Double
        if hasSubstantialText {
            score = 0.85 * textScore + 0.10 * structureScore + 0.05 * visualScore
        } else if hasVisuals {
            score = 0.20 * structureScore + 0.80 * visualScore
        } else {
            score = 0.70 * textScore + 0.30 * structureScore
        }

        if lhs.contentKind != .unknown,
           rhs.contentKind != .unknown,
           lhs.contentKind != rhs.contentKind {
            score *= 0.97
        }
        return min(1, max(0, score))
    }

    private static func referenceAgreement(
        analysis: PageAnalysis,
        nativeText: String,
        localOCR: LocalOCRReference,
        fallback: Double
    ) -> Double {
        let extracted = analysisComparableText(analysis, includeImageDescriptions: false)
        if significantCharacterCount(nativeText) >= 40 {
            return referenceTextSimilarity(extracted, nativeText)
        }
        if significantCharacterCount(localOCR.text) >= 25,
           localOCR.averageConfidence >= 0.85 {
            let ocrSimilarity = referenceTextSimilarity(extracted, localOCR.text)
            return 0.55 * fallback + 0.45 * ocrSimilarity
        }
        return fallback
    }

    private static func weightedConfidence(_ analysis: PageAnalysis) -> Double {
        var weightedTotal = 0.0
        var totalWeight = 0.0
        for block in analysis.blocks where block.type != .blank && block.type != .separator {
            let content: String
            if block.type == .table {
                content = block.tableCells.isEmpty
                    ? block.rows.flatMap { $0 }.joined(separator: " ")
                    : block.tableCells.map(\.text).joined(separator: " ")
            } else {
                content = block.text + " " + block.runs.map(\.text).joined() + " " + block.altText
            }
            let weight = Double(max(1, significantCharacterCount(content)))
            weightedTotal += min(1, max(0, block.confidence)) * weight
            totalWeight += weight
        }
        guard totalWeight > 0 else { return 1 }
        return weightedTotal / totalWeight
    }

    private static func analysisComparableText(
        _ analysis: PageAnalysis,
        includeImageDescriptions: Bool
    ) -> String {
        analysis.blocks.map { block in
            switch block.type {
            case .table:
                if !block.tableCells.isEmpty {
                    return block.tableCells.sorted {
                        ($0.row, $0.column) < ($1.row, $1.column)
                    }.map { $0.text }.joined(separator: "\t")
                }
                return block.rows.map { $0.joined(separator: "\t") }.joined(separator: "\n")
            case .image, .pageImage, .watermark:
                let literalText = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if includeImageDescriptions {
                    return [literalText, block.altText]
                        .filter { !$0.isEmpty }
                        .joined(separator: "\n")
                }
                return literalText
            case .blank:
                return ""
            case .separator:
                return "\n"
            default:
                return block.runs.isEmpty ? block.text : block.runs.map(\.text).joined()
            }
        }.joined(separator: "\n")
    }

    private static func structureSignature(_ analysis: PageAnalysis) -> String {
        analysis.blocks.map { block in
            switch block.type {
            case .table:
                let spans = block.tableCells.sorted {
                    ($0.row, $0.column) < ($1.row, $1.column)
                }.map { "\($0.row),\($0.column),\($0.rowSpan),\($0.columnSpan)" }
                    .joined(separator: ";")
                return "table:\(block.tableRowCount):\(block.tableColumnCount):\(block.repeatHeaderRows):\(spans)"
            case .image, .pageImage, .watermark:
                let box = block.boundingBox.map { String(format: "%.2f", $0) }.joined(separator: ",")
                return "\(block.type.rawValue):\(block.isDecorative ? 1 : 0):\(box)"
            case .bullet, .numbered:
                return "\(block.type.rawValue):\(block.listLevel):\(block.listStyle.rawValue):\(block.listStart)"
            case .textBox:
                return "textbox:\(String(format: "%.1f", block.rotationDegrees))"
            default:
                return block.type.rawValue
            }
        }.joined(separator: "|")
    }

    private static func visualDescriptionText(_ analysis: PageAnalysis) -> String {
        analysis.blocks
            .filter { [.image, .pageImage, .watermark].contains($0.type) && !$0.isDecorative }
            .map { [$0.text, $0.altText].filter { !$0.isEmpty }.joined(separator: " ") }
            .joined(separator: "\n")
    }

    private static func visualFallbackDescription(analysis: PageAnalysis, pageNumber: Int) -> String {
        let descriptions = visualDescriptionText(analysis)
        if !descriptions.isEmpty { return descriptions }
        let extracted = analysisComparableText(analysis, includeImageDescriptions: false)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !extracted.isEmpty {
            return L10n.format("صورة كاملة للصفحة %d. النص المقروء بثقة: %@", pageNumber, String(extracted.prefix(1_200)))
        }
        return L10n.format("صورة كاملة للصفحة %d حُفظت لضمان عدم فقدان محتواها المرئي.", pageNumber)
    }

    private static func textSimilarity(_ lhs: String, _ rhs: String) -> Double {
        let leftSequence = normalizedCharacterSequence(lhs)
        let rightSequence = normalizedCharacterSequence(rhs)
        if leftSequence.isEmpty && rightSequence.isEmpty { return 1 }
        if leftSequence.isEmpty || rightSequence.isEmpty { return 0 }

        let leftTokens = normalizedTokens(lhs)
        let rightTokens = normalizedTokens(rhs)
        let recall = multisetRecall(reference: leftTokens, candidate: rightTokens)
        let precision = multisetRecall(reference: rightTokens, candidate: leftTokens)
        let tokenF1 = (recall + precision) > 0
            ? 2 * recall * precision / (recall + precision)
            : 0
        let tokenOrderSimilarity = tokenNgramDice(leftTokens, rightTokens, width: 2)
        let characterOrderSimilarity = ngramDice(leftSequence, rightSequence, width: 3)
        let lengthAgreement = Double(min(leftSequence.count, rightSequence.count))
            / Double(max(1, max(leftSequence.count, rightSequence.count)))
        return min(1, max(0,
            0.35 * tokenF1
            + 0.35 * tokenOrderSimilarity
            + 0.20 * characterOrderSimilarity
            + 0.10 * lengthAgreement
        ))
    }

    private static func referenceTextSimilarity(_ lhs: String, _ rhs: String) -> Double {
        let leftTokens = normalizedTokens(lhs)
        let rightTokens = normalizedTokens(rhs)
        if leftTokens.isEmpty && rightTokens.isEmpty { return 1 }
        if leftTokens.isEmpty || rightTokens.isEmpty { return 0 }
        let recall = multisetRecall(reference: leftTokens, candidate: rightTokens)
        let precision = multisetRecall(reference: rightTokens, candidate: leftTokens)
        let tokenF1 = (recall + precision) > 0
            ? 2 * recall * precision / (recall + precision)
            : 0
        let leftCount = significantCharacterCount(lhs)
        let rightCount = significantCharacterCount(rhs)
        let lengthAgreement = Double(min(leftCount, rightCount)) / Double(max(1, max(leftCount, rightCount)))
        return min(1, max(0, 0.85 * tokenF1 + 0.15 * lengthAgreement))
    }

    private static func normalizedCharacterSequence(_ text: String) -> [Character] {
        let normalized = normalizeLineEndings(text)
            .precomposedStringWithCanonicalMapping
            .lowercased()
        var output = ""
        output.reserveCapacity(normalized.count)
        var previousWasWhitespace = false
        for scalar in normalized.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                if !previousWasWhitespace && !output.isEmpty { output.append(" ") }
                previousWasWhitespace = true
                continue
            }
            if CharacterSet.controlCharacters.contains(scalar) || scalar.value == 0x200E || scalar.value == 0x200F {
                continue
            }
            output.unicodeScalars.append(scalar)
            previousWasWhitespace = false
        }
        return Array(output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func tokenNgramDice(_ lhs: [String], _ rhs: [String], width: Int) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return lhs.isEmpty == rhs.isEmpty ? 1 : 0 }
        let actualWidth = max(1, min(width, min(lhs.count, rhs.count)))
        func counts(_ tokens: [String]) -> [String: Int] {
            guard tokens.count >= actualWidth else { return [tokens.joined(separator: "\u{001F}"): 1] }
            var result: [String: Int] = [:]
            for index in 0...(tokens.count - actualWidth) {
                let gram = tokens[index..<(index + actualWidth)].joined(separator: "\u{001F}")
                result[gram, default: 0] += 1
            }
            return result
        }
        let left = counts(lhs)
        let right = counts(rhs)
        let leftTotal = left.values.reduce(0, +)
        let rightTotal = right.values.reduce(0, +)
        var overlap = 0
        for (gram, count) in left {
            overlap += min(count, right[gram, default: 0])
        }
        return Double(2 * overlap) / Double(max(1, leftTotal + rightTotal))
    }

    private static func ngramDice(_ lhs: [Character], _ rhs: [Character], width: Int) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return lhs.isEmpty == rhs.isEmpty ? 1 : 0 }
        let actualWidth = max(1, min(width, min(lhs.count, rhs.count)))
        func counts(_ characters: [Character]) -> [String: Int] {
            guard characters.count >= actualWidth else { return [String(characters): 1] }
            var result: [String: Int] = [:]
            for index in 0...(characters.count - actualWidth) {
                let gram = String(characters[index..<(index + actualWidth)])
                result[gram, default: 0] += 1
            }
            return result
        }
        let left = counts(lhs)
        let right = counts(rhs)
        let leftTotal = left.values.reduce(0, +)
        let rightTotal = right.values.reduce(0, +)
        var overlap = 0
        for (gram, count) in left {
            overlap += min(count, right[gram, default: 0])
        }
        return Double(2 * overlap) / Double(max(1, leftTotal + rightTotal))
    }

    private static func normalizedTokens(_ text: String) -> [String] {
        var value = text.lowercased()
        let replacements: [String: String] = [
            "أ": "ا", "إ": "ا", "آ": "ا", "ٱ": "ا", "ى": "ي", "ؤ": "و", "ئ": "ي"
        ]
        for (source, target) in replacements {
            value = value.replacingOccurrences(of: source, with: target)
        }
        value = value.unicodeScalars.filter { scalar in
            !CharacterSet(charactersIn: "\u{064B}\u{064C}\u{064D}\u{064E}\u{064F}\u{0650}\u{0651}\u{0652}\u{0670}").contains(scalar)
        }.map(String.init).joined()

        return value.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { token in
                guard !token.isEmpty else { return false }
                return token.count > 1 || token.unicodeScalars.allSatisfy { CharacterSet.decimalDigits.contains($0) }
            }
    }

    private static func multisetRecall(reference: [String], candidate: [String]) -> Double {
        guard !reference.isEmpty else { return 1 }
        var candidateCounts: [String: Int] = [:]
        for token in candidate { candidateCounts[token, default: 0] += 1 }
        var matched = 0
        for token in reference {
            let count = candidateCounts[token, default: 0]
            if count > 0 {
                matched += 1
                candidateCounts[token] = count - 1
            }
        }
        return Double(matched) / Double(reference.count)
    }

    private static func significantCharacterCount(_ text: String) -> Int {
        text.unicodeScalars.reduce(into: 0) { count, scalar in
            if CharacterSet.alphanumerics.contains(scalar) { count += 1 }
        }
    }

    private static func normalizedBox(_ box: [Double]) -> [Double] {
        guard box.count == 4, box.allSatisfy(\.isFinite) else { return [0, 0, 0, 0] }
        let x = min(1, max(0, box[0]))
        let y = min(1, max(0, box[1]))
        let width = min(1 - x, max(0, box[2]))
        let height = min(1 - y, max(0, box[3]))
        return [x, y, width, height]
    }

    private static func normalizeLineEndings(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private static func removeCodeFence(from text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.hasPrefix("```") else { return value }
        if let firstNewline = value.firstIndex(of: "\n") {
            value = String(value[value.index(after: firstNewline)...])
        }
        if value.hasSuffix("```") { value.removeLast(3) }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func generateContentURL(model: String) throws -> URL {
        let encoded = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(encoded):generateContent") else {
            throw GeminiError.invalidEndpoint
        }
        return url
    }

    private static func normalizedModel(_ model: String) -> String {
        model.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "models/", with: "")
    }

    private static func supportsThinkingLevel(_ model: String) -> Bool {
        model.lowercased().hasPrefix("gemini-3")
    }

    private static func normalizedThinkingLevel(_ value: String, model: String) -> String {
        let allowed = Set(["minimal", "low", "medium", "high"])
        let normalized = allowed.contains(value.lowercased()) ? value.lowercased() : "medium"

        // Gemini 3.1 Pro does not accept the minimal level. Promote it to low
        // rather than failing a key test or an otherwise valid conversion.
        let lowerModel = model.lowercased()
        if normalized == "minimal", lowerModel.contains("pro") {
            return "low"
        }
        return normalized
    }

    private static func maximumOutputTokens(for model: String) -> Int {
        let lower = model.lowercased()
        return (lower.hasPrefix("gemini-3") || lower.hasPrefix("gemini-2.5")) ? 65_536 : 32_768
    }

    private static func sanitizedAPIMessage(_ message: String) -> String {
        let flattened = message.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        return String(flattened.prefix(700))
    }

    private static func retryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let raw = response.value(forHTTPHeaderField: "Retry-After") else { return nil }
        if let seconds = TimeInterval(raw) { return max(0, seconds) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let date = formatter.date(from: raw) { return max(0, date.timeIntervalSinceNow) }
        return nil
    }

#if QUALITY_TESTING
    static func testingAgreement(_ lhs: PageAnalysis, _ rhs: PageAnalysis) -> Double {
        analysisAgreement(lhs, rhs)
    }
#endif

    private static var textRunSchema: [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "text": ["type": "string"],
                "bold": ["type": "boolean"],
                "italic": ["type": "boolean"],
                "underline": ["type": "boolean"],
                "strike": ["type": "boolean"],
                "highlightColor": ["type": "string", "description": "Six-digit RGB hex without #, or empty."],
                "textColor": ["type": "string", "description": "Six-digit RGB hex without #, or empty."],
                "fontSize": ["type": "number", "minimum": 0, "maximum": 200],
                "baseline": ["type": "string", "enum": BaselineStyle.allCases.map(\.rawValue)],
                "direction": ["type": "string", "enum": TextDirection.allCases.map(\.rawValue)],
                "linkURL": ["type": "string"],
                "internalLink": ["type": "string"],
                "footnoteReferenceID": ["type": "integer", "minimum": 0],
                "preserveSpaces": ["type": "boolean"]
            ],
            "required": [
                "text", "bold", "italic", "underline", "strike", "highlightColor",
                "textColor", "fontSize", "baseline", "direction", "linkURL",
                "internalLink", "footnoteReferenceID", "preserveSpaces"
            ]
        ]
    }

    private static var tableCellSchema: [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "row": ["type": "integer", "minimum": 0, "maximum": 299],
                "column": ["type": "integer", "minimum": 0, "maximum": 119],
                "rowSpan": ["type": "integer", "minimum": 1, "maximum": 300],
                "columnSpan": ["type": "integer", "minimum": 1, "maximum": 120],
                "text": ["type": "string"],
                "runs": ["type": "array", "maxItems": 1000, "items": textRunSchema],
                "isHeader": ["type": "boolean"],
                "horizontalAlignment": ["type": "string", "enum": CellHorizontalAlignment.allCases.map(\.rawValue)],
                "verticalAlignment": ["type": "string", "enum": CellVerticalAlignment.allCases.map(\.rawValue)],
                "boundingBox": [
                    "type": "array", "minItems": 4, "maxItems": 4,
                    "items": ["type": "number", "minimum": 0, "maximum": 1]
                ]
            ],
            "required": [
                "row", "column", "rowSpan", "columnSpan", "text", "runs",
                "isHeader", "horizontalAlignment", "verticalAlignment", "boundingBox"
            ]
        ]
    }

    private static var pageSchema: [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "pageNumber": ["type": "integer", "minimum": 1, "description": "The 1-based page number."],
                "detectedLanguage": ["type": "string", "description": "Primary language code or short name."],
                "direction": ["type": "string", "enum": TextDirection.allCases.map(\.rawValue)],
                "contentKind": ["type": "string", "enum": PageContentKind.allCases.map(\.rawValue)],
                "preserveWholePageImage": ["type": "boolean"],
                "wholePageAltText": ["type": "string"],
                "readingOrderConfidence": ["type": "number", "minimum": 0, "maximum": 1],
                "criticalTokens": ["type": "array", "maxItems": 500, "items": ["type": "string"]],
                "blocks": [
                    "type": "array",
                    "minItems": 1,
                    "maxItems": 800,
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "properties": [
                            "type": ["type": "string", "enum": BlockType.allCases.map(\.rawValue)],
                            "text": ["type": "string"],
                            "runs": ["type": "array", "maxItems": 1500, "items": textRunSchema],
                            "rows": [
                                "type": "array", "maxItems": 300,
                                "items": ["type": "array", "maxItems": 120, "items": ["type": "string"]]
                            ],
                            "tableRowCount": ["type": "integer", "minimum": 0, "maximum": 300],
                            "tableColumnCount": ["type": "integer", "minimum": 0, "maximum": 120],
                            "tableCells": ["type": "array", "maxItems": 5000, "items": tableCellSchema],
                            "repeatHeaderRows": ["type": "integer", "minimum": 0, "maximum": 50],
                            "boundingBox": [
                                "type": "array", "minItems": 4, "maxItems": 4,
                                "items": ["type": "number", "minimum": 0, "maximum": 1]
                            ],
                            "altText": ["type": "string"],
                            "isDecorative": ["type": "boolean"],
                            "confidence": ["type": "number", "minimum": 0, "maximum": 1],
                            "direction": ["type": "string", "enum": TextDirection.allCases.map(\.rawValue)],
                            "listLevel": ["type": "integer", "minimum": 0, "maximum": 8],
                            "listStyle": ["type": "string", "enum": ListStyle.allCases.map(\.rawValue)],
                            "listStart": ["type": "integer", "minimum": 1],
                            "rotationDegrees": ["type": "number", "minimum": -360, "maximum": 360],
                            "bookmark": ["type": "string"],
                            "keepWithNext": ["type": "boolean"],
                            "footnoteID": ["type": "integer", "minimum": 0]
                        ],
                        "required": [
                            "type", "text", "runs", "rows", "tableRowCount", "tableColumnCount",
                            "tableCells", "repeatHeaderRows", "boundingBox", "altText", "isDecorative",
                            "confidence", "direction", "listLevel", "listStyle", "listStart",
                            "rotationDegrees", "bookmark", "keepWithNext", "footnoteID"
                        ]
                    ]
                ]
            ],
            "required": [
                "pageNumber", "detectedLanguage", "direction", "contentKind",
                "preserveWholePageImage", "wholePageAltText", "readingOrderConfidence",
                "criticalTokens", "blocks"
            ]
        ]
    }

}

private struct StructuredProbe: Decodable { let ok: Bool }

private struct ModelListEnvelope: Decodable {
    let models: [GeminiModelInfo]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        models = try container.decodeIfPresent([GeminiModelInfo].self, forKey: .models) ?? []
    }

    private enum CodingKeys: String, CodingKey { case models }
}

private struct GeminiEnvelope: Decodable {
    struct Candidate: Decodable {
        struct Content: Decodable {
            struct Part: Decodable {
                let text: String?
                let thought: Bool?
            }
            let parts: [Part]?
        }
        let content: Content?
        let finishReason: String?
    }
    struct PromptFeedback: Decodable { let blockReason: String? }

    let candidates: [Candidate]?
    let promptFeedback: PromptFeedback?
}

private struct GeminiAPIErrorEnvelope: Decodable {
    struct APIError: Decodable { let message: String }
    let error: APIError
}

enum GeminiError: LocalizedError, Sendable {
    case missingAPIKey
    case invalidEndpoint
    case invalidResponse
    case requestEncodingFailed
    case fileTooLarge
    case emptyPageData(Int)
    case emptyModelOutput
    case emptyPageAnalysis(Int)
    case excessiveBlockCount(page: Int, count: Int)
    case invalidStructuredOutput(String)
    case structuredOutputProbeFailed
    case insufficientCoverage(page: Int, ratio: Double, required: Double)
    case excessiveExpansion(page: Int, ratio: Double)
    case lowTextOverlap(page: Int, ratio: Double, required: Double)
    case missingCriticalToken(page: Int, token: String)
    case duplicateContent(page: Int)
    case lowReadingOrderConfidence(page: Int, score: Double)
    case invalidTableGeometry(page: Int)
    case overlappingTableCells(page: Int, row: Int, column: Int)
    case qualityBelowAcceptance(page: Int, score: Double, agreement: Double, required: Double, kind: PageContentKind)
    case falseBlankPage(Int)
    case blocked(String)
    case noCandidate(String)
    case incompleteCandidate(String)
    case modelUnavailable(String)
    case httpStatus(Int, String, TimeInterval?)

    var retryAfter: TimeInterval? {
        if case .httpStatus(_, _, let retryAfter) = self { return retryAfter }
        return nil
    }

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return L10n.text("مفتاح Gemini API فارغ.")
        case .invalidEndpoint: return L10n.text("عنوان Gemini API غير صالح.")
        case .invalidResponse: return L10n.text("وصلت استجابة غير صالحة من Gemini API.")
        case .requestEncodingFailed: return L10n.text("تعذر تجهيز طلب Gemini بصيغة JSON.")
        case .fileTooLarge: return L10n.text("حجم الصفحة المستخرجة تجاوز الحد المسموح للإرسال المباشر.")
        case .emptyPageData(let page): return L10n.format("تعذر استخراج بيانات PDF للصفحة %d.", page)
        case .emptyModelOutput: return L10n.text("لم يُرجع Gemini محتوى قابلًا للتحويل.")
        case .emptyPageAnalysis(let page): return L10n.format("أعاد Gemini تحليلًا فارغًا للصفحة %d.", page)
        case .excessiveBlockCount(let page, let count):
            return L10n.format("أعاد Gemini عددًا غير منطقي من الكتل في الصفحة %d: %d.", page, count)
        case .invalidStructuredOutput(let reason): return L10n.format("أعاد Gemini بنية غير صالحة: %@", reason)
        case .structuredOutputProbeFailed:
            return L10n.text("النموذج ظاهر للمفتاح، لكنه لم يجتز اختبار الإخراج المنظم المطلوب للتحويل.")
        case .insufficientCoverage(let page, let ratio, let required):
            return L10n.format("فشل فحص اكتمال الصفحة %d: استُخرج نحو %d%% فقط، والحد الأدنى %d%%.", page, Int(ratio * 100), Int(required * 100))
        case .excessiveExpansion(let page, let ratio):
            return L10n.format("أنتج Gemini نصًا أطول بصورة غير منطقية في الصفحة %d بنحو %.1f ضعف، وقد يكون أضاف محتوى غير موجود.", page, ratio)
        case .lowTextOverlap(let page, let ratio, let required):
            return L10n.format("فشل فحص تطابق نص الصفحة %d: التطابق %d%%، والحد الأدنى %d%%.", page, Int(ratio * 100), Int(required * 100))
        case .missingCriticalToken(let page, let token):
            return L10n.format("فُقد رمز حساس في الصفحة %d: %@.", page, token)
        case .duplicateContent(let page):
            return L10n.format("اكتُشف تكرار غير طبيعي في الصفحة %d، لذلك أُوقف تمرير النص.", page)
        case .lowReadingOrderConfidence(let page, let score):
            return L10n.format("ترتيب القراءة في الصفحة %d غير موثوق بما يكفي: %d%%.", page, Int(score * 100))
        case .invalidTableGeometry(let page):
            return L10n.format("أعاد النموذج بنية جدول غير صالحة في الصفحة %d.", page)
        case .overlappingTableCells(let page, let row, let column):
            return L10n.format("تداخلت خلايا جدول في الصفحة %d عند الصف %d والعمود %d.", page, row + 1, column + 1)
        case .qualityBelowAcceptance(let page, let score, let agreement, let required, let kind):
            let kindName: String
            switch kind {
            case .printed: kindName = L10n.text("مطبوع")
            case .handwritten: kindName = L10n.text("خط يد")
            case .mixed: kindName = L10n.text("مختلط")
            case .imageOnly: kindName = L10n.text("صورة فقط")
            case .unknown: kindName = L10n.text("غير محدد")
            }
            return L10n.format("لم تجتز الصفحة %d بوابة الدقة الداخلية. النوع: %@، درجة القبول %d%%، واتفاق القراءات %d%%، والمطلوب %d%%. أوقف التطبيق إنشاء Word بدل تمرير نتيجة غير موثوقة.", page, kindName, Int(score * 100), Int(agreement * 100), Int(required * 100))
        case .falseBlankPage(let page):
            return L10n.format("صنّف Gemini الصفحة %d فارغة رغم أن الفحص المحلي وجد محتوى مرئيًا.", page)
        case .blocked(let reason): return L10n.format("رفض Gemini تحليل الصفحة بسبب مرشح المحتوى: %@.", reason)
        case .noCandidate(let reason): return L10n.format("لم يُنشئ Gemini نتيجة. سبب الإنهاء: %@.", reason)
        case .incompleteCandidate(let reason): return L10n.format("توقفت استجابة Gemini قبل الاكتمال. سبب الإنهاء: %@.", reason)
        case .modelUnavailable(let model): return L10n.format("النموذج %@ غير متاح لهذا المفتاح أو لا يدعم generateContent.", model)
        case .httpStatus(let code, let message, _):
            if code == 400 { return L10n.format("رفض Gemini إعدادات الطلب أو اسم النموذج. %@", message) }
            if code == 404 { return L10n.format("النموذج المطلوب غير موجود أو غير متاح. %@", message) }
            if code == 429 { return L10n.format("تم بلوغ الحصة أو معدل الطلبات. %@", message) }
            if code == 401 || code == 403 { return L10n.format("المفتاح غير صالح أو لا يملك الصلاحية. %@", message) }
            return L10n.format("خطأ Gemini API رقم %d: %@", code, message)
        }
    }
}
