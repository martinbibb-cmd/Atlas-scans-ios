import XCTest
@testable import AtlasScan

// MARK: - CaptureReviewUpdaterTests
//
// Unit tests for CaptureReviewUpdater.
//
// Covers:
//   - confirmEvidence updates the correct item in every category
//   - rejectEvidence updates the correct item
//   - markPending updates the correct item
//   - updateReviewStatus with unknown ID is a no-op
//   - confirmAllManualEvidence confirms manual items, leaves LiDAR unchanged
//   - rejectEvidenceByType rejects matching pin types only
//   - review action updates draft (touch()) timestamp

final class CaptureReviewUpdaterTests: XCTestCase {

    // MARK: - Helpers

    private func makeDraft() -> CaptureSessionDraft {
        CaptureSessionStore.newSession(visitReference: "REVIEW-TEST")
    }

    // MARK: - confirmEvidence

    func test_confirm_roomScan_updatesReviewStatus() {
        var draft = makeDraft()
        var room = CapturedRoomScanDraft()
        room.reviewStatus = .pending
        draft.roomScans.append(room)

        CaptureReviewUpdater.confirmEvidence(id: room.id, in: &draft)

        XCTAssertEqual(draft.roomScans.first?.reviewStatus, .confirmed)
    }

    func test_confirm_photo_updatesReviewStatus() {
        var draft = makeDraft()
        var photo = CapturedPhotoDraft(localFilename: "test.jpg")
        photo.reviewStatus = .pending
        draft.photos.append(photo)

        CaptureReviewUpdater.confirmEvidence(id: photo.id, in: &draft)

        XCTAssertEqual(draft.photos.first?.reviewStatus, .confirmed)
    }

    func test_confirm_voiceNote_updatesReviewStatus() {
        var draft = makeDraft()
        var note = CapturedVoiceNoteDraft()
        note.reviewStatus = .pending
        draft.voiceNotes.append(note)

        CaptureReviewUpdater.confirmEvidence(id: note.id, in: &draft)

        XCTAssertEqual(draft.voiceNotes.first?.reviewStatus, .confirmed)
    }

    func test_confirm_objectPin_updatesReviewStatus() {
        var draft = makeDraft()
        var pin = CapturedObjectPinDraft(type: .boiler)
        pin.reviewStatus = .pending
        draft.objectPins.append(pin)

        CaptureReviewUpdater.confirmEvidence(id: pin.id, in: &draft)

        XCTAssertEqual(draft.objectPins.first?.reviewStatus, .confirmed)
    }

    func test_confirm_floorPlanSnapshot_updatesReviewStatus() {
        var draft = makeDraft()
        var snapshot = CapturedFloorPlanSnapshotDraft(imageRef: "fp.png")
        snapshot.reviewStatus = .pending
        draft.floorPlanSnapshots.append(snapshot)

        CaptureReviewUpdater.confirmEvidence(id: snapshot.id, in: &draft)

        XCTAssertEqual(draft.floorPlanSnapshots.first?.reviewStatus, .confirmed)
    }

    // MARK: - rejectEvidence

    func test_reject_objectPin_updatesReviewStatus() {
        var draft = makeDraft()
        var pin = CapturedObjectPinDraft(type: .radiator)
        pin.reviewStatus = .pending
        draft.objectPins.append(pin)

        CaptureReviewUpdater.rejectEvidence(id: pin.id, in: &draft)

        XCTAssertEqual(draft.objectPins.first?.reviewStatus, .rejected)
    }

    func test_reject_photo_updatesReviewStatus() {
        var draft = makeDraft()
        var photo = CapturedPhotoDraft(localFilename: "flue.jpg")
        photo.reviewStatus = .confirmed
        draft.photos.append(photo)

        CaptureReviewUpdater.rejectEvidence(id: photo.id, in: &draft)

        XCTAssertEqual(draft.photos.first?.reviewStatus, .rejected)
    }

    // MARK: - markPending

    func test_markPending_confirmedItem_setsPending() {
        var draft = makeDraft()
        var pin = CapturedObjectPinDraft(type: .boiler)
        pin.reviewStatus = .confirmed
        draft.objectPins.append(pin)

        CaptureReviewUpdater.markPending(id: pin.id, in: &draft)

        XCTAssertEqual(draft.objectPins.first?.reviewStatus, .pending)
    }

    // MARK: - Unknown ID is a no-op

    func test_updateReviewStatus_unknownId_isNoOp() {
        var draft = makeDraft()
        var pin = CapturedObjectPinDraft(type: .boiler)
        pin.reviewStatus = .confirmed
        draft.objectPins.append(pin)

        let unknownId = UUID()
        CaptureReviewUpdater.updateReviewStatus(id: unknownId, status: .rejected, in: &draft)

        XCTAssertEqual(draft.objectPins.first?.reviewStatus, .confirmed)
    }

    // MARK: - confirmAllManualEvidence

    func test_confirmAllManual_confirmsManualRoom() {
        var draft = makeDraft()
        var room = CapturedRoomScanDraft()
        room.captureSource = .manual
        room.reviewStatus = .pending
        draft.roomScans.append(room)

        CaptureReviewUpdater.confirmAllManualEvidence(in: &draft)

        XCTAssertEqual(draft.roomScans.first?.reviewStatus, .confirmed)
    }

    func test_confirmAllManual_doesNotConfirmLiDARRoom() {
        var draft = makeDraft()
        var room = CapturedRoomScanDraft()
        room.captureSource = .lidar
        room.reviewStatus = .pending
        draft.roomScans.append(room)

        CaptureReviewUpdater.confirmAllManualEvidence(in: &draft)

        XCTAssertEqual(draft.roomScans.first?.reviewStatus, .pending)
    }

    func test_confirmAllManual_confirmsManualPin() {
        var draft = makeDraft()
        var pin = CapturedObjectPinDraft(type: .boiler)
        pin.pinSource = .manual
        pin.reviewStatus = .pending
        draft.objectPins.append(pin)

        CaptureReviewUpdater.confirmAllManualEvidence(in: &draft)

        XCTAssertEqual(draft.objectPins.first?.reviewStatus, .confirmed)
    }

    func test_confirmAllManual_confirmsPinWithNilSource() {
        var draft = makeDraft()
        var pin = CapturedObjectPinDraft(type: .cylinder)
        pin.pinSource = nil
        pin.reviewStatus = .pending
        draft.objectPins.append(pin)

        CaptureReviewUpdater.confirmAllManualEvidence(in: &draft)

        XCTAssertEqual(draft.objectPins.first?.reviewStatus, .confirmed)
    }

    func test_confirmAllManual_doesNotConfirmLiDARPin() {
        var draft = makeDraft()
        var pin = CapturedObjectPinDraft(type: .radiator)
        pin.pinSource = .lidar
        pin.reviewStatus = .pending
        draft.objectPins.append(pin)

        CaptureReviewUpdater.confirmAllManualEvidence(in: &draft)

        XCTAssertEqual(draft.objectPins.first?.reviewStatus, .pending)
    }

    func test_confirmAllManual_confirmsAllPhotos() {
        var draft = makeDraft()
        var photo = CapturedPhotoDraft(localFilename: "overview.jpg")
        photo.reviewStatus = .pending
        draft.photos.append(photo)

        CaptureReviewUpdater.confirmAllManualEvidence(in: &draft)

        XCTAssertEqual(draft.photos.first?.reviewStatus, .confirmed)
    }

    func test_confirmAllManual_confirmsAllVoiceNotes() {
        var draft = makeDraft()
        var note = CapturedVoiceNoteDraft()
        note.reviewStatus = .pending
        draft.voiceNotes.append(note)

        CaptureReviewUpdater.confirmAllManualEvidence(in: &draft)

        XCTAssertEqual(draft.voiceNotes.first?.reviewStatus, .confirmed)
    }

    // MARK: - rejectEvidenceByType

    func test_rejectEvidenceByType_rejectsMatchingPins() {
        var draft = makeDraft()
        var boiler = CapturedObjectPinDraft(type: .boiler)
        boiler.reviewStatus = .pending
        var radiator = CapturedObjectPinDraft(type: .radiator)
        radiator.reviewStatus = .pending
        draft.objectPins.append(boiler)
        draft.objectPins.append(radiator)

        CaptureReviewUpdater.rejectEvidenceByType(.boiler, in: &draft)

        XCTAssertEqual(draft.objectPins.first(where: { $0.id == boiler.id })?.reviewStatus, .rejected)
        XCTAssertEqual(draft.objectPins.first(where: { $0.id == radiator.id })?.reviewStatus, .pending)
    }

    // MARK: - touch() is called on mutation

    func test_updateReviewStatus_knownId_touchesUpdatedAt() {
        var draft = makeDraft()
        var pin = CapturedObjectPinDraft(type: .boiler)
        pin.reviewStatus = .pending
        draft.objectPins.append(pin)
        let before = draft.updatedAt

        // Small sleep to ensure updatedAt changes
        Thread.sleep(forTimeInterval: 0.01)
        CaptureReviewUpdater.confirmEvidence(id: pin.id, in: &draft)

        XCTAssertGreaterThan(draft.updatedAt, before)
    }

    func test_updateReviewStatus_unknownId_doesNotTouchUpdatedAt() {
        var draft = makeDraft()
        let before = draft.updatedAt

        Thread.sleep(forTimeInterval: 0.01)
        CaptureReviewUpdater.updateReviewStatus(id: UUID(), status: .rejected, in: &draft)

        XCTAssertEqual(draft.updatedAt, before)
    }
}
