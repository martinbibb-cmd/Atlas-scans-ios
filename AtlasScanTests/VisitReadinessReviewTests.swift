import XCTest
import AtlasContracts
@testable import AtlasScan

// MARK: - VisitReadinessReviewTests
//
// Tests for AtlasScanVisit.deriveReadiness(from:) using review-aware logic.
//
// Covers:
//   - Confirmed evidence counts toward readiness
//   - Rejected evidence does not count
//   - Pending evidence does not count
//   - Pending LiDAR boiler does not satisfy hasBoiler
//   - Confirmed manual boiler satisfies hasBoiler
//   - Confirmed flue object satisfies hasFlue
//   - Confirmed flue photo satisfies hasFlue
//   - Confirmed transcript satisfies hasNotes
//   - Object-linked rejected photo remains stored but is excluded from hasPhotos
//   - Confirmed room satisfies hasRooms
//   - Empty draft has all false

final class VisitReadinessReviewTests: XCTestCase {

    // MARK: - Helpers

    private func makeDraft() -> CaptureSessionDraft {
        CaptureSessionStore.newSession(visitReference: "READINESS-TEST")
    }

    private func confirmedPin(_ type: ObjectPinType) -> CapturedObjectPinDraft {
        var pin = CapturedObjectPinDraft(type: type)
        pin.pinSource = .manual
        pin.reviewStatus = .confirmed
        return pin
    }

    private func pendingPin(_ type: ObjectPinType) -> CapturedObjectPinDraft {
        var pin = CapturedObjectPinDraft(type: type)
        pin.pinSource = .lidar
        pin.reviewStatus = .pending
        return pin
    }

    private func rejectedPin(_ type: ObjectPinType) -> CapturedObjectPinDraft {
        var pin = CapturedObjectPinDraft(type: type)
        pin.reviewStatus = .rejected
        return pin
    }

    // MARK: - Empty draft

    func test_emptyDraft_allFlagsFalse() {
        let draft = makeDraft()
        let r = AtlasScanVisit.deriveReadiness(from: draft)
        XCTAssertFalse(r.hasRooms)
        XCTAssertFalse(r.hasPhotos)
        XCTAssertFalse(r.hasHeatingSystem)
        XCTAssertFalse(r.hasHotWaterSystem)
        XCTAssertFalse(r.hasBoiler)
        XCTAssertFalse(r.hasFlue)
        XCTAssertFalse(r.hasNotes)
    }

    // MARK: - hasBoiler

    func test_hasBoiler_confirmedManualBoiler_isTrue() {
        var draft = makeDraft()
        draft.objectPins.append(confirmedPin(.boiler))
        XCTAssertTrue(AtlasScanVisit.deriveReadiness(from: draft).hasBoiler)
    }

    func test_hasBoiler_pendingLiDARBoiler_isFalse() {
        var draft = makeDraft()
        draft.objectPins.append(pendingPin(.boiler))
        XCTAssertFalse(AtlasScanVisit.deriveReadiness(from: draft).hasBoiler)
    }

    func test_hasBoiler_rejectedBoiler_isFalse() {
        var draft = makeDraft()
        draft.objectPins.append(rejectedPin(.boiler))
        XCTAssertFalse(AtlasScanVisit.deriveReadiness(from: draft).hasBoiler)
    }

    func test_hasBoiler_confirmedHeatPump_isTrue() {
        var draft = makeDraft()
        draft.objectPins.append(confirmedPin(.heatPump))
        XCTAssertTrue(AtlasScanVisit.deriveReadiness(from: draft).hasBoiler)
    }

    // MARK: - hasFlue

    func test_hasFlue_confirmedFlueObject_isTrue() {
        var draft = makeDraft()
        draft.objectPins.append(confirmedPin(.flue))
        XCTAssertTrue(AtlasScanVisit.deriveReadiness(from: draft).hasFlue)
    }

    func test_hasFlue_pendingFlueObject_isFalse() {
        var draft = makeDraft()
        draft.objectPins.append(pendingPin(.flue))
        XCTAssertFalse(AtlasScanVisit.deriveReadiness(from: draft).hasFlue)
    }

    func test_hasFlue_confirmedFluePhoto_isTrue() {
        var draft = makeDraft()
        var photo = CapturedPhotoDraft(localFilename: "flue.jpg")
        photo.kind = .flue
        photo.reviewStatus = .confirmed
        draft.photos.append(photo)
        XCTAssertTrue(AtlasScanVisit.deriveReadiness(from: draft).hasFlue)
    }

    func test_hasFlue_rejectedFluePhoto_isFalse() {
        var draft = makeDraft()
        var photo = CapturedPhotoDraft(localFilename: "flue.jpg")
        photo.kind = .flue
        photo.reviewStatus = .rejected
        draft.photos.append(photo)
        XCTAssertFalse(AtlasScanVisit.deriveReadiness(from: draft).hasFlue)
    }

    // MARK: - hasNotes

    func test_hasNotes_confirmedTranscript_isTrue() {
        var draft = makeDraft()
        var note = CapturedVoiceNoteDraft()
        note.transcript = "The boiler is in the kitchen."
        note.reviewStatus = .confirmed
        draft.voiceNotes.append(note)
        XCTAssertTrue(AtlasScanVisit.deriveReadiness(from: draft).hasNotes)
    }

    func test_hasNotes_rejectedTranscript_isFalse() {
        var draft = makeDraft()
        var note = CapturedVoiceNoteDraft()
        note.transcript = "This note was rejected."
        note.reviewStatus = .rejected
        draft.voiceNotes.append(note)
        XCTAssertFalse(AtlasScanVisit.deriveReadiness(from: draft).hasNotes)
    }

    func test_hasNotes_pendingTranscript_isFalse() {
        var draft = makeDraft()
        var note = CapturedVoiceNoteDraft()
        note.transcript = "Pending review."
        note.reviewStatus = .pending
        draft.voiceNotes.append(note)
        XCTAssertFalse(AtlasScanVisit.deriveReadiness(from: draft).hasNotes)
    }

    // MARK: - hasPhotos

    func test_hasPhotos_confirmedPhoto_isTrue() {
        var draft = makeDraft()
        var photo = CapturedPhotoDraft(localFilename: "overview.jpg")
        photo.reviewStatus = .confirmed
        draft.photos.append(photo)
        XCTAssertTrue(AtlasScanVisit.deriveReadiness(from: draft).hasPhotos)
    }

    func test_hasPhotos_rejectedObjectLinkedPhoto_isFalse() {
        var draft = makeDraft()
        var photo = CapturedPhotoDraft(localFilename: "boiler-linked.jpg")
        photo.linkedObjectId = UUID()
        photo.reviewStatus = .rejected
        draft.photos.append(photo)
        // Rejected photo must NOT count — even with a linked object
        XCTAssertFalse(AtlasScanVisit.deriveReadiness(from: draft).hasPhotos)
    }

    func test_hasPhotos_pendingPhoto_isFalse() {
        var draft = makeDraft()
        var photo = CapturedPhotoDraft(localFilename: "overview.jpg")
        photo.reviewStatus = .pending
        draft.photos.append(photo)
        XCTAssertFalse(AtlasScanVisit.deriveReadiness(from: draft).hasPhotos)
    }

    // MARK: - hasRooms

    func test_hasRooms_confirmedRoom_isTrue() {
        var draft = makeDraft()
        var room = CapturedRoomScanDraft()
        room.reviewStatus = .confirmed
        draft.roomScans.append(room)
        XCTAssertTrue(AtlasScanVisit.deriveReadiness(from: draft).hasRooms)
    }

    func test_hasRooms_rejectedRoom_isFalse() {
        var draft = makeDraft()
        var room = CapturedRoomScanDraft()
        room.reviewStatus = .rejected
        draft.roomScans.append(room)
        XCTAssertFalse(AtlasScanVisit.deriveReadiness(from: draft).hasRooms)
    }

    func test_hasRooms_pendingRoom_isFalse() {
        var draft = makeDraft()
        var room = CapturedRoomScanDraft()
        room.reviewStatus = .pending
        draft.roomScans.append(room)
        XCTAssertFalse(AtlasScanVisit.deriveReadiness(from: draft).hasRooms)
    }

    // MARK: - hasHeatingSystem

    func test_hasHeatingSystem_confirmedBoiler_isTrue() {
        var draft = makeDraft()
        draft.objectPins.append(confirmedPin(.boiler))
        XCTAssertTrue(AtlasScanVisit.deriveReadiness(from: draft).hasHeatingSystem)
    }

    func test_hasHeatingSystem_confirmedRadiator_isTrue() {
        var draft = makeDraft()
        draft.objectPins.append(confirmedPin(.radiator))
        XCTAssertTrue(AtlasScanVisit.deriveReadiness(from: draft).hasHeatingSystem)
    }

    func test_hasHeatingSystem_pendingBoiler_isFalse() {
        var draft = makeDraft()
        draft.objectPins.append(pendingPin(.boiler))
        XCTAssertFalse(AtlasScanVisit.deriveReadiness(from: draft).hasHeatingSystem)
    }

    // MARK: - hasHotWaterSystem

    func test_hasHotWaterSystem_confirmedCylinder_isTrue() {
        var draft = makeDraft()
        draft.objectPins.append(confirmedPin(.cylinder))
        XCTAssertTrue(AtlasScanVisit.deriveReadiness(from: draft).hasHotWaterSystem)
    }

    func test_hasHotWaterSystem_confirmedBoiler_isTrue() {
        // Confirmed boiler implicitly satisfies hot water (combi system)
        var draft = makeDraft()
        draft.objectPins.append(confirmedPin(.boiler))
        XCTAssertTrue(AtlasScanVisit.deriveReadiness(from: draft).hasHotWaterSystem)
    }

    func test_hasHotWaterSystem_pendingCylinder_isFalse() {
        var draft = makeDraft()
        draft.objectPins.append(pendingPin(.cylinder))
        XCTAssertFalse(AtlasScanVisit.deriveReadiness(from: draft).hasHotWaterSystem)
    }

    // MARK: - Rejected evidence stays stored but excluded

    func test_rejectedEvidence_remainsInDraft() {
        var draft = makeDraft()
        draft.objectPins.append(rejectedPin(.boiler))

        let r = AtlasScanVisit.deriveReadiness(from: draft)

        // Rejected item is still in the draft
        XCTAssertEqual(draft.objectPins.count, 1)
        XCTAssertEqual(draft.objectPins.first?.reviewStatus, .rejected)
        // But does not satisfy readiness
        XCTAssertFalse(r.hasBoiler)
    }

    // MARK: - Review action updates SessionCaptureV2 via builder

    func test_reviewAction_updatesReadinessWhenRebuildingCapture() {
        var draft = makeDraft()
        var pin = CapturedObjectPinDraft(type: .boiler)
        pin.reviewStatus = .pending
        draft.objectPins.append(pin)

        // Before confirming: readiness should not have hasBoiler
        let before = AtlasScanVisit.deriveReadiness(from: draft)
        XCTAssertFalse(before.hasBoiler)

        // After confirming:
        CaptureReviewUpdater.confirmEvidence(id: pin.id, in: &draft)
        let after = AtlasScanVisit.deriveReadiness(from: draft)
        XCTAssertTrue(after.hasBoiler)
    }
}
