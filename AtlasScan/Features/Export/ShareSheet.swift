import SwiftUI
#if canImport(UIKit)
import UIKit

// MARK: - ShareSheet
//
// A thin UIViewControllerRepresentable wrapper around UIActivityViewController.
// Used by AtlasHandoffView to present the system share sheet for the
// export file.

struct ShareSheet: UIViewControllerRepresentable {

    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#endif
