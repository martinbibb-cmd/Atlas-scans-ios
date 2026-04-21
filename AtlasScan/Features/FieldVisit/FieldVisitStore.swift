import Foundation
import Combine
import AtlasContracts

// MARK: - FieldVisitStore

/// Single observable store that owns the active field-visit draft.
///
/// Responsibilities:
///   - Holds the one `PropertyScanSession` being worked on.
///   - Derives `FieldSurveyV1` and `PlanningOverlayV1` from session state.
///   - Exposes `VisitReadinessV1` and `PlanningReadinessV1` via the contract helpers.
///   - Advances `visitLifecycle` when the engineer enters a new phase.
///   - Persists changes through `ScanSessionStore` with debounced autosave.
///
/// Design:
///   - All mutations go through `update(_:)` so autosave fires on every change.
///   - Contract derivation (fieldSurvey, planningOverlay) is computed on demand
///     from the session; no duplicate storage.
///   - Missing optional fields in older sessions are handled lazily — the store
///     never mutates the session on open unless the engineer makes a change.
@MainActor
final class FieldVisitStore: ObservableObject {

    // MARK: - Session

    @Published private(set) var session: PropertyScanSession

    // MARK: - Save state

    enum SaveState: Equatable {
        case saved
        case saving
        case unsaved
    }

    @Published private(set) var saveState: SaveState = .saved

    // MARK: - Dependencies

    private let sessionStore: ScanSessionStore
    private var autosaveTask: Task<Void, Never>?

    // MARK: - Init

    init(session: PropertyScanSession, sessionStore: ScanSessionStore) {
        self.session = session
        self.sessionStore = sessionStore
    }

    // MARK: - Lifecycle

    /// Advances the lifecycle to `.capturing` if still at `.draft`.
    ///
    /// Call when the engineer enters the Capture tab for the first time.
    func enterCapturePhase() {
        guard session.visitLifecycle == .draft else { return }
        update { $0.visitLifecycle = .capturing }
    }

    /// Advances the lifecycle to `.planning` if still at `.draft` or `.capturing`.
    ///
    /// Call when the engineer enters the Plan tab for the first time.
    func enterPlanningPhase() {
        guard session.visitLifecycle == .draft || session.visitLifecycle == .capturing else { return }
        update { $0.visitLifecycle = .planning }
    }

    // MARK: - Derived: visit lifecycle badge

    /// The lifecycle status to display in the shell header badge.
    ///
    /// If the survey readiness passes the critical checks, the badge reflects
    /// `.readyToComplete` even if the persisted `visitLifecycle` is lower —
    /// so the engineer sees real-time feedback without needing to navigate.
    var lifecycleBadgeStatus: VisitLifecycleStatus {
        if session.visitLifecycle == .complete { return .complete }
        if visitReadiness.isReady { return .readyToComplete }
        return session.visitLifecycle
    }

    // MARK: - Derived: field survey

    /// The current field survey payload derived from the session.
    ///
    /// This is computed on demand from the session's rooms, objects, and artefacts.
    /// It is never stored separately; derive it whenever the review surface needs it.
    var fieldSurvey: FieldSurveyV1 {
        let allObjects = session.allTaggedObjects

        let emitterCategories: Set<String> = [
            "radiator", "radiator_drop", "towel_rail", "ufh_zone", "fan_convector"
        ]
        let hotWaterCategories: Set<String> = [
            "cylinder", "thermal_store", "buffer_vessel"
        ]
        let boilerCategories: Set<String> = [
            "boiler", "heat_pump"
        ]

        let hasBoiler = allObjects.contains { boilerCategories.contains($0.category.rawValue) }
        let hasFlue = allObjects.contains { $0.category == .flue }
        let hasHotWaterSystem = allObjects.contains { hotWaterCategories.contains($0.category.rawValue) }
        let hasHeatingSystem = hasBoiler || allObjects.contains { emitterCategories.contains($0.category.rawValue) }

        let surveyRooms = session.rooms.map { room in
            FieldSurveyRoomV1(
                id: room.id.uuidString,
                name: room.name,
                photoCount: room.photos.count,
                voiceNoteCount: room.voiceNotes.count
            )
        }

        return FieldSurveyV1(
            rooms: surveyRooms,
            totalPhotoCount: session.totalPhotos,
            totalVoiceNoteCount: session.totalVoiceNotes,
            hasBoiler: hasBoiler,
            hasFlue: hasFlue,
            hasHotWaterSystem: hasHotWaterSystem,
            hasHeatingSystem: hasHeatingSystem
        )
    }

    // MARK: - Derived: planning overlay

    /// The current planning overlay derived from install markup and planning annotations.
    ///
    /// Proposed emitters come from `installMarkupObjects` where `layer == .proposed`
    /// and the category is an emitter type.  Routes come from `installMarkupRoutes`
    /// where `layer == .proposed`.  Annotation notes come from `planningAnnotations`.
    var planningOverlay: PlanningOverlayV1 {
        let emitterCategories: Set<String> = [
            "radiator", "radiator_drop", "towel_rail", "ufh_zone", "fan_convector"
        ]

        let proposedEmitters = session.installMarkupObjects
            .filter { $0.layer == .proposed && emitterCategories.contains($0.categoryRawValue) }
            .map { obj in
                ProposedEmitterV1(
                    id: obj.id.uuidString,
                    type: obj.categoryRawValue,
                    label: obj.label,
                    roomID: obj.roomID?.uuidString
                )
            }

        let routeMarkups = session.installMarkupRoutes
            .filter { $0.layer == .proposed }
            .map { route in
                RouteMarkupV1(
                    id: route.id.uuidString,
                    kind: route.kind.rawValue,
                    roomID: route.roomID?.uuidString,
                    notes: route.notes
                )
            }

        let accessNotes = session.planningAnnotations(ofKind: .accessNote)
            .map { note in
                PlanningNoteV1(
                    id: note.id.uuidString,
                    text: note.text,
                    roomID: note.roomID?.uuidString,
                    kind: note.kind.rawValue
                )
            }

        let roomPlanNotes = session.planningAnnotations(ofKind: .roomPlanNote)
            .map { note in
                PlanningNoteV1(
                    id: note.id.uuidString,
                    text: note.text,
                    roomID: note.roomID?.uuidString,
                    kind: note.kind.rawValue
                )
            }

        let specNotes = session.planningAnnotations(ofKind: .specNote)
            .map { note in
                PlanningNoteV1(
                    id: note.id.uuidString,
                    text: note.text,
                    roomID: note.roomID?.uuidString,
                    kind: note.kind.rawValue
                )
            }

        return PlanningOverlayV1(
            proposedEmitters: proposedEmitters,
            routeMarkups: routeMarkups,
            accessNotes: accessNotes,
            roomPlanNotes: roomPlanNotes,
            specNotes: specNotes
        )
    }

    // MARK: - Derived: readiness

    /// Visit readiness derived from the current field survey.
    var visitReadiness: VisitReadinessV1 {
        deriveVisitReadinessFromFieldSurvey(fieldSurvey)
    }

    /// Planning coverage derived from the current planning overlay.
    var planningReadiness: PlanningReadinessV1 {
        derivePlanningReadiness(planningOverlay)
    }

    // MARK: - Session mutation

    /// Applies `mutation` to the session and schedules autosave.
    func update(_ mutation: (inout PropertyScanSession) -> Void) {
        mutation(&session)
        scheduleAutosave()
    }

    // MARK: - Autosave

    private static let autosaveDebounceNanoseconds: UInt64 = 800_000_000

    private func scheduleAutosave() {
        saveState = .unsaved
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: Self.autosaveDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            self.saveState = .saving
            self.sessionStore.save(self.session)
            self.saveState = .saved
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
