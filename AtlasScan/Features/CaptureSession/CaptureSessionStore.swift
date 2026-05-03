import Foundation
import Combine

// MARK: - CaptureSessionStore
//
// Single visit-owned session state for one capture session.
//
// Design:
//   • Exactly one CaptureSessionDraft is active at a time.
//   • All mutations are funnelled through update(_:) so the session is
//     persisted on every meaningful change.
//   • Autosave is debounced 800 ms to avoid excessive disk writes.
//   • visit reference is required before export is allowed.

@MainActor
final class CaptureSessionStore: ObservableObject {

    // MARK: Published state

    @Published private(set) var draft: CaptureSessionDraft

    // MARK: Save state

    enum SaveState: Equatable {
        case saved
        case saving
        case unsaved
    }

    @Published private(set) var saveState: SaveState = .saved

    // MARK: Dependencies

    private let persistence: CaptureSessionPersistence
    private var autosaveTask: Task<Void, Never>?

    // MARK: Init

    init(
        draft: CaptureSessionDraft,
        persistence: CaptureSessionPersistence = .shared
    ) {
        self.draft = draft
        self.persistence = persistence
    }

    // MARK: - Session creation helpers

    /// Creates a new draft session with the given visit reference and optional appointment ID.
    ///
    /// - Parameters:
    ///   - visitReference: Human-readable job reference (e.g. "JOB-2025-001").
    ///   - appointmentId:  Cross-system appointment key from Atlas Recommendations
    ///                     (``AppointmentV1/appointmentId``).  Must be present in the
    ///                     exported ``SessionCaptureV1`` payload so Atlas can match the
    ///                     capture back to the appointment that triggered the visit.
    static func newSession(
        visitReference: String,
        appointmentId: String? = nil
    ) -> CaptureSessionDraft {
        var d = CaptureSessionDraft()
        d.visitReference = visitReference
        d.appointmentId = appointmentId
        return d
    }

    /// Resumes the last incomplete session if one exists, otherwise creates a new one.
    static func resumeOrCreate(
        visitReference: String,
        persistence: CaptureSessionPersistence = .shared
    ) -> CaptureSessionDraft {
        persistence.lastIncompleteDraft() ?? newSession(visitReference: visitReference)
    }

    // MARK: - Session mutation

    /// Applies a mutation closure to the active draft and schedules autosave.
    func update(_ mutation: (inout CaptureSessionDraft) -> Void) {
        mutation(&draft)
        scheduleAutosave()
    }

    // MARK: - Room scans

    func addRoomScan(_ scan: CapturedRoomScanDraft) {
        update { $0.roomScans.append(scan) }
    }

    func removeRoomScan(id: UUID) {
        update { $0.roomScans.removeAll { $0.id == id } }
    }

    func updateRoomScan(_ scan: CapturedRoomScanDraft) {
        update { draft in
            if let idx = draft.roomScans.firstIndex(where: { $0.id == scan.id }) {
                draft.roomScans[idx] = scan
            }
        }
    }

    // MARK: - Photos

    func addPhoto(_ photo: CapturedPhotoDraft) {
        update { $0.photos.append(photo) }
    }

    func removePhoto(id: UUID) {
        update { $0.photos.removeAll { $0.id == id } }
    }

    // MARK: - Voice notes

    func addVoiceNote(_ note: CapturedVoiceNoteDraft) {
        update { $0.voiceNotes.append(note) }
    }

    func removeVoiceNote(id: UUID) {
        update { $0.voiceNotes.removeAll { $0.id == id } }
    }

    func updateVoiceNote(_ note: CapturedVoiceNoteDraft) {
        update { draft in
            if let idx = draft.voiceNotes.firstIndex(where: { $0.id == note.id }) {
                draft.voiceNotes[idx] = note
            }
        }
    }

    // MARK: - Object pins

    func addObjectPin(_ pin: CapturedObjectPinDraft) {
        update { $0.objectPins.append(pin) }
    }

    func removeObjectPin(id: UUID) {
        update { $0.objectPins.removeAll { $0.id == id } }
    }

    func updateObjectPin(_ pin: CapturedObjectPinDraft) {
        update { draft in
            if let idx = draft.objectPins.firstIndex(where: { $0.id == pin.id }) {
                draft.objectPins[idx] = pin
            }
        }
    }

    // MARK: - Review status

    /// Updates the review status of a single evidence item by its UUID.
    ///
    /// Searches all evidence categories for a matching ID and applies the new status.
    func updateReviewStatus(id: UUID, status: EvidenceReviewStatus) {
        update { draft in
            CaptureReviewUpdater.updateReviewStatus(id: id, status: status, in: &draft)
        }
    }

    // MARK: - Floor plan snapshots

    func addFloorPlanSnapshot(_ snapshot: CapturedFloorPlanSnapshotDraft) {
        update { $0.floorPlanSnapshots.append(snapshot) }
    }

    func removeFloorPlanSnapshot(id: UUID) {
        update { $0.floorPlanSnapshots.removeAll { $0.id == id } }
    }

    // MARK: - Fabric records

    func addFabricRecord(_ record: CapturedFloorPlanFabricDraft) {
        update { $0.fabricRecords.append(record) }
    }

    func removeFabricRecord(id: UUID) {
        update { $0.fabricRecords.removeAll { $0.id == id } }
    }

    func updateFabricRecord(_ record: CapturedFloorPlanFabricDraft) {
        update { draft in
            if let idx = draft.fabricRecords.firstIndex(where: { $0.id == record.id }) {
                draft.fabricRecords[idx] = record
            }
        }
    }

    // MARK: - Hazard observations

    func addHazardObservation(_ hazard: CapturedHazardObservationDraft) {
        update { $0.hazardObservations.append(hazard) }
    }

    func removeHazardObservation(id: UUID) {
        update { $0.hazardObservations.removeAll { $0.id == id } }
    }

    func updateHazardObservation(_ hazard: CapturedHazardObservationDraft) {
        update { draft in
            if let idx = draft.hazardObservations.firstIndex(where: { $0.id == hazard.id }) {
                draft.hazardObservations[idx] = hazard
            }
        }
    }

    // MARK: - Quote planner anchors

    func addQuotePlannerAnchor(_ anchor: CapturedQuotePlannerAnchorDraft) {
        update { $0.quotePlannerAnchors.append(anchor) }
    }

    func removeQuotePlannerAnchor(id: UUID) {
        update { $0.quotePlannerAnchors.removeAll { $0.id == id } }
    }

    func updateQuotePlannerAnchor(_ anchor: CapturedQuotePlannerAnchorDraft) {
        update { draft in
            if let idx = draft.quotePlannerAnchors.firstIndex(where: { $0.id == anchor.id }) {
                draft.quotePlannerAnchors[idx] = anchor
            }
        }
    }

    // MARK: - Visit reference

    func setVisitReference(_ reference: String) {
        update { $0.visitReference = reference }
    }

    // MARK: - Appointment ID

    /// Sets the cross-system appointment key (``AppointmentV1/appointmentId``).
    func setAppointmentId(_ id: String?) {
        update { $0.appointmentId = id }
    }

    // MARK: - Export state

    func markReadyForExport() {
        update { $0.exportState = .readyForExport }
    }

    func markExported() {
        autosaveTask?.cancel()
        autosaveTask = nil
        draft.exportState = .exported
        draft.touch()
        persistence.save(draft)
        saveState = .saved
    }

    func markExportFailed() {
        update { $0.exportState = .exportFailed }
    }

    // MARK: - Immediate save

    func saveNow() {
        autosaveTask?.cancel()
        autosaveTask = nil
        saveState = .saving
        persistence.save(draft)
        saveState = .saved
    }

    // MARK: - Autosave

    private static let autosaveDebounceNanoseconds: UInt64 = 800_000_000

    private func scheduleAutosave() {
        saveState = .unsaved
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.autosaveDebounceNanoseconds)
            guard let self, !Task.isCancelled else { return }
            self.saveState = .saving
            self.persistence.save(self.draft)
            self.saveState = .saved
        }
    }
}
