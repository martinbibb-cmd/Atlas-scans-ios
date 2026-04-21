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
///   - Validates completion readiness and performs the explicit complete action.
///   - Persists changes through `ScanSessionStore` with debounced autosave.
///
/// Design:
///   - All mutations go through `update(_:)` so autosave fires on every change.
///   - Contract derivation (fieldSurvey, planningOverlay) is computed on demand
///     from the session; no duplicate storage.
///   - Missing optional fields in older sessions are handled lazily — the store
///     never mutates the session on open unless the engineer makes a change.
///   - `completeVisit()` performs an immediate, non-debounced save; if the save
///     fails the lifecycle is NOT advanced and `completionError` is set.
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

    // MARK: - Completion error

    /// Non-nil when a `completeVisit()` call failed to persist.
    ///
    /// The lifecycle is NOT advanced when this is set; the visit remains
    /// in its pre-completion state so the engineer can retry.
    @Published private(set) var completionError: String?

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
    /// If completion validation passes, the badge reflects `.readyToComplete`
    /// even if the persisted `visitLifecycle` is lower — so the engineer sees
    /// real-time feedback without needing to navigate to the Complete tab.
    var lifecycleBadgeStatus: VisitLifecycleStatus {
        if session.visitLifecycle == .complete { return .complete }
        if completionValidation.isCompletable { return .readyToComplete }
        return session.visitLifecycle
    }

    // MARK: - Derived: completion

    /// Whether the visit is currently in the `.complete` lifecycle state.
    var isCompleted: Bool {
        session.visitLifecycle == .complete
    }

    /// Completion validation result derived from current visit readiness.
    ///
    /// Checks all seven required survey items.  This is stricter than
    /// `visitReadiness.isReady`, which only checks a subset.
    var completionValidation: VisitCompletionValidationResult {
        validateVisitForCompletion(readiness: visitReadiness)
    }

    /// Whether the engineer is allowed to trigger explicit completion right now.
    ///
    /// False when the visit is already complete or when validation fails.
    var canCompleteVisit: Bool {
        !isCompleted && completionValidation.isCompletable
    }

    // MARK: - Completion action

    /// Explicitly completes the visit.
    ///
    /// Steps:
    ///   1. Validates completion readiness.
    ///   2. If invalid: sets `completionError` and returns without changing state.
    ///   3. If valid:
    ///      a. Writes lifecycle `.complete` and completion metadata in memory.
    ///      b. Performs an immediate, non-debounced save.
    ///      c. If save succeeds: commits the new session state.
    ///      d. If save fails: reverts the in-memory change, sets `completionError`.
    ///
    /// Completion is never implied by navigation or autosave — only this method
    /// can advance the lifecycle to `.complete`.
    func completeVisit() {
        completionError = nil

        guard completionValidation.isCompletable else {
            completionError = "Visit cannot be completed. Some required items are still missing."
            return
        }

        guard !isCompleted else { return }

        // Build the completed session in a local copy first.
        var completed = session
        completed.visitLifecycle = .complete
        completed.completedAt = Date()
        completed.completedByUserId = nil      // user identity not wired in this PR
        completed.completionMethod = .manual

        // Cancel any pending debounced save so we don't race with it.
        autosaveTask?.cancel()
        autosaveTask = nil

        saveState = .saving

        let saveSucceeded = sessionStore.save(completed)

        if saveSucceeded {
            session = completed
            saveState = .saved
        } else {
            // Do NOT advance the lifecycle — the visit is still incomplete.
            saveState = .unsaved
            completionError = "Failed to save the visit. Please check storage and try again."
        }
    }

    /// Clears any pending completion error so the UI can dismiss it.
    func clearCompletionError() {
        completionError = nil
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
                    roomID: obj.roomID?.uuidString,
                    note: obj.note,
                    replacesExisting: obj.replacesExisting
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
    ///
    /// Mutations are blocked after the visit has been completed to prevent
    /// accidental state changes to a closed record.
    func update(_ mutation: (inout PropertyScanSession) -> Void) {
        guard !isCompleted else { return }
        mutation(&session)
        scheduleAutosave()
    }

    // MARK: - Capture mutation helpers

    /// Adds a room with the given label and floor.
    ///
    /// Trims surrounding whitespace. No-ops if the trimmed label is empty.
    func addRoom(label: String, floor: Int = 0) {
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let room = ScannedRoom(propertyID: session.id, name: trimmed, floor: floor)
        update { $0.addRoom(room) }
    }

    /// Removes the room with the given ID, cascading to linked objects, photos,
    /// and adjacencies via the session helper.
    func removeRoom(id: UUID) {
        update { $0.removeRoom(id: id) }
    }

    /// Appends a pre-built photo to the session.
    ///
    /// The caller is responsible for persisting image bytes via `PhotoStore`.
    func addPhoto(_ photo: TaggedPhoto) {
        update { $0.addPhoto(photo) }
    }

    /// Removes the photo record with the given ID from the session.
    ///
    /// The caller is responsible for deleting image files via `PhotoStore`.
    func removePhoto(id: UUID) {
        update { $0.removePhoto(id: id) }
    }

    /// Adds a session-level key object of the given category.
    ///
    /// - Parameters:
    ///   - category: The service object category (e.g. `.boiler`, `.flue`).
    ///   - label:    Optional engineer label. Defaults to the category display name when empty.
    ///   - roomID:   Optional room to associate the object with. Defaults to the session ID.
    ///   - note:     Optional free-text note.
    func addKeyObject(
        category: ServiceObjectCategory,
        label: String = "",
        roomID: UUID? = nil,
        note: String = ""
    ) {
        let object = TaggedObject(
            roomID: roomID ?? session.id,
            category: category,
            label: label,
            notes: note
        )
        update { $0.addTaggedObject(object) }
    }

    /// Removes the session-level tagged object with the given ID.
    func removeKeyObject(id: UUID) {
        update { $0.removeTaggedObject(id: id) }
    }

    /// Adds a text-only note to the session.
    ///
    /// The text is stored as a `VoiceNote` with an empty audio filename and the
    /// text captured in both `caption` and `transcript`.  This satisfies the
    /// `hasNotes` readiness flag without requiring audio recording.
    ///
    /// No-ops if the trimmed text is empty.
    func addTextNote(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let note = VoiceNote(
            localFilename: "",
            caption: trimmed,
            kind: .observation,
            transcriptStatus: .completed,
            transcript: trimmed
        )
        update { $0.addVoiceNote(note) }
    }

    /// Removes the voice/text note with the given ID from the session.
    ///
    /// Delegates to `removeVoiceNote(id:)`.  Kept for backward compatibility
    /// with existing callers that use the text-note terminology.
    func removeTextNote(id: UUID) {
        removeVoiceNote(id: id)
    }

    // MARK: - Voice note recording

    /// Adds a recorded voice note to the session and kicks off transcription.
    ///
    /// The note is saved immediately with `transcriptStatus == .pending`.
    /// Transcription runs asynchronously; the note record is updated when the
    /// result arrives (via `applyTranscriptResult`).
    ///
    /// The note always persists regardless of whether transcription succeeds.
    /// Blocked after completion.
    func addVoiceNoteRecording(_ note: VoiceNote) {
        var pending = note
        pending.transcriptStatus = .pending
        update { $0.addVoiceNote(pending) }
        Task {
            await startTranscription(for: pending)
        }
    }

    /// Removes the voice or text note with the given ID from the session.
    ///
    /// Also deletes the local audio file when the note has a non-empty filename.
    /// Blocked after completion.
    func removeVoiceNote(id: UUID) {
        let filename = session.allVoiceNotes.first(where: { $0.id == id })?.localFilename
        update { $0.removeVoiceNote(id: id) }
        if let filename = filename, !filename.isEmpty {
            VoiceNoteStore.shared.delete(filename: filename)
        }
    }

    /// Applies a transcription result to an existing voice note record.
    ///
    /// This mutation bypasses the completion lock because it is a system-initiated
    /// update from an in-flight transcription task, not a user-initiated capture.
    /// The session is persisted via the normal debounced autosave.
    func applyTranscriptResult(noteID: UUID, transcript: String?, status: TranscriptStatus) {
        if let idx = session.voiceNotes.firstIndex(where: { $0.id == noteID }) {
            session.voiceNotes[idx].transcript = transcript
            session.voiceNotes[idx].transcriptStatus = status
            scheduleAutosave()
            return
        }
        for roomIdx in session.rooms.indices {
            if let noteIdx = session.rooms[roomIdx].voiceNotes.firstIndex(where: { $0.id == noteID }) {
                session.rooms[roomIdx].voiceNotes[noteIdx].transcript = transcript
                session.rooms[roomIdx].voiceNotes[noteIdx].transcriptStatus = status
                scheduleAutosave()
                return
            }
        }
    }

    // MARK: - Derived: consolidated notes

    /// The current consolidated note content derived from all voice and text notes.
    ///
    /// Transcript text is preferred for each note; caption is used as fallback.
    /// Empty/whitespace notes are excluded.  Computed on demand — not stored.
    var consolidatedNotes: VisitConsolidatedNotes {
        consolidateVisitNotes(voiceNotes: session.allVoiceNotes)
    }

    // MARK: - Private: transcription

    private func startTranscription(for note: VoiceNote) async {
        let fileURL = VoiceNoteStore.shared.fileURL(for: note.localFilename)
        let result = await VoiceNoteTranscriptionService.shared.transcribe(fileURL: fileURL)
        applyTranscriptResult(noteID: note.id, transcript: result.transcript, status: result.status)
    }

    // MARK: - Planning mutation helpers

    /// Adds a proposed emitter to the session planning overlay.
    ///
    /// Creates an `InstallMarkupObject` on the `.proposed` layer with the given
    /// emitter type, room, label, note, and replacement intent.
    ///
    /// - Parameters:
    ///   - roomID:           Optional room to associate the emitter with.
    ///   - type:             Emitter category (e.g. `.radiator`, `.towelRail`).
    ///   - label:            Optional engineer-assigned label.
    ///   - note:             Optional planning note.
    ///   - replacesExisting: True when the proposed emitter replaces an existing one.
    func addProposedEmitter(
        roomID: UUID? = nil,
        type: ServiceObjectCategory,
        label: String = "",
        note: String = "",
        replacesExisting: Bool = false
    ) {
        let obj = InstallMarkupObject(
            categoryRawValue: type.rawValue,
            label: label,
            position: NormalizedPoint2D(x: 0.5, y: 0.5),
            layer: .proposed,
            roomID: roomID,
            note: note,
            replacesExisting: replacesExisting
        )
        update { $0.installMarkupObjects.append(obj) }
    }

    /// Removes the proposed emitter with the given ID from the session.
    func removeProposedEmitter(id: UUID) {
        update { $0.installMarkupObjects.removeAll { $0.id == id } }
    }

    /// Adds an access note to the session planning annotations.
    ///
    /// - Parameters:
    ///   - roomID:        Optional room association.
    ///   - category:      Access note category (e.g. "ladder", "clearance").
    ///   - note:          The note text.
    func addAccessNote(roomID: UUID? = nil, category: String = "general", note: String) {
        let trimmed = note.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let annotation = PlanningAnnotation(
            text: trimmed,
            kind: .accessNote,
            roomID: roomID,
            category: category
        )
        update { $0.addPlanningAnnotation(annotation) }
    }

    /// Removes the access note with the given ID from the session.
    func removeAccessNote(id: UUID) {
        update { $0.removePlanningAnnotation(id: id) }
    }

    /// Adds a room plan note to the session planning annotations.
    ///
    /// - Parameters:
    ///   - roomID:    Room association (required for room plan notes).
    ///   - category:  Room plan category (e.g. "emitter", "pipework").
    ///   - note:      The note text.
    func addRoomPlanNote(roomID: UUID? = nil, category: String = "general", note: String) {
        let trimmed = note.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let annotation = PlanningAnnotation(
            text: trimmed,
            kind: .roomPlanNote,
            roomID: roomID,
            category: category
        )
        update { $0.addPlanningAnnotation(annotation) }
    }

    /// Removes the room plan note with the given ID from the session.
    func removeRoomPlanNote(id: UUID) {
        update { $0.removePlanningAnnotation(id: id) }
    }

    /// Adds a spec note to the session planning annotations.
    ///
    /// No-ops if the trimmed text is empty.
    func addSpecNote(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let annotation = PlanningAnnotation(text: trimmed, kind: .specNote)
        update { $0.addPlanningAnnotation(annotation) }
    }

    /// Removes the spec note with the given ID from the session.
    func removeSpecNote(id: UUID) {
        update { $0.removePlanningAnnotation(id: id) }
    }

    // MARK: - Room reassignment helpers

    /// Assigns or reassigns a key object to a room.
    ///
    /// Pass `nil` to move the object to the unassigned (session-level) state.
    /// Blocked after completion.
    func assignKeyObject(_ id: UUID, toRoom roomID: UUID?) {
        update { session in
            guard let index = session.taggedObjects.firstIndex(where: { $0.id == id }) else { return }
            session.taggedObjects[index].roomID = roomID ?? session.id
        }
    }

    /// Assigns or reassigns a proposed emitter to a room.
    ///
    /// Pass `nil` to mark the emitter as unassigned.
    /// Blocked after completion.
    func assignProposedEmitter(_ id: UUID, toRoom roomID: UUID?) {
        update { session in
            guard let index = session.installMarkupObjects.firstIndex(where: { $0.id == id }) else { return }
            session.installMarkupObjects[index].roomID = roomID
        }
    }

    /// Assigns or reassigns an access note to a room.
    ///
    /// Pass `nil` to mark the note as unassigned.
    /// Blocked after completion.
    func assignAccessNote(_ id: UUID, toRoom roomID: UUID?) {
        update { session in
            guard let index = session.planningAnnotations.firstIndex(where: {
                $0.id == id && $0.kind == .accessNote
            }) else { return }
            session.planningAnnotations[index].roomID = roomID
        }
    }

    /// Assigns or reassigns a room plan note to a room.
    ///
    /// Pass `nil` to mark the note as unassigned.
    /// Blocked after completion.
    func assignRoomPlanNote(_ id: UUID, toRoom roomID: UUID?) {
        update { session in
            guard let index = session.planningAnnotations.firstIndex(where: {
                $0.id == id && $0.kind == .roomPlanNote
            }) else { return }
            session.planningAnnotations[index].roomID = roomID
        }
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
