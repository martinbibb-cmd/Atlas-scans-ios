import XCTest
import AtlasContracts
@testable import AtlasScan

// MARK: - AtlasScanVisitStoreTests
//
// Unit tests for AtlasScanVisitStore.
//
// Covers:
//   - createVisit: creates an active visit and persists it
//   - loadActiveVisit: returns the current active visit
//   - saveActiveVisit: persists changes
//   - clearActiveVisit: removes the active visit
//   - updateStatus: transitions status correctly
//   - updateReadiness: updates readiness flags
//   - Readiness defaults: all false on a fresh visit
//   - Status transitions: capturing → readyToComplete → complete
//   - createVisit also persists a CaptureSessionDraft

@MainActor
final class AtlasScanVisitStoreTests: XCTestCase {

    // MARK: - Fixtures

    private var store: AtlasScanVisitStore!

    override func setUp() async throws {
        try await super.setUp()
        store = AtlasScanVisitStore.makeTestInstance()
    }

    override func tearDown() async throws {
        store = nil
        try await super.tearDown()
    }

    // MARK: - createVisit

    func test_createVisit_setsActiveVisit() {
        let visit = store.createVisit(visitNumber: "JOB-001", brandId: nil)
        XCTAssertNotNil(store.activeVisit)
        XCTAssertEqual(store.activeVisit?.id, visit.id)
    }

    func test_createVisit_preservesVisitNumber() {
        store.createVisit(visitNumber: "JOB-VISIT-NUMBER", brandId: nil)
        XCTAssertEqual(store.activeVisit?.visitNumber, "JOB-VISIT-NUMBER")
    }

    func test_createVisit_preservesBrandId() {
        store.createVisit(visitNumber: "JOB-002", brandId: "BRAND-XYZ")
        XCTAssertEqual(store.activeVisit?.brandId, "BRAND-XYZ")
    }

    func test_createVisit_initialStatusIsCapturing() {
        store.createVisit(visitNumber: "JOB-003", brandId: nil)
        XCTAssertEqual(store.activeVisit?.status, .capturing)
    }

    func test_createVisit_linksCaptureSessionId() {
        store.createVisit(visitNumber: "JOB-LINK", brandId: nil)
        XCTAssertNotNil(store.activeVisit?.captureSessionId)
    }

    func test_createVisit_nilVisitNumber() {
        store.createVisit(visitNumber: nil, brandId: nil)
        XCTAssertNil(store.activeVisit?.visitNumber)
    }

    // MARK: - Readiness defaults

    func test_readiness_defaultAllFalse() {
        store.createVisit(visitNumber: "JOB-READINESS", brandId: nil)
        let readiness = store.activeVisit?.readiness
        XCTAssertEqual(readiness?.hasRooms,          false)
        XCTAssertEqual(readiness?.hasPhotos,         false)
        XCTAssertEqual(readiness?.hasHeatingSystem,  false)
        XCTAssertEqual(readiness?.hasHotWaterSystem, false)
        XCTAssertEqual(readiness?.hasBoiler,         false)
        XCTAssertEqual(readiness?.hasFlue,           false)
        XCTAssertEqual(readiness?.hasNotes,          false)
    }

    // MARK: - loadActiveVisit

    func test_loadActiveVisit_returnsNilWhenNone() {
        XCTAssertNil(store.loadActiveVisit())
    }

    func test_loadActiveVisit_returnsActiveVisitAfterCreate() {
        store.createVisit(visitNumber: "JOB-LOAD", brandId: nil)
        XCTAssertNotNil(store.loadActiveVisit())
    }

    // MARK: - saveActiveVisit

    func test_saveActiveVisit_updatesActiveVisit() {
        store.createVisit(visitNumber: "JOB-SAVE", brandId: nil)
        var visit = store.activeVisit!
        visit.visitNumber = "JOB-SAVE-UPDATED"
        store.saveActiveVisit(visit)
        XCTAssertEqual(store.activeVisit?.visitNumber, "JOB-SAVE-UPDATED")
    }

    func test_saveActiveVisit_updatesTimestamp() {
        store.createVisit(visitNumber: "JOB-TIMESTAMP", brandId: nil)
        let original = store.activeVisit!.updatedAt
        var visit = store.activeVisit!
        visit.visitNumber = "JOB-TIMESTAMP-UPDATED"
        store.saveActiveVisit(visit)
        XCTAssertGreaterThanOrEqual(store.activeVisit!.updatedAt, original)
    }

    // MARK: - clearActiveVisit

    func test_clearActiveVisit_removesActiveVisit() {
        store.createVisit(visitNumber: "JOB-CLEAR", brandId: nil)
        store.clearActiveVisit()
        XCTAssertNil(store.activeVisit)
    }

    func test_clearActiveVisit_loadReturnsNil() {
        store.createVisit(visitNumber: "JOB-CLEAR-LOAD", brandId: nil)
        store.clearActiveVisit()
        XCTAssertNil(store.loadActiveVisit())
    }

    // MARK: - updateStatus (status transitions)

    func test_updateStatus_capturingToReadyToComplete() {
        store.createVisit(visitNumber: "JOB-STATUS-1", brandId: nil)
        XCTAssertEqual(store.activeVisit?.status, .capturing)
        store.updateStatus(.readyToComplete)
        XCTAssertEqual(store.activeVisit?.status, .readyToComplete)
    }

    func test_updateStatus_readyToCompleteToComplete() {
        store.createVisit(visitNumber: "JOB-STATUS-2", brandId: nil)
        store.updateStatus(.readyToComplete)
        store.updateStatus(.complete)
        XCTAssertEqual(store.activeVisit?.status, .complete)
    }

    func test_updateStatus_completeSetsCompletedAt() {
        store.createVisit(visitNumber: "JOB-COMPLETED-AT", brandId: nil)
        XCTAssertNil(store.activeVisit?.completedAt)
        store.updateStatus(.complete)
        XCTAssertNotNil(store.activeVisit?.completedAt)
    }

    func test_updateStatus_capturingToCompleteFullTransition() {
        store.createVisit(visitNumber: "JOB-FULL-TRANSITION", brandId: nil)
        store.updateStatus(.readyToComplete)
        store.updateStatus(.complete)
        XCTAssertEqual(store.activeVisit?.status, .complete)
        XCTAssertNotNil(store.activeVisit?.completedAt)
    }

    func test_updateStatus_noopWhenNoActiveVisit() {
        // Should not crash
        store.updateStatus(.complete)
        XCTAssertNil(store.activeVisit)
    }

    // MARK: - updateReadiness

    func test_updateReadiness_updatesFlags() {
        store.createVisit(visitNumber: "JOB-READINESS-UPDATE", brandId: nil)
        let readiness = VisitReadinessV1(
            hasRooms: true,
            hasPhotos: true,
            hasHeatingSystem: true,
            hasHotWaterSystem: true,
            hasBoiler: true,
            hasFlue: true,
            hasNotes: true
        )
        store.updateReadiness(readiness)
        XCTAssertEqual(store.activeVisit?.readiness.hasRooms, true)
        XCTAssertEqual(store.activeVisit?.readiness.hasBoiler, true)
        XCTAssertEqual(store.activeVisit?.readiness.hasFlue, true)
    }

    func test_updateReadiness_noopWhenNoActiveVisit() {
        // Should not crash
        let readiness = VisitReadinessV1(
            hasRooms: true, hasPhotos: false, hasHeatingSystem: false,
            hasHotWaterSystem: false, hasBoiler: false, hasFlue: false, hasNotes: false
        )
        store.updateReadiness(readiness)
        XCTAssertNil(store.activeVisit)
    }

    // MARK: - deriveReadiness (from CaptureSessionDraft)

    func test_deriveReadiness_emptyDraftAllFalse() {
        let draft = CaptureSessionStore.newSession(visitReference: "TEST")
        let readiness = AtlasScanVisit.deriveReadiness(from: draft)
        XCTAssertFalse(readiness.hasRooms)
        XCTAssertFalse(readiness.hasPhotos)
        XCTAssertFalse(readiness.hasHeatingSystem)
        XCTAssertFalse(readiness.hasHotWaterSystem)
        XCTAssertFalse(readiness.hasBoiler)
        XCTAssertFalse(readiness.hasFlue)
        XCTAssertFalse(readiness.hasNotes)
    }

    func test_deriveReadiness_withRoomsAndPhotos() {
        var draft = CaptureSessionStore.newSession(visitReference: "TEST")
        draft.roomScans.append(CapturedRoomScanDraft(roomLabel: "Kitchen"))
        draft.photos.append(CapturedPhotoDraft(localFilename: "photo.jpg"))
        let readiness = AtlasScanVisit.deriveReadiness(from: draft)
        XCTAssertTrue(readiness.hasRooms)
        XCTAssertTrue(readiness.hasPhotos)
    }

    func test_deriveReadiness_boilerPin() {
        var draft = CaptureSessionStore.newSession(visitReference: "TEST")
        draft.objectPins.append(CapturedObjectPinDraft(type: .boiler))
        let readiness = AtlasScanVisit.deriveReadiness(from: draft)
        XCTAssertTrue(readiness.hasBoiler)
        XCTAssertTrue(readiness.hasHeatingSystem)
    }

    func test_deriveReadiness_heatPumpCountsAsBoiler() {
        var draft = CaptureSessionStore.newSession(visitReference: "TEST")
        draft.objectPins.append(CapturedObjectPinDraft(type: .heatPump))
        let readiness = AtlasScanVisit.deriveReadiness(from: draft)
        XCTAssertTrue(readiness.hasBoiler)
    }

    func test_deriveReadiness_fluePin() {
        var draft = CaptureSessionStore.newSession(visitReference: "TEST")
        draft.objectPins.append(CapturedObjectPinDraft(type: .flue))
        let readiness = AtlasScanVisit.deriveReadiness(from: draft)
        XCTAssertTrue(readiness.hasFlue)
    }

    func test_deriveReadiness_cylinderCountsAsHotWater() {
        var draft = CaptureSessionStore.newSession(visitReference: "TEST")
        draft.objectPins.append(CapturedObjectPinDraft(type: .cylinder))
        let readiness = AtlasScanVisit.deriveReadiness(from: draft)
        XCTAssertTrue(readiness.hasHotWaterSystem)
    }

    func test_deriveReadiness_voiceNotes() {
        var draft = CaptureSessionStore.newSession(visitReference: "TEST")
        var note = CapturedVoiceNoteDraft()
        note.transcript = "Note text"
        draft.voiceNotes.append(note)
        let readiness = AtlasScanVisit.deriveReadiness(from: draft)
        XCTAssertTrue(readiness.hasNotes)
    }

    // MARK: - visitId

    func test_visitId_matchesUUIDString() {
        store.createVisit(visitNumber: "JOB-ID", brandId: nil)
        let visit = store.activeVisit!
        XCTAssertEqual(visit.visitId, visit.id.uuidString)
    }
}
