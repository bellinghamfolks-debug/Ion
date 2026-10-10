import PDFKit
import UIKit
import XCTest
@testable import BasirConvert

final class ImagePDFBuilderTests: XCTestCase {
    private var created: [URL] = []

    override func tearDown() {
        created.forEach { try? FileManager.default.removeItem(at: $0.deletingLastPathComponent()) }
        created.removeAll()
        super.tearDown()
    }

    /// A noisy photo-like image, so JPEG cannot shrink it to nothing.
    private func image(width: Int, height: Int, alpha: Bool = false, seed: UInt64 = 1) throws -> URL {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = !alpha
        var state = seed
        let picture = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            if !alpha {
                UIColor.white.setFill()
                context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            }
            for y in stride(from: 0, to: height, by: 8) {
                for x in stride(from: 0, to: width, by: 8) {
                    state = state &* 6364136223846793005 &+ 1442695040888963407
                    let shade = CGFloat(state >> 56) / 255
                    UIColor(white: shade, alpha: 1).setFill()
                    context.fill(CGRect(x: x, y: y, width: 8, height: 8))
                }
            }
        }
        let data = alpha ? picture.pngData()! : picture.jpegData(compressionQuality: 0.95)!
        let url = try FileAccess.persistImportedData(data, preferredName: alpha ? "test.png" : "test.jpg")
        created.append(url)
        return url
    }

    func testOnePagePerImageInTheGivenOrder() throws {
        let wide = try image(width: 1200, height: 800)
        let tall = try image(width: 800, height: 1200, seed: 2)
        let outcome = try ImagePDFBuilder.build([tall, wide], name: "ترتيب")
        created.append(outcome.url)
        let pdf = try XCTUnwrap(PDFDocument(url: outcome.url))
        XCTAssertEqual(pdf.pageCount, 2)
        XCTAssertEqual(outcome.pages, 2)
        XCTAssertTrue(outcome.skipped.isEmpty)
        let first = try XCTUnwrap(pdf.page(at: 0)).bounds(for: .mediaBox)
        let second = try XCTUnwrap(pdf.page(at: 1)).bounds(for: .mediaBox)
        XCTAssertGreaterThan(first.height, first.width, "the tall image comes first")
        XCTAssertGreaterThan(second.width, second.height)
        XCTAssertEqual(outcome.url.lastPathComponent, "ترتيب.pdf")
    }

    func testA4PagesTurnToMatchTheImage() {
        let landscape = ImagePDFBuilder.pageRect(for: CGSize(width: 3000, height: 2000), pageSize: .a4)
        XCTAssertEqual(landscape.width, 841.89, accuracy: 0.01)
        XCTAssertEqual(landscape.height, 595.28, accuracy: 0.01)
        let fit = ImagePDFBuilder.pageRect(for: CGSize(width: 1000, height: 2000), pageSize: .fit)
        XCTAssertEqual(fit.height, ImagePDFBuilder.fitLongEdge)
        XCTAssertEqual(fit.width, ImagePDFBuilder.fitLongEdge / 2, accuracy: 1)
    }

    func testAspectFitCentresWithoutStretching() {
        let rect = ImagePDFBuilder.aspectFit(CGSize(width: 200, height: 100), in: CGRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertEqual(rect.width, 100, accuracy: 0.001)
        XCTAssertEqual(rect.height, 50, accuracy: 0.001)
        XCTAssertEqual(rect.midY, 50, accuracy: 0.001)
    }

    func testUnreadableImagesAreSkippedAndReported() throws {
        let good = try image(width: 600, height: 800)
        let broken = try FileAccess.persistImportedData(Data("not an image".utf8), preferredName: "broken.jpg")
        created.append(broken)
        let outcome = try ImagePDFBuilder.build([good, broken, good], name: "x")
        created.append(outcome.url)
        XCTAssertEqual(outcome.pages, 2)
        XCTAssertEqual(outcome.skipped, [2])
    }

    func testTransparentImagesBecomeWhitePages() throws {
        let png = try image(width: 400, height: 400, alpha: true)
        let page = try XCTUnwrap(ImagePDFBuilder.pageImage(png, quality: .standard))
        XCTAssertEqual(page.alphaInfo == .none || page.alphaInfo == .noneSkipLast || page.alphaInfo == .noneSkipFirst, true)
    }

    func testQualityStepsDownToFitTheLimit() throws {
        let urls = try (0..<3).map { try image(width: 3000, height: 4000, seed: UInt64($0 + 5)) }
        let roomy = try ImagePDFBuilder.build(urls, name: "roomy")
        created.append(roomy.url)
        XCTAssertEqual(roomy.quality, .high)
        let limit = roomy.bytes - 1
        let tight = try ImagePDFBuilder.build(urls, name: "tight", maximumBytes: limit)
        created.append(tight.url)
        XCTAssertLessThan(tight.quality, .high)
        XCTAssertLessThanOrEqual(tight.bytes, limit)
    }

    func testFailsClearlyWhenEvenTheSmallestFileIsTooLarge() throws {
        let url = try image(width: 2000, height: 2000)
        XCTAssertThrowsError(try ImagePDFBuilder.build([url], name: "x", maximumBytes: 10)) { error in
            guard case BasirError.fileTooLarge = error else { return XCTFail("unexpected \(error)") }
        }
    }

    func testTooManyImagesIsRefusedUpFront() {
        let urls = Array(repeating: URL(fileURLWithPath: "/tmp/none.jpg"), count: ImagePDFBuilder.maximumImages + 1)
        XCTAssertThrowsError(try ImagePDFBuilder.build(urls, name: "x")) { error in
            guard case BasirError.tooManyImages(let count, let limit) = error else { return XCTFail("unexpected \(error)") }
            XCTAssertEqual(count, ImagePDFBuilder.maximumImages + 1)
            XCTAssertEqual(limit, ImagePDFBuilder.maximumImages)
        }
    }

    func testFileNamesAreSafeAndEndInPDF() {
        XCTAssertEqual(ImagePDFBuilder.pdfName("فاتورة.PDF"), "فاتورة.pdf")
        XCTAssertEqual(ImagePDFBuilder.pdfName("a/b:c"), "a-b-c.pdf")
        XCTAssertEqual(ImagePDFBuilder.pdfName("   "), "صور.pdf")
    }

    func testDownsampleKeepsTheLongEdgeWithinTheLimit() throws {
        let url = try image(width: 3000, height: 1500)
        let small = try XCTUnwrap(ImagePDFBuilder.downsample(url, maxPixel: 600))
        XCTAssertEqual(max(small.width, small.height), 600)
    }
}
