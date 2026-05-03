import Foundation

// MARK: - CaptureReviewUpdater
//
// Pure enum that applies review-status mutations to a CaptureSessionDraft.
//
// Design:
//   • No stored state — all functions are pure and return via inout parameter.
//   • Works on IDs; ignores unknown IDs silently.
//   • Call-sites should then use SessionCaptureV2Builder to rebuild the canonical
//     payload after any mutation.
//
// Default rules (applied when adding evidence, not by this type):
//   • Manual items default to .confirmed.
//   • LiDAR/inferred items default to .pending.
//   • Rejected items remain stored for audit; never count toward readiness.

enum CaptureReviewUpdater {

    // MARK: - Single-item mutations

    /// Marks a single evidence item as confirmed.
    static func confirmEvidence(id: UUID, in draft: inout CaptureSessionDraft) {
        updateReviewStatus(id: id, status: .confirmed, in: &draft)
    }

    /// Marks a single evidence item as rejected.
    ///
    /// Rejected items remain stored in the draft for audit purposes but are
    /// excluded from readiness derivation.
    static func rejectEvidence(id: UUID, in draft: inout CaptureSessionDraft) {
        updateReviewStatus(id: id, status: .rejected, in: &draft)
    }

    /// Marks a single evidence item as pending (awaiting review).
    static func markPending(id: UUID, in draft: inout CaptureSessionDraft) {
        updateReviewStatus(id: id, status: .pending, in: &draft)
    }

    // MARK: - Bulk mutations

    /// Confirms every evidence item that was created manually (non-LiDAR).
    ///
    /// Covers:
    ///   - Room scans with `captureSource == .manual`
    ///   - Object pins with `pinSource == .manual` or `pinSource == nil`
    ///   - Photos (always manual)
    ///   - Voice notes (always manual)
    ///   - Floor plan snapshots (always manual)
    static func confirmAllManualEvidence(in draft: inout CaptureSessionDraft) {
        for i in draft.roomScans.indices where draft.roomScans[i].captureSource == .manual {
            draft.roomScans[i].reviewStatus = .confirmed
        }
        for i in draft.objectPins.indices {
            let isManual = draft.objectPins[i].pinSource == .manual
                || draft.objectPins[i].pinSource == nil
            if isManual {
                draft.objectPins[i].reviewStatus = .confirmed
            }
        }
        for i in draft.photos.indices {
            draft.photos[i].reviewStatus = .confirmed
        }
        for i in draft.voiceNotes.indices {
            draft.voiceNotes[i].reviewStatus = .confirmed
        }
        for i in draft.floorPlanSnapshots.indices {
            draft.floorPlanSnapshots[i].reviewStatus = .confirmed
        }
        for i in draft.fabricRecords.indices {
            for j in draft.fabricRecords[i].boundaries.indices {
                draft.fabricRecords[i].boundaries[j].reviewStatus = .confirmed
            }
            for j in draft.fabricRecords[i].openings.indices {
                draft.fabricRecords[i].openings[j].reviewStatus = .confirmed
            }
        }
        for i in draft.hazardObservations.indices {
            draft.hazardObservations[i].reviewStatus = .confirmed
        }
        for i in draft.quotePlannerAnchors.indices {
            draft.quotePlannerAnchors[i].reviewStatus = .confirmed
        }
        for i in draft.candidateRoutes.indices {
            draft.candidateRoutes[i].reviewStatus = .confirmed
        }
        draft.touch()
    }

    /// Rejects all object pins matching the given type.
    ///
    /// Useful for bulk-rejecting a category of LiDAR-inferred pins the engineer
    /// has decided are incorrect, while keeping other types intact.
    static func rejectEvidenceByType(
        _ pinType: ObjectPinType,
        in draft: inout CaptureSessionDraft
    ) {
        for i in draft.objectPins.indices where draft.objectPins[i].type == pinType {
            draft.objectPins[i].reviewStatus = .rejected
        }
        draft.touch()
    }

    // MARK: - Generic status update

    /// Applies `status` to the evidence item identified by `id`, searching all categories.
    ///
    /// Searches room scans, photos, voice notes, object pins, floor plan snapshots,
    /// fabric records, hazard observations, quote-planner anchors, and candidate routes.
    /// If the ID is not found in any category the call is a no-op.
    static func updateReviewStatus(
        id: UUID,
        status: EvidenceReviewStatus,
        in draft: inout CaptureSessionDraft
    ) {
        var changed = false

        if let idx = draft.roomScans.firstIndex(where: { $0.id == id }) {
            draft.roomScans[idx].reviewStatus = status
            changed = true
        }
        if let idx = draft.photos.firstIndex(where: { $0.id == id }) {
            draft.photos[idx].reviewStatus = status
            changed = true
        }
        if let idx = draft.voiceNotes.firstIndex(where: { $0.id == id }) {
            draft.voiceNotes[idx].reviewStatus = status
            changed = true
        }
        if let idx = draft.objectPins.firstIndex(where: { $0.id == id }) {
            draft.objectPins[idx].reviewStatus = status
            changed = true
        }
        if let idx = draft.floorPlanSnapshots.firstIndex(where: { $0.id == id }) {
            draft.floorPlanSnapshots[idx].reviewStatus = status
            changed = true
        }

        // Search fabric boundaries and openings.
        for i in draft.fabricRecords.indices {
            if let j = draft.fabricRecords[i].boundaries.firstIndex(where: { $0.id == id }) {
                draft.fabricRecords[i].boundaries[j].reviewStatus = status
                changed = true
            }
            if let j = draft.fabricRecords[i].openings.firstIndex(where: { $0.id == id }) {
                draft.fabricRecords[i].openings[j].reviewStatus = status
                changed = true
            }
        }

        if let idx = draft.hazardObservations.firstIndex(where: { $0.id == id }) {
            draft.hazardObservations[idx].reviewStatus = status
            changed = true
        }

        if let idx = draft.quotePlannerAnchors.firstIndex(where: { $0.id == id }) {
            draft.quotePlannerAnchors[idx].reviewStatus = status
            changed = true
        }

        if let idx = draft.candidateRoutes.firstIndex(where: { $0.id == id }) {
            draft.candidateRoutes[idx].reviewStatus = status
            changed = true
        }

        if changed {
            draft.touch()
        }
    }
}
