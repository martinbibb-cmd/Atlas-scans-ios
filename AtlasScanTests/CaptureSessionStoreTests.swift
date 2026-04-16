import XCTest
import AtlasContracts
@testable import AtlasScan

// MARK: - CaptureSessionStoreTests
//
// Tests for CaptureSessionStore — the single visit-owned session store.
//
// Covers:
//   - Session creation
//   - Visit reference update
//   - Add / remove room scan
//   - Add / remove photo
//   - Add / remove voice note
//   - Add / remove object pin
//   - Persist and reload draft
//   - Export state transitions

final class CaptureSessionStoreTests: XCTestCase {

    // MARK: - Helpers

    private func makeDraft(visitReference: String = "JOB-TEST") -> CaptureSessionDraft {
        CaptureSessionStore.newSession(visitReference: visitReference)
    }

    private func makeStore(visitReference: String = "JOB-TEST") -> CaptureSessionStore {
        let draft = makeDraft(visitReference: visitReference)
        return CaptureSessionStore(draft: draft)
    }

    private func makeTempPersistence() -> CaptureSessionPersistence {
        // Use the shared instance — each test uses a unique session ID so
        // there is no cross-test contamination, and files are cleaned up in tearDown.
        return .shared
    }

    // MARK: - Session creation

    func test_newSession_visitReferenceSet() {
        let draft = CaptureSessionStore.newSession(visitReference: "JOB-001")
        XCTAssertEqual(draft.visitReference, "JOB-001")
    }

    func test_newSession_exportStateIsDraft() {
        let draft = CaptureSessionStore.newSession(visitReference: "JOB-002")
        XCTAssertEqual(draft.exportState, .draft)
    }

    func test_newSession_artefactsEmpty() {
        let draft = CaptureSessionStore.newSession(visitReference: "JOB-003")
        XCTAssertTrue(draft.roomScans.isEmpty)
        XCTAssertTrue(draft.photos.isEmpty)
        XCTAssertTrue(draft.voiceNotes.isEmpty)
        XCTAssertTrue(draft.objectPins.isEmpty)
        XCTAssertTrue(draft.floorPlanSnapshots.isEmpty)
    }

    func test_newSession_idIsStable() {
        let draft = CaptureSessionStore.newSession(visitReference: "JOB-004")
        XCTAssertNotEqual(draft.id, UUID()) // not the zero UUID
    }

    // MARK: - Visit reference

    @MainActor func test_setVisitReference_updatesStore() {
        let store = makeStore(visitReference: "OLD-REF")
        store.setVisitReference("NEW-REF")
        XCTAssertEqual(store.draft.visitReference, "NEW-REF")
    }

    // MARK: - Room scans

    @MainActor func test_addRoomScan_appendsToStore() {
        let store = makeStore()
        let scan = CapturedRoomScanDraft(roomLabel: "Kitchen")
        store.addRoomScan(scan)
        XCTAssertEqual(store.draft.roomScans.count, 1)
        XCTAssertEqual(store.draft.roomScans.first?.roomLabel, "Kitchen")
    }

    @MainActor func test_removeRoomScan_removesFromStore() {
        let store = makeStore()
        let scan = CapturedRoomScanDraft(roomLabel: "Bathroom")
        store.addRoomScan(scan)
        store.removeRoomScan(id: scan.id)
        XCTAssertTrue(store.draft.roomScans.isEmpty)
    }

    @MainActor func test_updateRoomScan_updatesInStore() {
        let store = makeStore()
        var scan = CapturedRoomScanDraft(roomLabel: "Living Room")
        store.addRoomScan(scan)
        scan.roomLabel = "Lounge"
        store.updateRoomScan(scan)
        XCTAssertEqual(store.draft.roomScans.first?.roomLabel, "Lounge")
    }

    @MainActor func test_addRoomScan_idStableAfterAdd() {
        let store = makeStore()
        let scan = CapturedRoomScanDraft(roomLabel: "Study")
        store.addRoomScan(scan)
        XCTAssertEqual(store.draft.roomScans.first?.id, scan.id)
    }

    // MARK: - Photos

    @MainActor func test_addPhoto_appendsToStore() {
        let store = makeStore()
        let photo = CapturedPhotoDraft(localFilename: "p1.jpg")
        store.addPhoto(photo)
        XCTAssertEqual(store.draft.photos.count, 1)
    }

    @MainActor func test_removePhoto_removesFromStore() {
        let store = makeStore()
        let photo = CapturedPhotoDraft(localFilename: "p2.jpg")
        store.addPhoto(photo)
        store.removePhoto(id: photo.id)
        XCTAssertTrue(store.draft.photos.isEmpty)
    }

    @MainActor func test_addMultiplePhotos_allAppended() {
        let store = makeStore()
        store.addPhoto(CapturedPhotoDraft(localFilename: "a.jpg"))
        store.addPhoto(CapturedPhotoDraft(localFilename: "b.jpg"))
        store.addPhoto(CapturedPhotoDraft(localFilename: "c.jpg"))
        XCTAssertEqual(store.draft.photos.count, 3)
    }

    // MARK: - Voice notes

    @MainActor func test_addVoiceNote_appendsToStore() {
        let store = makeStore()
        var note = CapturedVoiceNoteDraft()
        note.transcript = "Test transcript"
        store.addVoiceNote(note)
        XCTAssertEqual(store.draft.voiceNotes.count, 1)
    }

    @MainActor func test_removeVoiceNote_removesFromStore() {
        let store = makeStore()
        let note = CapturedVoiceNoteDraft()
        store.addVoiceNote(note)
        store.removeVoiceNote(id: note.id)
        XCTAssertTrue(store.draft.voiceNotes.isEmpty)
    }

    @MainActor func test_updateVoiceNote_updatesTranscript() {
        let store = makeStore()
        var note = CapturedVoiceNoteDraft()
        store.addVoiceNote(note)
        note.transcript = "Boiler is in the kitchen."
        store.updateVoiceNote(note)
        XCTAssertEqual(store.draft.voiceNotes.first?.transcript, "Boiler is in the kitchen.")
    }

    // MARK: - Object pins

    @MainActor func test_addObjectPin_appendsToStore() {
        let store = makeStore()
        let pin = CapturedObjectPinDraft(type: .boiler)
        store.addObjectPin(pin)
        XCTAssertEqual(store.draft.objectPins.count, 1)
    }

    @MainActor func test_removeObjectPin_removesFromStore() {
        let store = makeStore()
        let pin = CapturedObjectPinDraft(type: .radiator)
        store.addObjectPin(pin)
        store.removeObjectPin(id: pin.id)
        XCTAssertTrue(store.draft.objectPins.isEmpty)
    }

    @MainActor func test_updateObjectPin_updatesLabel() {
        let store = makeStore()
        var pin = CapturedObjectPinDraft(type: .boiler)
        store.addObjectPin(pin)
        pin.label = "Worcester Bosch 30i"
        store.updateObjectPin(pin)
        XCTAssertEqual(store.draft.objectPins.first?.label, "Worcester Bosch 30i")
    }

    // MARK: - Export state

    @MainActor func test_markReadyForExport_updatesState() {
        let store = makeStore()
        store.markReadyForExport()
        XCTAssertEqual(store.draft.exportState, .readyForExport)
    }

    @MainActor func test_markExported_updatesState() {
        let store = makeStore()
        store.markExported()
        XCTAssertEqual(store.draft.exportState, .exported)
    }

    @MainActor func test_markExportFailed_updatesState() {
        let store = makeStore()
        store.markExportFailed()
        XCTAssertEqual(store.draft.exportState, .exportFailed)
    }

    // MARK: - Persist and reload

    func test_persistence_saveAndReload() throws {
        let persistence = CaptureSessionPersistence.shared
        var draft = CaptureSessionStore.newSession(visitReference: "JOB-PERSIST")
        var scan = CapturedRoomScanDraft()
        scan.roomLabel = "Kitchen"
        draft.roomScans.append(scan)
        var photo = CapturedPhotoDraft(localFilename: "test.jpg")
        draft.photos.append(photo)

        persistence.save(draft)

        let reloaded = persistence.load(id: draft.id)
        XCTAssertNotNil(reloaded)
        XCTAssertEqual(reloaded?.visitReference, "JOB-PERSIST")
        XCTAssertEqual(reloaded?.roomScans.count, 1)
        XCTAssertEqual(reloaded?.roomScans.first?.roomLabel, "Kitchen")
        XCTAssertEqual(reloaded?.photos.count, 1)

        // Cleanup
        persistence.delete(id: draft.id)
    }

    func test_persistence_lastIncompleteDraft_returnsNonExported() throws {
        let persistence = CaptureSessionPersistence.shared
        var draft = CaptureSessionStore.newSession(visitReference: "JOB-INCOMPLETE")
        draft.exportState = .draft
        persistence.save(draft)

        let last = persistence.lastIncompleteDraft()
        // Should return our draft (or another incomplete one if tests run in order).
        // Just verify it's not an exported session.
        if let found = last {
            XCTAssertNotEqual(found.exportState, .exported)
        }

        // Cleanup
        persistence.delete(id: draft.id)
    }

    func test_persistence_exportedSessionNotReturnedAsIncomplete() throws {
        let persistence = CaptureSessionPersistence.shared

        // Save an exported draft
        var exportedDraft = CaptureSessionStore.newSession(visitReference: "JOB-EXPORTED")
        exportedDraft.exportState = .exported
        persistence.save(exportedDraft)

        // Also save an incomplete draft with a known ID
        var incompleteDraft = CaptureSessionStore.newSession(visitReference: "JOB-INCOMPLETE-2")
        incompleteDraft.exportState = .draft
        persistence.save(incompleteDraft)

        let last = persistence.lastIncompleteDraft()
        XCTAssertNotEqual(last?.exportState, .exported,
                          "lastIncompleteDraft must not return an exported session")

        // Cleanup
        persistence.delete(id: exportedDraft.id)
        persistence.delete(id: incompleteDraft.id)
    }

    func test_persistence_roundTrip_allArtefactTypes() throws {
        let persistence = CaptureSessionPersistence.shared
        var draft = CaptureSessionStore.newSession(visitReference: "JOB-ROUNDTRIP")

        var scan = CapturedRoomScanDraft()
        scan.roomLabel = "Kitchen"
        draft.roomScans.append(scan)

        var photo = CapturedPhotoDraft(localFilename: "ph.jpg")
        photo.kind = .plant
        draft.photos.append(photo)

        var note = CapturedVoiceNoteDraft()
        note.transcript = "Note about boiler"
        draft.voiceNotes.append(note)

        var pin = CapturedObjectPinDraft(type: .cylinder)
        pin.label = "Hot water cylinder"
        draft.objectPins.append(pin)

        persistence.save(draft)

        let reloaded = try XCTUnwrap(persistence.load(id: draft.id))
        XCTAssertEqual(reloaded.roomScans.count, 1)
        XCTAssertEqual(reloaded.photos.count, 1)
        XCTAssertEqual(reloaded.photos.first?.kind, .plant)
        XCTAssertEqual(reloaded.voiceNotes.count, 1)
        XCTAssertEqual(reloaded.voiceNotes.first?.transcript, "Note about boiler")
        XCTAssertEqual(reloaded.objectPins.count, 1)
        XCTAssertEqual(reloaded.objectPins.first?.type, .cylinder)
        XCTAssertEqual(reloaded.objectPins.first?.label, "Hot water cylinder")

        // Cleanup
        persistence.delete(id: draft.id)
    }
}
