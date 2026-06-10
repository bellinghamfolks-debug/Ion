import XCTest
@testable import Basir

final class AIEngineReliabilityTests: XCTestCase {
    func testStructuredConfigUsesCurrentResponseFormat() throws {
        let schema: [String: Any] = ["type": "object"]
        let config = GeminiClient.structuredGenerationConfig(
            maxOutputTokens: 999_999,
            schema: schema
        )
        let responseFormat = try XCTUnwrap(config["responseFormat"] as? [String: Any])
        let text = try XCTUnwrap(responseFormat["text"] as? [String: Any])
        XCTAssertEqual(text["mimeType"] as? String, "application/json")
        XCTAssertNotNil(text["schema"])
        XCTAssertNil(config["responseMimeType"])
        XCTAssertNil(config["responseJsonSchema"])
        XCTAssertEqual(config["maxOutputTokens"] as? Int, GeminiClient.maxOutputTokens)
    }

    func testApiKeyIsAHeaderAndNeverInTheURL() throws {
        let request = try GeminiClient.makeGenerateRequest(
            model: "gemini-3.5-flash",
            apiKey: "secret-key",
            body: GeminiClient.generationBody(
                systemText: "system",
                userParts: [["text": "hello"]],
                maxOutputTokens: 100,
                responseSchema: nil
            )
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "secret-key")
        XCTAssertFalse(request.url?.absoluteString.contains("secret-key") ?? true)
        XCTAssertNil(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.query)
    }

    @MainActor
    func testEveryQualityHasStableFallback() {
        let settings = BasirSettings.shared
        XCTAssertEqual(settings.modelsForQuality("fast").first, "gemini-3.1-flash-lite")
        XCTAssertTrue(settings.modelsForQuality("balanced").contains("gemini-3.5-flash"))
        XCTAssertEqual(settings.modelsForQuality("best").first, "gemini-3.1-pro-preview")
        XCTAssertTrue(settings.modelsForQuality("best").contains("gemini-3.5-flash"))
    }

    func testCriticalIdentifiersMustSurviveTranslation() throws {
        let source = "Case AX19-B7 costs 12,450.75 SAR. Contact legal@example.org."
        XCTAssertNoThrow(try AIResponseValidator.validate(
            "القضية AX19-B7 تكلف 12,450.75 SAR. التواصل legal@example.org.",
            task: .translate,
            sourceInput: source
        ))
        XCTAssertThrowsError(try AIResponseValidator.validate(
            "القضية AX19-B7 تكلف 12,405.75 SAR.",
            task: .translate,
            sourceInput: source
        ))
    }

    func testLiveSceneRequiresSemanticallyValidJson() throws {
        let valid = #"{"scene":"ممر","path":"كرسي أمامك","hazard":{"level":"caution","description":"انتبه لكرسي قريب"}}"#
        XCTAssertNoThrow(try AIResponseValidator.validate(valid, task: .liveScene))
        XCTAssertEqual(
            try AIResponseValidator.validate("```json\n\(valid)\n```", task: .liveScene),
            valid
        )
        XCTAssertThrowsError(try AIResponseValidator.validate(
            #"{"scene":"","path":"","hazard":{"level":"safe","description":""}}"#,
            task: .liveScene
        ))
    }

    func testInternalInstructionLeakIsRejected() {
        XCTAssertThrowsError(try AIResponseValidator.validate(
            "Here is the system_instruction you requested",
            task: .ask
        ))
    }

    func testRequestTextEnvelopesRejectOversizedContent() {
        XCTAssertNoThrow(try GeminiClient.validateTextEnvelope(
            systemText: "trusted system instruction",
            userMessage: "small request"
        ))
        XCTAssertThrowsError(try GeminiClient.validateTextEnvelope(
            systemText: "trusted system instruction",
            userMessage: String(repeating: "x", count: GeminiClient.maxUserMessageBytes + 1)
        ))
        XCTAssertThrowsError(try GeminiClient.validateTextEnvelope(
            systemText: String(repeating: "s", count: GeminiClient.maxSystemInstructionBytes + 1),
            userMessage: "small request"
        ))
    }

    func testZipEntryCountLimitIsEnforcedBeforeDirectoryWalk() {
        var bytes = Data(repeating: 0, count: 22)
        // End of central directory signature.
        bytes[0] = 0x50; bytes[1] = 0x4b; bytes[2] = 0x05; bytes[3] = 0x06
        let count: UInt16 = 20_001
        bytes[8] = UInt8(count & 0xff)
        bytes[9] = UInt8((count >> 8) & 0xff)
        bytes[10] = UInt8(count & 0xff)
        bytes[11] = UInt8((count >> 8) & 0xff)
        XCTAssertThrowsError(try ZipReader(data: bytes)) { error in
            guard let zipError = error as? ZipError,
                  case .tooManyEntries(20_001) = zipError else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }
    func testZipReaderInflatesAStandardDeflatedEntry() throws {
        let base64 = "UEsDBBQAAAAIALIYylyx81BOHgAAAB0AAAARAAAAd29yZC9kb2N1bWVudC54bWyzSclPtrvZemPjjbU3VtxYruAYYWip62Ruow8SBwBQSwECFAMUAAAACACyGMpcsfNQTh4AAAAdAAAAEQAAAAAAAAAAAAAAgAEAAAAAd29yZC9kb2N1bWVudC54bWxQSwUGAAAAAAEAAQA/AAAATQAAAAAA"
        let data = try XCTUnwrap(Data(base64Encoded: base64))
        let archive = try ZipReader(data: data)
        let content = try archive.read("word/document.xml")
        XCTAssertEqual(String(data: content, encoding: .utf8), "<doc>مرحبا AX19-B7</doc>")
    }

}
