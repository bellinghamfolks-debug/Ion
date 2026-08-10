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
        let rect = CropSolver.largestValidCrop(imageSize: CGSize(width: 1000, height: 1000), degrees: 45)
        XCTAssertEqual(CropSolver.croppedAreaFraction(rect), 0.5, accuracy: 0.02)
    }

    func testSmallAngleCropsLittle() {
        let rect = CropSolver.largestValidCrop(imageSize: CGSize(width: 4000, height: 3000), degrees: 5)
        let fraction = CropSolver.croppedAreaFraction(rect)
        XCTAssertGreaterThan(fraction, 0)
        XCTAssertLessThan(fraction, 0.25)
    }

    func testCropIsSymmetricInAngle() {
        let positive = CropSolver.largestValidCrop(imageSize: CGSize(width: 4000, height: 3000), degrees: 12)
        let negative = CropSolver.largestValidCrop(imageSize: CGSize(width: 4000, height: 3000), degrees: -12)
        XCTAssertEqual(positive.width, negative.width, accuracy: 1e-9)
        XCTAssertEqual(positive.height, negative.height, accuracy: 1e-9)
    }

    func testCropIsCenteredAndInBounds() {
        let rect = CropSolver.largestValidCrop(imageSize: CGSize(width: 4000, height: 3000), degrees: 15)
        XCTAssertEqual(rect.x, (1 - rect.width) / 2, accuracy: 1e-9)
        XCTAssertEqual(rect.y, (1 - rect.height) / 2, accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(rect.x, 0)
        XCTAssertLessThanOrEqual(rect.x + rect.width, 1 + 1e-9)
    }

    func testLargerAngleCropsMore() {
        let small = CropSolver.croppedAreaFraction(
            CropSolver.largestValidCrop(imageSize: .init(width: 4000, height: 3000), degrees: 5)
        )
        let large = CropSolver.croppedAreaFraction(
            CropSolver.largestValidCrop(imageSize: .init(width: 4000, height: 3000), degrees: 20)
        )
        XCTAssertGreaterThan(large, small)
    }

    func testSafeAspectCropPreservesOriginalAspectRatio() {
        let imageSize = CGSize(width: 4000, height: 3000)
        let rect = CropSolver.safeAspectCrop(imageSize: imageSize, degrees: 13)
        let pixelWidth = rect.width * imageSize.width
        let pixelHeight = rect.height * imageSize.height
        XCTAssertEqual(pixelWidth / pixelHeight,
                       imageSize.width / imageSize.height,
                       accuracy: 1e-9)
    }

    func testSafeAspectCropFitsInsideLargestValidCrop() {
        let maximum = CropSolver.largestValidCrop(imageSize: CGSize(width: 4000, height: 3000), degrees: 13)
        let safe = CropSolver.safeAspectCrop(imageSize: CGSize(width: 4000, height: 3000), degrees: 13)
        XCTAssertLessThanOrEqual(safe.width, maximum.width + 1e-9)
        XCTAssertLessThanOrEqual(safe.height, maximum.height + 1e-9)
    }
}
