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

    /// One PDF page per image, built a page at a time so long scans and
    /// large photo selections do not run out of memory.
    static func combineImagesAsPDF(_ imageURLs: [URL], name: String = "صور مجمعة.pdf") throws -> URL {
        try ImagePDFBuilder.build(imageURLs, name: name).url
    }

    @MainActor
    static func pasteboardImages() throws -> [URL] {
        guard let images = UIPasteboard.general.images, !images.isEmpty else {
            throw BasirError.emptyDocument
        }
        return try persist(images, prefix: "صورة ملصقة")
    }
}

