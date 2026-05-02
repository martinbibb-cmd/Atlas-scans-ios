import XCTest
import AtlasContracts
@testable import AtlasScan

// MARK: - SessionCaptureV2StoreTests
//
// Tests for SessionCaptureV2Store — persistence to
//   Documents/captures/{visitId}/session_capture_v2.json
//
// Covers:
//   - Save then load round-trips correctly
//   - Load returns nil when no capture saved
//   - Clear removes the persisted file
//   - Multiple visits are stored independently

final class SessionCaptureV2StoreTests: XCTestCase {

    // MARK: - Fixtures

    private var store: SessionCaptureV2Store!

    override func setUp() {
        super.setUp()
        store = SessionCaptureV2Store.makeTestInstance()
    }

    override func tearDown() {
        store = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeCapture(visitId: String = UUID().uuidString) -> SessionCaptureV2 {
        SessionCaptureV2(
            schemaVersion: currentSessionCaptureVersion,
            sessionId: visitId,
            visitReference: "JOB-STORE-TEST",
            appointmentId: nil,
            propertyAddress: nil,
            customerName: nil,
            capturedAt: "2025-01-01T10:00:00.000Z",
            exportedAt: "2025-01-01T11:00:00.000Z",
            deviceModel: "iPhone 15 Pro",
            roomScans: [],
            photos: [],
            voiceNotes: [],
            objectPins: [],
            floorPlanSnapshots: [],
            qaFlags: []
        )
    }

    // MARK: - Round-trip

    func test_saveAndLoad_roundTripsCorrectly() {
        let visitId = UUID().uuidString
        let capture = makeCapture(visitId: visitId)
        store.saveCapture(capture, for: visitId)
        let loaded = store.loadCapture(for: visitId)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.sessionId, visitId)
        XCTAssertEqual(loaded?.visitReference, "JOB-STORE-TEST")
    }

    func test_saveAndLoad_schemaVersionPreserved() {
        let visitId = UUID().uuidString
        let capture = makeCapture(visitId: visitId)
        store.saveCapture(capture, for: visitId)
        XCTAssertEqual(store.loadCapture(for: visitId)?.schemaVersion, currentSessionCaptureVersion)
    }

    func test_saveAndLoad_artefactsRoundTrip() {
        let visitId = UUID().uuidString
        let pin = CapturedObjectPinV2(
            id: UUID().uuidString,
            type: "boiler",
            label: "Main boiler",
            roomId: nil,
            linkedPhotoId: nil,
            approximatePositionRef: nil
        )
        let capture = SessionCaptureV2(
            schemaVersion: currentSessionCaptureVersion,
            sessionId: visitId,
            visitReference: "JOB-ARTEFACT",
            appointmentId: nil,
            propertyAddress: nil,
            customerName: nil,
            capturedAt: "2025-01-01T10:00:00.000Z",
            exportedAt: "2025-01-01T11:00:00.000Z",
            deviceModel: "iPhone 15 Pro",
            roomScans: [],
            photos: [],
            voiceNotes: [],
            objectPins: [pin],
            floorPlanSnapshots: [],
            qaFlags: []
        )
        store.saveCapture(capture, for: visitId)
        let loaded = store.loadCapture(for: visitId)
        XCTAssertEqual(loaded?.objectPins.count, 1)
        XCTAssertEqual(loaded?.objectPins.first?.type, "boiler")
        XCTAssertEqual(loaded?.objectPins.first?.label, "Main boiler")
    }

    // MARK: - Load returns nil when not saved

    func test_load_returnsNil_whenNoCaptureSaved() {
        let visitId = UUID().uuidString
        XCTAssertNil(store.loadCapture(for: visitId))
    }

    func test_load_returnsNil_afterClear() {
        let visitId = UUID().uuidString
        let capture = makeCapture(visitId: visitId)
        store.saveCapture(capture, for: visitId)
        XCTAssertNotNil(store.loadCapture(for: visitId))
        store.clearCapture(for: visitId)
        XCTAssertNil(store.loadCapture(for: visitId))
    }

    // MARK: - Clear

    func test_clear_removesCapture() {
        let visitId = UUID().uuidString
        store.saveCapture(makeCapture(visitId: visitId), for: visitId)
        store.clearCapture(for: visitId)
        XCTAssertNil(store.loadCapture(for: visitId))
    }

    func test_clear_noopWhenNoCaptureSaved() {
        // Should not crash
        let visitId = UUID().uuidString
        store.clearCapture(for: visitId)
        XCTAssertNil(store.loadCapture(for: visitId))
    }

    // MARK: - Multiple visits are independent

    func test_multipleVisits_storedIndependently() {
        let visitId1 = UUID().uuidString
        let visitId2 = UUID().uuidString
        let capture1 = makeCapture(visitId: visitId1)
        var capture2 = makeCapture(visitId: visitId2)
        // Mutate capture2 to be distinguishable
        capture2 = SessionCaptureV2(
            schemaVersion: currentSessionCaptureVersion,
            sessionId: visitId2,
            visitReference: "JOB-VISIT-2",
            appointmentId: nil,
            propertyAddress: nil,
            customerName: nil,
            capturedAt: "2025-02-01T10:00:00.000Z",
            exportedAt: "2025-02-01T11:00:00.000Z",
            deviceModel: "iPhone 15 Pro",
            roomScans: [],
            photos: [],
            voiceNotes: [],
            objectPins: [],
            floorPlanSnapshots: [],
            qaFlags: []
        )
        store.saveCapture(capture1, for: visitId1)
        store.saveCapture(capture2, for: visitId2)

        XCTAssertEqual(store.loadCapture(for: visitId1)?.sessionId, visitId1)
        XCTAssertEqual(store.loadCapture(for: visitId2)?.visitReference, "JOB-VISIT-2")
    }

    func test_clearOneVisit_doesNotAffectOther() {
        let visitId1 = UUID().uuidString
        let visitId2 = UUID().uuidString
        store.saveCapture(makeCapture(visitId: visitId1), for: visitId1)
        store.saveCapture(makeCapture(visitId: visitId2), for: visitId2)

        store.clearCapture(for: visitId1)

        XCTAssertNil(store.loadCapture(for: visitId1))
        XCTAssertNotNil(store.loadCapture(for: visitId2))
    }

    // MARK: - Overwrite on second save

    func test_save_overwritesExistingCapture() {
        let visitId = UUID().uuidString
        store.saveCapture(makeCapture(visitId: visitId), for: visitId)

        let updated = SessionCaptureV2(
            schemaVersion: currentSessionCaptureVersion,
            sessionId: visitId,
            visitReference: "JOB-UPDATED",
            appointmentId: nil,
            propertyAddress: nil,
            customerName: nil,
            capturedAt: "2025-01-01T10:00:00.000Z",
            exportedAt: "2025-01-01T12:00:00.000Z",
            deviceModel: "iPhone 15 Pro",
            roomScans: [],
            photos: [],
            voiceNotes: [],
            objectPins: [],
            floorPlanSnapshots: [],
            qaFlags: []
        )
        store.saveCapture(updated, for: visitId)

        XCTAssertEqual(store.loadCapture(for: visitId)?.visitReference, "JOB-UPDATED")
    }

    // MARK: - Builder integration: save a builder-produced capture

    func test_builderProducedCapture_savesAndLoadsCorrectly() {
        let visit = AtlasScanVisit(visitNumber: "JOB-INTEGRATION", brandId: "BRAND-TEST")
        var draft = CaptureSessionStore.newSession(visitReference: "JOB-INTEGRATION")
        draft.objectPins.append(CapturedObjectPinDraft(type: .boiler))
        draft.photos.append(CapturedPhotoDraft(localFilename: "boiler.jpg"))

        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(visit: visit, draft: draft)
        store.saveCapture(capture, for: visit.visitId)

        let loaded = store.loadCapture(for: visit.visitId)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.sessionId, visit.visitId)
        XCTAssertEqual(loaded?.visitReference, "JOB-INTEGRATION")
        XCTAssertEqual(loaded?.objectPins.count, 1)
        XCTAssertEqual(loaded?.photos.count, 1)
    }
}
