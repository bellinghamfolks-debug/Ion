import Foundation
import Photos
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics

/// Saves corrected photos as new copies and persists a local audit record.
public final class PhotoLibraryManager {

    public enum SaveError: Error { case encodeFailed, notAuthorized }

    public init() {}

    public func saveCorrectedCopy(_ image: CGImage,
                                  provenance: EditingProvenance,
                                  asHEIC: Bool = true,
                                  completion: @escaping (Result<Void, Error>) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { completion(.failure(SaveError.notAuthorized)) }
                return
            }

            guard let data = self.encode(image, asHEIC: asHEIC) else {
                DispatchQueue.main.async { completion(.failure(SaveError.encodeFailed)) }
                return
            }

            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            } completionHandler: { success, error in
                if success {
                    self.persistProvenance(provenance)
                }
                DispatchQueue.main.async {
                    completion(success
                               ? .success(())
                               : .failure(error ?? SaveError.encodeFailed))
                }
            }
        }
    }

    private func encode(_ image: CGImage, asHEIC: Bool) -> Data? {
        let type = (asHEIC ? UTType.heic : UTType.jpeg).identifier as CFString
        let output = NSMutableData()

        guard let destination = CGImageDestinationCreateWithData(output, type, 1, nil) else {
            if asHEIC { return encode(image, asHEIC: false) }
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.95
        ]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    private func persistProvenance(_ provenance: EditingProvenance) {
        guard let directory = FileManager.default.urls(for: .documentDirectory,
                                                       in: .userDomainMask).first else {
            return
        }

        let folder = directory.appendingPathComponent("Provenance", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder,
                                                    withIntermediateDirectories: true)
            let milliseconds = Int(Date().timeIntervalSince1970 * 1_000)
            let name = "provenance-\(milliseconds)-\(UUID().uuidString).json"
            let data = try JSONEncoder().encode(provenance)
            try data.write(to: folder.appendingPathComponent(name), options: .atomic)
        } catch {
            // The photo is already safely saved in Photos. Audit persistence is
            // best-effort and must never roll back or delete the user's image.
        }
    }
}
