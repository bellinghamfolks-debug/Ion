import SwiftUI
import UIKit
import PhotosUI
import VisionKit
import QuickLook
import UniformTypeIdentifiers

struct StablePreviewItem: Identifiable, Equatable {
    let url: URL

    var id: String {
        PreviewReloadPolicy.normalized(url).absoluteString
    }
}

enum PreviewReloadPolicy {
    static func normalized(_ url: URL) -> URL {
        url.isFileURL ? url.standardizedFileURL : url
    }

    static func shouldReload(current: URL, incoming: URL) -> Bool {
        normalized(current) != normalized(incoming)
    }
}

struct PhotoLibraryPicker: UIViewControllerRepresentable {
    let onPick: ([URL]) -> Void
    let onError: (Error) -> Void
    let onCancel: () -> Void
    /// Images saved so far, out of the number chosen.
    var onProgress: ((Int, Int) -> Void)? = nil

    /// Long edge kept from each photo: sharper than any page needs, while a
    /// 48-megapixel photo is never decoded at full size.
    static let maximumPixel: CGFloat = 5_000
    /// Photos read at the same time.
    static let parallelImports = 3

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 0
        configuration.selection = .ordered
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) { }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoLibraryPicker
        init(parent: PhotoLibraryPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard !results.isEmpty else { parent.onCancel(); return }
            let parent = self.parent
            let providers = results.map(\.itemProvider)
            parent.onProgress?(0, providers.count)
            Task { @MainActor in
                do {
                    let urls = try await PhotoLibraryPicker.importAll(providers) { done in
                        parent.onProgress?(done, providers.count)
                    }
                    parent.onPick(urls)
                } catch {
                    parent.onError(error)
                }
            }
        }
    }

    /// Saves the chosen photos in their chosen order, a few at a time.
    @MainActor
    static func importAll(_ providers: [NSItemProvider], progress: @escaping (Int) -> Void) async throws -> [URL] {
        var ordered = [URL?](repeating: nil, count: providers.count)
        var done = 0
        try await withThrowingTaskGroup(of: (Int, URL).self) { group in
            var next = 0
            func addNext() {
                guard next < providers.count else { return }
                let index = next
                let provider = providers[index]
                next += 1
                group.addTask { (index, try await importImage(provider, index: index)) }
            }
            for _ in 0..<min(parallelImports, providers.count) { addNext() }
            while let (index, url) = try await group.next() {
                ordered[index] = url
                done += 1
                progress(done)
                addNext()
            }
        }
        return ordered.compactMap { $0 }
    }

    private static func importImage(_ provider: NSItemProvider, index: Int) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { file, error in
                // The file is deleted when this returns, so it is read here.
                do {
                    if let error { throw error }
                    guard let file,
                          let image = ImagePDFBuilder.downsample(file, maxPixel: maximumPixel),
                          let jpeg = UIImage(cgImage: image).jpegData(compressionQuality: 0.94) else {
                        throw BasirError.invalidFileContent
                    }
                    continuation.resume(returning: try FileAccess.persistImportedData(jpeg, preferredName: "صورة \(index + 1).jpg"))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    let onError: (Error) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) { }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(parent: CameraPicker) { self.parent = parent }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true); parent.onCancel()
        }
        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            picker.dismiss(animated: true)
            do {
                guard let image = info[.originalImage] as? UIImage,
                      let data = image.jpegData(compressionQuality: 0.94) else {
                    throw BasirError.invalidFileContent
                }
                parent.onPick(try FileAccess.persistImportedData(data, preferredName: "صورة الكاميرا.jpg"))
            } catch { parent.onError(error) }
        }
    }
}

struct DocumentScanner: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    let onError: (Error) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }
    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) { }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScanner
        init(parent: DocumentScanner) { self.parent = parent }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            controller.dismiss(animated: true); parent.onCancel()
        }
        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            controller.dismiss(animated: true); parent.onError(error)
        }
        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            controller.dismiss(animated: true)
            do {
                let images = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
                let urls = try MediaImport.persist(images, prefix: "مسح")
                parent.onPick(try MediaImport.combineImagesAsPDF(urls, name: "مستند ممسوح.pdf"))
            } catch { parent.onError(error) }
        }
    }
}

struct QuickLookPreview: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url, onClose: { dismiss() })
    }

    func makeUIViewController(context: Context) -> UINavigationController {
        let preview = QLPreviewController()
        preview.dataSource = context.coordinator
        context.coordinator.previewController = preview
        preview.navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: context.coordinator,
            action: #selector(Coordinator.closePreview)
        )
        preview.navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .action,
            target: context.coordinator,
            action: #selector(Coordinator.sharePreview)
        )
        return UINavigationController(rootViewController: preview)
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {
        guard PreviewReloadPolicy.shouldReload(current: context.coordinator.url, incoming: url) else {
            return
        }
        context.coordinator.url = url
        context.coordinator.previewController?.reloadData()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL
        let onClose: () -> Void
        weak var previewController: QLPreviewController?

        init(url: URL, onClose: @escaping () -> Void) {
            self.url = url
            self.onClose = onClose
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }

        @objc func closePreview() { onClose() }

        @objc func sharePreview() {
            guard let previewController else { return }
            let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            if let popover = share.popoverPresentationController {
                popover.sourceView = previewController.view
                popover.sourceRect = CGRect(x: previewController.view.bounds.midX,
                                            y: previewController.view.bounds.minY + 44,
                                            width: 1, height: 1)
            }
            previewController.present(share, animated: true)
        }
    }
}

struct ExportDocumentPicker: UIViewControllerRepresentable {
    let urls: [URL]
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        UIDocumentPickerViewController(forExporting: urls, asCopy: true)
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) { }
}

struct ActivityShareView: UIViewControllerRepresentable {
    let urls: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: urls, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
}

struct OpenInApplicationView: UIViewControllerRepresentable {
    let url: URL
    func makeCoordinator() -> Coordinator { Coordinator(url: url) }
    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.backgroundColor = .clear
        DispatchQueue.main.async {
            context.coordinator.interaction.presentOpenInMenu(
                from: controller.view.bounds,
                in: controller.view,
                animated: true
            )
        }
        return controller
    }
    func updateUIViewController(_ controller: UIViewController, context: Context) { }
    final class Coordinator: NSObject, UIDocumentInteractionControllerDelegate {
        let interaction: UIDocumentInteractionController
        init(url: URL) {
            interaction = UIDocumentInteractionController(url: url)
            super.init()
            interaction.delegate = self
        }
    }
}
