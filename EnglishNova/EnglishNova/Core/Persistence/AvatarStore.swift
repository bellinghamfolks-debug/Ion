import SwiftUI
import UIKit

/// Stores the user's profile picture as a JPEG in the app's Documents folder.
@MainActor
final class AvatarStore: ObservableObject {
    static let shared = AvatarStore()

    @Published private(set) var image: UIImage?

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("profile-avatar.jpg")
    }

    init() {
        if let data = try? Data(contentsOf: fileURL) {
            image = UIImage(data: data)
        }
    }

    func save(_ newImage: UIImage) {
        image = newImage
        if let data = newImage.jpegData(compressionQuality: 0.85) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func clear() {
        image = nil
        try? FileManager.default.removeItem(at: fileURL)
    }
}

/// Wraps `UIImagePickerController` for taking a photo with the camera (SwiftUI's
/// PhotosPicker covers the library; the camera still needs this bridge).
struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
