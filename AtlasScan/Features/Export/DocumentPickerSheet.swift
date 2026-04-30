import SwiftUI
#if canImport(UIKit)
import UIKit

// MARK: - DocumentPickerSheet
//
// A UIViewControllerRepresentable wrapper around UIDocumentPickerViewController
// in "export to service" mode.
//
// Used by ReviewExportView to present a "Save to Files / Cloud Drive" action
// that lets the engineer save the .atlasvisit package directly to iCloud Drive,
// On My iPhone, or any third-party Files provider — without going through the
// general share sheet.

struct DocumentPickerSheet: UIViewControllerRepresentable {

    /// The file URL(s) to export.
    let urls: [URL]

    /// Called when the user finishes (saved or cancelled).
    var onDismiss: (() -> Void)? = nil

    // MARK: - Coordinator

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var parent: DocumentPickerSheet

        init(_ parent: DocumentPickerSheet) {
            self.parent = parent
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onDismiss?()
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.onDismiss?()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: urls, asCopy: true)
        picker.delegate = context.coordinator
        picker.shouldShowFileExtensions = true
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
}

#endif
