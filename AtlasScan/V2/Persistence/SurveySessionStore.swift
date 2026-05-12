/// SurveySessionStore — High-level wrapper around the existing
/// `AtomicSessionStore` (AtlasScanCore) and `CaptureSessionPersistence`
/// (legacy, AtlasScan main target).
///
/// Adds the survey-shell concepts on top of the underlying envelope:
///   - `workspaceId` / `visitId` / `sessionId` top-level identity
///   - resume helpers (`loadActiveSession`, `clearActiveSession`)
///   - shell-status (`AtlasScanSessionStatus`) tracking
///
/// This type does *not* replace `ScanSessionCoordinator`. The coordinator
/// continues to own the live `SessionCaptureV2` mutation; this store owns the
/// shell-level descriptor and the active-session pointer in `UserDefaults`.

import Foundation
import AtlasScanCore

@MainActor
public final class SurveySessionStore {
    public static let shared = SurveySessionStore()

    public static let activeShellKey = "atlas.survey.activeShellSession.v1"

    private let defaults: UserDefaults
    private let captureStore: AtomicSessionStore
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public init(
        defaults: UserDefaults = .standard,
        captureStore: AtomicSessionStore = .shared
    ) {
        self.defaults = defaults
        self.captureStore = captureStore
    }

    // MARK: - Active shell session

    /// Loads the currently-active shell session descriptor, if any.
    public func loadActiveSession() -> AtlasScanSessionV1? {
        guard let data = defaults.data(forKey: Self.activeShellKey) else { return nil }
        return try? decoder.decode(AtlasScanSessionV1.self, from: data)
    }

    /// Persists the shell session descriptor. Called whenever the user
    /// changes workspace/visit, or status transitions.
    public func saveActiveSession(_ session: AtlasScanSessionV1) {
        var updated = session
        updated.updatedAt = Date()
        if let data = try? encoder.encode(updated) {
            defaults.set(data, forKey: Self.activeShellKey)
        }
    }

    /// Clears the shell session pointer. Does *not* delete the underlying
    /// `SessionCaptureV2` JSON on disk — `ScanSessionCoordinator` owns that.
    public func clearActiveSession() {
        defaults.removeObject(forKey: Self.activeShellKey)
    }

    // MARK: - Capture envelope passthrough

    /// Loads the underlying `SessionCaptureV2` for `visitId`, if it exists on
    /// disk. Returns `nil` for never-touched visits.
    public func loadCaptureEnvelope(for visitId: UUID) -> SessionCaptureV2? {
        try? captureStore.load(visitId: visitId)
    }

    /// Persists the underlying capture envelope.
    public func saveCaptureEnvelope(_ session: SessionCaptureV2) throws {
        try captureStore.save(session)
    }

    /// Convenience: build (or refresh) a shell descriptor for `visit` in
    /// `workspace`, persist it, and return it. Used when the user picks a
    /// visit from the picker.
    public func startOrResume(
        workspaceId: String?,
        visitId: UUID,
        currentLifecycle: VisitCaptureLifecycleState
    ) -> AtlasScanSessionV1 {
        if let existing = loadActiveSession(),
           existing.visitId == visitId {
            var refreshed = existing
            refreshed.status = AtlasScanSessionStatus.from(lifecycle: currentLifecycle)
            refreshed.lastActiveAt = Date()
            saveActiveSession(refreshed)
            return refreshed
        }

        let fresh = AtlasScanSessionV1(
            visitId: visitId,
            workspaceId: workspaceId,
            status: AtlasScanSessionStatus.from(lifecycle: currentLifecycle)
        )
        saveActiveSession(fresh)
        return fresh
    }
}
