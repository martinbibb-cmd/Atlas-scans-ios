/// SurveyAutosaveService — Debounced autosave coordinator for the new
/// continuous-survey shell.
///
/// Triggers a save when:
///   - the user performs a capture action (photo, tag, note, measurement)
///   - the room candidate changes (e.g. user confirms a new room)
///   - the SwiftUI `scenePhase` becomes `.background` or `.inactive`
///
/// Saves are debounced (default 200 ms) so a flurry of rapid mutations
/// coalesces into a single write. Forced saves (background transitions)
/// flush immediately and bypass the debounce.

import Foundation
import SwiftUI

@MainActor
public final class SurveyAutosaveService: ObservableObject {

    /// Trigger types — surfaces in `lastTrigger` for diagnostics.
    public enum Trigger: String, Sendable {
        case captureAction
        case roomCandidateChanged
        case scenePhaseBackground
        case manual
    }

    @Published public private(set) var lastSaveDate: Date?
    @Published public private(set) var lastTrigger: Trigger?
    @Published public private(set) var pendingSave: Bool = false

    private let debounce: TimeInterval
    private let save: () async throws -> Void
    private var pendingTask: Task<Void, Never>?

    public init(
        debounce: TimeInterval = 0.2,
        save: @escaping () async throws -> Void
    ) {
        self.debounce = debounce
        self.save = save
    }

    /// Schedules a debounced save. Coalesces with any in-flight pending save.
    public func schedule(_ trigger: Trigger) {
        lastTrigger = trigger
        pendingSave = true
        pendingTask?.cancel()
        let interval = debounce
        pendingTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            await self.flushNow(trigger: trigger)
        }
    }

    /// Immediately flushes any pending save. Use when the scene goes to
    /// background or the user explicitly leaves the survey.
    public func flushNow(trigger: Trigger = .manual) async {
        pendingTask?.cancel()
        pendingTask = nil
        do {
            try await save()
            lastSaveDate = Date()
            lastTrigger = trigger
            pendingSave = false
        } catch {
            // Surface failures via the underlying save closure's own error
            // handling; we just clear the pending flag here so the UI doesn't
            // spin forever.
            pendingSave = false
        }
    }

    /// SwiftUI helper — pass the current `scenePhase` and we'll flush on
    /// background/inactive transitions.
    public func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background, .inactive:
            Task { await flushNow(trigger: .scenePhaseBackground) }
        case .active:
            break
        @unknown default:
            break
        }
    }
}
