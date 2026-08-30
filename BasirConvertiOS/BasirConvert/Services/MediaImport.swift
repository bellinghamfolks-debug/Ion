import Foundation
import UIKit
import PDFKit

enum MediaImport {
    static func persist(_ images: [UIImage], prefix: String = "صورة") throws -> [URL] {
        try images.enumerated().map { index, image in
            guard let data = image.jpegData(compressionQuality: 0.92) else {
                throw BasirError.invalidFileContent
            }
            return try FileAccess.persistImportedData(
                data,
                preferredName: "\(prefix) \(index + 1).jpg"
            )
        }
    }

    static func combineImagesAsPDF(_ imageURLs: [URL], name: String = "صور مجمعة.pdf") throws -> URL {
        guard !imageURLs.isEmpty else { throw BasirError.emptyDocument }
        let document = PDFDocument()
        for (index, url) in imageURLs.enumerated() {
            guard let image = UIImage(contentsOfFile: url.path), let page = PDFPage(image: image) else {
                throw BasirError.invalidFileContent
            }
            document.insert(page, at: index)
        }
        guard let data = document.dataRepresentation() else { throw BasirError.invalidFileContent }
        return try FileAccess.persistImportedData(data, preferredName: name)
    }

    @MainActor
    static func pasteboardImages() throws -> [URL] {
        guard let images = UIPasteboard.general.images, !images.isEmpty else {
            throw BasirError.emptyDocument
        }
        return try persist(images, prefix: "صورة ملصقة")
    }
}

