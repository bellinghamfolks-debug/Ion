import Foundation
import Photos
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics

/// Saves corrected photos as NEW copies (never overwriting the original) and
/// writes the machine-readable provenance record next to them. The source image
/// is always preserved separately by the caller.
public final class PhotoLibraryManager {

    public enum SaveError: Error { case encodeFailed, notAuthorized }

    public init() {}

    /// Save a corrected CGImage as a high-quality copy in the user's library and
    /// persist its `EditingProvenance` JSON in the app's documents.
    public func saveCorrectedCopy(_ image: CGImage,
                                  provenance: EditingProvenance,
                                  asHEIC: Bool = true,
                                  completion: @escaping (Result<Void, Error>) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                completion(.failure(SaveError.notAuthorized)); return
            }
            guard let data = self.encode(image, asHEIC: asHEIC) else {
                completion(.failure(SaveError.encodeFailed)); return
            }
            PHPhotoLibrary.shared().performChanges {
                let req = PHAssetCreationRequest.forAsset()
                req.addResource(with: .photo, data: data, options: nil)
            } completionHandler: { ok, err in
                if ok { self.persistProvenance(provenance) }
                DispatchQueue.main.async {
                    completion(ok ? .success(()) : .failure(err ?? SaveError.encodeFailed))
                }
            }
        }
    }

    private func encode(_ image: CGImage, asHEIC: Bool) -> Data? {
        let type = (asHEIC ? UTType.heic : UTType.jpeg).identifier as CFString
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, type, 1, nil) else {
            // HEIC may be unavailable on the simulator; fall back to JPEG.
            if asHEIC { return encode(image, asHEIC: false) }
            return nil
        }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.95]
        CGImageDestinationAddImage(dest, image, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    private func persistProvenance(_ p: EditingProvenance) {
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let folder = dir.appendingPathComponent("Provenance", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = "provenance-\(Int(Date().timeIntervalSince1970)).json"
        if let data = try? JSONEncoder().encode(p) {
            try? data.write(to: folder.appendingPathComponent(name))
        }
    }
}
