import Foundation
import Combine

// MARK: - VisitCaptureStore

/// Holds the single active `PropertyScanSession` for the current visit.
///
/// Design:
///   - Exactly one session is active at a time.
///   - All mutations are funnelled through `update(_:)` so that the
///     session is persisted on every meaningful change.
///   - Wraps `ScanSessionStore` for offline-first persistence.
@MainActor
final class VisitCaptureStore: ObservableObject {

    // MARK: Active session

    @Published private(set) var session: PropertyScanSession

    // MARK: Save state

    enum SaveState: Equatable {
        case saved
        case saving
        case unsaved
    }

    @Published private(set) var saveState: SaveState = .saved

    // MARK: Dependencies

    private let sessionStore: ScanSessionStore
    private var autosaveTask: Task<Void, Never>?

    // MARK: Init

    init(session: PropertyScanSession, sessionStore: ScanSessionStore) {
        self.session = session
        self.sessionStore = sessionStore
    }

    // MARK: Session mutation

    /// Applies a mutation closure to the active session and schedules autosave.
    func update(_ mutation: (inout PropertyScanSession) -> Void) {
        mutation(&session)
        scheduleAutosave()
    }

    // MARK: Autosave

    private func scheduleAutosave() {
        saveState = .unsaved
        autosaveTask?.cancel()
        autosaveTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000) // 800 ms debounce
            guard !Task.isCancelled else { return }
            saveState = .saving
            sessionStore.save(session)
            saveState = .saved
        }
    }

    /// Immediately persists the current session without debounce.
    func saveNow() {
        autosaveTask?.cancel()
        autosaveTask = nil
        saveState = .saving
        sessionStore.save(session)
        saveState = .saved
    }
}
