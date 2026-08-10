import XCTest
import CoreGraphics
@testable import TrueFrame

final class CropSolverTests: XCTestCase {

    func testNoRotationKeepsFullImage() {
        let rect = CropSolver.largestValidCrop(imageSize: CGSize(width: 4000, height: 3000), degrees: 0)
        XCTAssertEqual(rect.width, 1, accuracy: 1e-9)
        XCTAssertEqual(rect.height, 1, accuracy: 1e-9)
        XCTAssertEqual(CropSolver.croppedAreaFraction(rect), 0, accuracy: 1e-9)
    }

    func testSquareAt45DegreesLosesAboutHalf() {
        // The largest inscribed axis-aligned square in a square rotated 45° has
        // side w/√2, so ~50% of the area is cropped.
        let rect = CropSolver.largestValidCrop(imageSize: CGSize(width: 1000, height: 1000), degrees: 45)
        XCTAssertEqual(CropSolver.croppedAreaFraction(rect), 0.5, accuracy: 0.02)
    }

    func testSmallAngleCropsLittle() {
        let rect = CropSolver.largestValidCrop(imageSize: CGSize(width: 4000, height: 3000), degrees: 5)
        let frac = CropSolver.croppedAreaFraction(rect)
        XCTAssertGreaterThan(frac, 0)
        XCTAssertLessThan(frac, 0.25)
    }

    func testCropIsSymmetricInAngle() {
        let a = CropSolver.largestValidCrop(imageSize: CGSize(width: 4000, height: 3000), degrees: 12)
        let b = CropSolver.largestValidCrop(imageSize: CGSize(width: 4000, height: 3000), degrees: -12)
        XCTAssertEqual(a.width, b.width, accuracy: 1e-9)
        XCTAssertEqual(a.height, b.height, accuracy: 1e-9)
    }

    func testCropIsCenteredAndInBounds() {
        let rect = CropSolver.largestValidCrop(imageSize: CGSize(width: 4000, height: 3000), degrees: 15)
        XCTAssertEqual(rect.x, (1 - rect.width) / 2, accuracy: 1e-9)
        XCTAssertEqual(rect.y, (1 - rect.height) / 2, accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(rect.x, 0)
        XCTAssertLessThanOrEqual(rect.x + rect.width, 1 + 1e-9)
    }

    func testLargerAngleCropsMore() {
        let small = CropSolver.croppedAreaFraction(CropSolver.largestValidCrop(imageSize: .init(width: 4000, height: 3000), degrees: 5))
        let large = CropSolver.croppedAreaFraction(CropSolver.largestValidCrop(imageSize: .init(width: 4000, height: 3000), degrees: 20))
        XCTAssertGreaterThan(large, small)
    }
}
