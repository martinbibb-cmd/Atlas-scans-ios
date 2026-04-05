import SwiftUI
import UIKit

// MARK: - ImagePickerView
//
// A UIViewControllerRepresentable that wraps UIImagePickerController for
// camera capture and photo-library import.
//
// Usage:
//   ImagePickerView(source: .camera) { image in ... }
//
// Requires Info.plist keys:
//   NSCameraUsageDescription          — for .camera source
//   NSPhotoLibraryUsageDescription    — for .photoLibrary source

struct ImagePickerView: UIViewControllerRepresentable {

    enum Source {
        case camera
        case photoLibrary

        fileprivate var pickerSourceType: UIImagePickerController.SourceType {
            switch self {
            case .camera:        return .camera
            case .photoLibrary:  return .photoLibrary
            }
        }
    }

    let source: Source
    let onImagePicked: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = source.pickerSourceType
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject,
                             UIImagePickerControllerDelegate,
                             UINavigationControllerDelegate {

        let parent: ImagePickerView

        init(parent: ImagePickerView) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImagePicked(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

