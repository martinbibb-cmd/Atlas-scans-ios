import Foundation
import SwiftUI

// MARK: - DeveloperModeStore
//
// Lightweight singleton that persists the developer-mode flag in UserDefaults.
//
// Developer mode exposes:
//   • Raw JSON inspector for export payloads.
//   • Copy JSON to clipboard.
//   • Extended logging / debug banners (future).
//
// Toggle:
//   • Tap the "Atlas Scan" version label on the home screen seven times.
//   • The same action disables developer mode if it was already enabled.

final class DeveloperModeStore: ObservableObject {

    // MARK: Shared instance

    static let shared = DeveloperModeStore()

    // MARK: Persisted flag

    @AppStorage("atlas.developerMode") var isEnabled: Bool = false {
        willSet { objectWillChange.send() }
    }

    // MARK: Init

    private init() {}

    // MARK: Toggle

    /// Flips the developer mode flag.
    func toggle() {
        isEnabled.toggle()
    }
}
