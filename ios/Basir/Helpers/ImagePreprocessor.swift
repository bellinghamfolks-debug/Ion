// ImagePreprocessor.swift
// Memory-bounded image downsampling for every AI image path.
// ImageIO decodes directly to the requested thumbnail size instead of
// materialising a multi-megapixel UIImage and resizing it afterwards.

import Foundation
import UIKit
import ImageIO

enum ImagePreprocessor {
    static let defaultMaxLongEdge = 1_600
    static let defaultQuality: CGFloat = 0.85
    static let maximumInputBytes = 128 * 1_024 * 1_024

    static func jpeg(from data: Data,
                     maxLongEdge: Int = defaultMaxLongEdge,
                     quality: CGFloat = defaultQuality) -> Data? {
        guard !data.isEmpty,
              data.count <= maximumInputBytes,
              let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }
        return jpeg(from: source, maxLongEdge: maxLongEdge, quality: quality)
    }

    static func jpeg(fromFileURL url: URL,
                     maxLongEdge: Int = defaultMaxLongEdge,
                     quality: CGFloat = defaultQuality) -> Data? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
              values.isRegularFile == true,
              let size = values.fileSize,
              size > 0,
              size <= maximumInputBytes,
              let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            return nil
        }
        return jpeg(from: source, maxLongEdge: maxLongEdge, quality: quality)
    }

    private static var sourceOptions: CFDictionary {
        [kCGImageSourceShouldCache: false] as CFDictionary
    }

    private static func jpeg(from source: CGImageSource,
                             maxLongEdge: Int,
                             quality: CGFloat) -> Data? {
        guard maxLongEdge >= 256 else { return nil }
        let options: CFDictionary = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxLongEdge,
            kCGImageSourceShouldCacheImmediately: false
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            return nil
        }
        return UIImage(cgImage: image).jpegData(
            compressionQuality: min(max(quality, 0.45), 0.95))
    }
}
