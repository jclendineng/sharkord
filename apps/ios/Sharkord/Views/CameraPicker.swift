import SwiftUI
import UIKit
import UniformTypeIdentifiers

// the system camera for a photo or a video, handed back as a file the upload can read
struct CameraPicker: UIViewControllerRepresentable {
    let onCapture: (URL) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()

        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
        picker.videoQuality = .typeHigh
        picker.delegate = context.coordinator

        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CameraPicker

        init(_ parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let url = Self.file(from: info) {
                parent.onCapture(url)
            }

            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }

        private static func file(from info: [UIImagePickerController.InfoKey: Any]) -> URL? {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)

            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            // the recording lives in a temporary spot the picker cleans up, so it is moved out
            if let movie = info[.mediaURL] as? URL {
                let target = directory.appending(path: "video.\(movie.pathExtension.isEmpty ? "mov" : movie.pathExtension)")

                return (try? FileManager.default.moveItem(at: movie, to: target)) == nil ? nil : target
            }

            guard let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.9) else {
                return nil
            }

            let target = directory.appending(path: "photo.jpg")

            return (try? data.write(to: target)) == nil ? nil : target
        }
    }
}
