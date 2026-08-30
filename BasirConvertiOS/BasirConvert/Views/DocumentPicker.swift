import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// Uses the native UIKit document picker in copy mode. This avoids the
/// provider/type-matching issue that can leave otherwise valid files inert in
/// SwiftUI's fileImporter on some iOS file providers.
struct BasirDocumentPicker: UIViewControllerRepresentable {
    var contentTypes: [UTType] = UTType.basirSupportedDocuments
    var allowsMultipleSelection = true
    let onPick: ([URL]) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: contentTypes,
            asCopy: true
        )
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = allowsMultipleSelection
        picker.shouldShowFileExtensions = true
        picker.modalPresentationStyle = .fullScreen
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) { }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let parent: BasirDocumentPicker

        init(parent: BasirDocumentPicker) {
            self.parent = parent
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            guard !urls.isEmpty else {
                parent.onCancel()
                return
            }
            parent.onPick(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onCancel()
        }
    }
}

