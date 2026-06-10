import XCTest
@testable import Basir

/// Covers the structured-output resilience added so that document, OCR, and
/// image features keep working even if the provider rejects the response
/// schema (HTTP 400 / InvalidArgument), plus the error-mapper transparency
/// for previously-unmapped 400/404 responses.
final class AIEngineSchemaFallbackTests: XCTestCase {

    func testSchemaRejectionDetectedForBadRequest() {
        XCTAssertTrue(AIExecutionDecision.isStructuredSchemaRejection(
            GeminiError.http(status: 400, body: "Invalid JSON payload: unknown name responseFormat")))
        XCTAssertTrue(AIExecutionDecision.isStructuredSchemaRejection(
            GeminiError.http(status: 400, body: "")))
        XCTAssertTrue(AIExecutionDecision.isStructuredSchemaRejection(
            GeminiError.decode("invalid argument: response_format schema")))
    }

    func testNonSchemaErrorsAreNotTreatedAsSchemaRejection() {
        XCTAssertFalse(AIExecutionDecision.isStructuredSchemaRejection(
            GeminiError.http(status: 429, body: "rate limit")))
        XCTAssertFalse(AIExecutionDecision.isStructuredSchemaRejection(
            GeminiError.http(status: 503, body: "unavailable")))
        XCTAssertFalse(AIExecutionDecision.isStructuredSchemaRejection(GeminiError.missingApiKey))
        XCTAssertFalse(AIExecutionDecision.isStructuredSchemaRejection(GeminiError.cancelled))
    }

    func testProxyBodyOmitsSchemaWhenDisabled() {
        let policy = AITaskPolicyCatalog.policy(for: .describeImage)
        let withSchema = ProxyAiProvider.makeBody(
            task: .describeImage, input: "", instruction: nil, language: .arabic,
            imageData: Data([0x1]), mimeType: "image/jpeg",
            modelCandidates: ["gemini-3.5-flash"], policy: policy,
            requestID: "r", attempt: 1, repairReason: nil, includeSchema: true)
        let generationWith = withSchema["generation_config"] as? [String: Any]
        XCTAssertNotNil(generationWith?["response_format"])

        let withoutSchema = ProxyAiProvider.makeBody(
            task: .describeImage, input: "", instruction: nil, language: .arabic,
            imageData: Data([0x1]), mimeType: "image/jpeg",
            modelCandidates: ["gemini-3.5-flash"], policy: policy,
            requestID: "r", attempt: 1, repairReason: nil, includeSchema: false)
        let generationWithout = withoutSchema["generation_config"] as? [String: Any]
        XCTAssertNil(generationWithout?["response_format"])
    }

    func testGenerationBodyOmitsSchemaWhenNil() {
        let config = GeminiClient.structuredGenerationConfig(maxOutputTokens: 1_024, schema: nil)
        XCTAssertNil(config["responseFormat"])
        let withSchema = GeminiClient.structuredGenerationConfig(
            maxOutputTokens: 1_024, schema: AIResponseSchemas.imageDescription)
        XCTAssertNotNil(withSchema["responseFormat"])
    }

    func testErrorMapperSurfacesBadRequestAndModelNotFound() {
        let badRequest = UserFriendlyErrorMapper.map(
            GeminiError.http(status: 400, body: "InvalidArgument: schema"))
        XCTAssertFalse(badRequest.contains("تحقق من اتصال الإنترنت"),
                       "HTTP 400 must no longer fall through to the generic connectivity message")

        let notFound = UserFriendlyErrorMapper.map(
            GeminiError.http(status: 404, body: "model gemini-x was not found"))
        XCTAssertFalse(notFound.contains("تحقق من اتصال الإنترنت"),
                       "HTTP 404 must map to a model-availability message")
    }
}
