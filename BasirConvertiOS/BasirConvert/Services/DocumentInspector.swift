import Foundation
import PDFKit
import ImageIO
import CryptoKit

enum PageSelectionParser {
    static func pages(from specification: String, total: Int) throws -> [Int] {
        guard total > 0 else { return [] }
        let text = specification
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "،", with: ",")
        if text.isEmpty { return Array(1...total) }

        var result = Set<Int>()
        for token in text.split(separator: ",", omittingEmptySubsequences: true) {
            let pieces = token.split(separator: "-", omittingEmptySubsequences: false)
            if pieces.count == 1, let page = Int(pieces[0]), (1...total).contains(page) {
                result.insert(page)
            } else if pieces.count == 2,
                      let first = Int(pieces[0]), let last = Int(pieces[1]),
                      first > 0, last >= first, last <= total {
                result.formUnion(first...last)
            } else {
                throw BasirError.invalidPageSelection
            }
        }
        guard !result.isEmpty else { throw BasirError.invalidPageSelection }
        return result.sorted()
    }
}

enum DocumentInspector {
    static func inspect(_ url: URL, includeChecksum: Bool = true) throws -> DocumentMetadata {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile != false else { throw BasirError.invalidFileContent }
        let byteCount = Int64(values.fileSize ?? 0)
        guard byteCount > 0 else { throw BasirError.emptyDocument }
        guard byteCount <= FileAccess.maximumSourceBytes else { throw BasirError.fileTooLarge(byteCount) }
        try FileAccess.validateSignature(of: url)

        let type = FileAccess.mimeType(for: url)
        var count: Int?
        var width: Int?
        var height: Int?
        if url.pathExtension.lowercased() == "pdf" {
            guard let pdf = PDFDocument(url: url) else { throw BasirError.invalidFileContent }
            if pdf.isEncrypted && pdf.isLocked { throw BasirError.passwordProtectedPDF }
            count = pdf.pageCount
        } else if SupportedInput.imageExtensions.contains(url.pathExtension.lowercased()),
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            count = CGImageSourceGetCount(source)
            width = properties[kCGImagePropertyPixelWidth] as? Int
            height = properties[kCGImagePropertyPixelHeight] as? Int
        }

        return DocumentMetadata(
            filename: url.lastPathComponent,
            contentType: type,
            byteCount: byteCount,
            itemCount: count,
            pixelWidth: width,
            pixelHeight: height,
            checksum: includeChecksum ? try sha256(url) : nil
        )
    }

    static func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            try Task.checkCancellation()
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func unlockedCopy(of url: URL, password: String) throws -> URL {
        guard let document = PDFDocument(url: url), document.isEncrypted,
              document.unlock(withPassword: password), !document.isLocked,
              let data = document.dataRepresentation() else {
            throw BasirError.passwordProtectedPDF
        }
        let name = url.deletingPathExtension().lastPathComponent + " - unlocked.pdf"
        return try FileAccess.persistImportedData(data, preferredName: name)
    }
}

