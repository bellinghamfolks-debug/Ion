import XCTest
@testable import TrueFrame

final class AuthenticityGuardTests: XCTestCase {

    func testGeometryAllowedInSafeMode() {
        let g = AuthenticityGuard(policy: .authenticitySafe)
        XCTAssertNoThrow(try g.authorize(.rotate))
        XCTAssertNoThrow(try g.authorize(.crop))
        XCTAssertNoThrow(try g.authorize(.perspectiveCorrect))
    }

    func testGenerativeBlockedInSafeMode() {
        let g = AuthenticityGuard(policy: .authenticitySafe)
        XCTAssertThrowsError(try g.authorize(.generativeFill))
        XCTAssertThrowsError(try g.authorize(.outpaint))
        XCTAssertThrowsError(try g.authorize(.skyGenerate))
    }

    func testTonalBlockedInSafeButAllowedInEnhanced() {
        XCTAssertThrowsError(try AuthenticityGuard(policy: .authenticitySafe).authorize(.exposureAdjust))
        XCTAssertNoThrow(try AuthenticityGuard(policy: .enhancedNonGenerative).authorize(.exposureAdjust))
    }

    func testGenerativeBlockedEvenInEnhanced() {
        XCTAssertThrowsError(try AuthenticityGuard(policy: .enhancedNonGenerative).authorize(.diffusionReconstruct))
    }

    func testProvenanceDisclosureDefaultsToNone() {
        let p = EditingProvenance(rotationDegrees: 11.8,
                                  cropRectNormalized: .full,
                                  croppedAreaFraction: 0.06,
                                  appliedOperations: [.rotate, .crop])
        XCTAssertFalse(p.generativeModelAlteredPixels)
        XCTAssertEqual(p.generativeDisclosure, "Generative modification: None.")
    }

    func testProvenanceRoundTripsThroughJSON() throws {
        let p = EditingProvenance(rotationDegrees: -5, cropRectNormalized: NormalizedRect(x: 0.02, y: 0.02, width: 0.96, height: 0.96), croppedAreaFraction: 0.08, appliedOperations: [.rotate, .horizonLevel, .crop])
        let data = try JSONEncoder().encode(p)
        let back = try JSONDecoder().decode(EditingProvenance.self, from: data)
        XCTAssertEqual(p, back)
    }
}
