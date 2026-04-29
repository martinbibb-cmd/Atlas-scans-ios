import XCTest
@testable import AtlasScan

// MARK: - VisitContainerTests
//
// Unit tests for the new minimal visit container flow.
//
// Covers:
//   - Start: creates a persisted draft with the supplied visit reference
//   - Save / reload: persistence round-trip
//   - Reopen: last incomplete draft surfaced correctly after restart
//   - Exit: data not corrupted by closing the visit
//   - Delete: removes draft from persistence
//   - Mark complete (exported): state persists
//   - Photo attachment: filename preserved
//   - Note attachment: transcript preserved
//   - Export validation: visit reference required, some evidence required
//   - Export success: valid JSON containing visit reference

@MainActor
final class VisitContainerTests: XCTestCase {

    // MARK: - Fixtures

    private var persistence: CaptureSessionPersistence!

    override func setUp() async throws {
        try await super.setUp()
        persistence = CaptureSessionPersistence.makeTestInstance()
    }

    override func tearDown() async throws {
        persistence.deleteAll()
        persistence = nil
        try await super.tearDown()
    }

    private func makeStore(visitReference: String = "JOB-TEST") -> CaptureSessionStore {
        CaptureSessionStore(
            draft: CaptureSessionStore.newSession(visitReference: visitReference),
            persistence: persistence
        )
    }

    // MARK: - Start

    func test_start_createsPersistedDraft() {
        var draft = CaptureSessionStore.newSession(visitReference: "JOB-001")
        persistence.save(draft)

        let all = persistence.loadAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.visitReference, "JOB-001")
    }

    func test_start_initialStateIsDraft() {
        let draft = CaptureSessionStore.newSession(visitReference: "JOB-002")
        XCTAssertEqual(draft.exportState, .draft)
    }

    func test_start_visitReferencePreserved() {
        let draft = CaptureSessionStore.newSession(visitReference: "VISIT-ABC")
        XCTAssertEqual(draft.visitReference, "VISIT-ABC")
    }

    func test_start_propertyAddressPreserved() {
        var draft = CaptureSessionStore.newSession(visitReference: "JOB-003")
        draft.propertyAddress = "42 Example Road"
        persistence.save(draft)

        let loaded = persistence.load(id: draft.id)
        XCTAssertEqual(loaded?.propertyAddress, "42 Example Road")
    }

    // MARK: - Save / reload

    func test_save_draftPersistsAcrossReload() {
        let draft = CaptureSessionStore.newSession(visitReference: "JOB-SAVE-001")
        persistence.save(draft)

        let reloaded = persistence.load(id: draft.id)
        XCTAssertNotNil(reloaded)
        XCTAssertEqual(reloaded?.id, draft.id)
    }

    func test_save_multipleVisitsPersist() {
        for i in 1...3 {
            persistence.save(CaptureSessionStore.newSession(visitReference: "JOB-\(i)"))
        }
        XCTAssertEqual(persistence.loadAll().count, 3)
    }

    func test_save_updatePreservesId() {
        var draft = CaptureSessionStore.newSession(visitReference: "JOB-UPDATE")
        let originalId = draft.id
        persistence.save(draft)

        draft.propertyAddress = "Updated Address"
        persistence.save(draft)

        let loaded = persistence.load(id: originalId)
        XCTAssertEqual(loaded?.propertyAddress, "Updated Address")
        XCTAssertEqual(loaded?.id, originalId)
    }

    // MARK: - Reopen

    func test_reopen_incompleteSessionResumable() {
        persistence.save(CaptureSessionStore.newSession(visitReference: "JOB-REOPEN"))
        let incomplete = persistence.lastIncompleteDraft()
        XCTAssertNotNil(incomplete)
        XCTAssertEqual(incomplete?.visitReference, "JOB-REOPEN")
    }

    func test_reopen_exportedSessionNotReturnedAsIncomplete() {
        var draft = CaptureSessionStore.newSession(visitReference: "JOB-EXPORTED")
        draft.exportState = .exported
        persistence.save(draft)

        XCTAssertNil(persistence.lastIncompleteDraft(),
                     "Exported session must not appear in last incomplete")
    }

    func test_reopen_mostRecentIncompleteIsFirst() {
        var older = CaptureSessionStore.newSession(visitReference: "JOB-OLD")
        older.updatedAt = Date(timeIntervalSinceNow: -3600)
        persistence.save(older)

        persistence.save(CaptureSessionStore.newSession(visitReference: "JOB-NEW"))

        let all = persistence.loadAll()
        XCTAssertEqual(all.first?.visitReference, "JOB-NEW",
                       "Most recently updated visit must appear first")
    }

    // MARK: - Exit (data integrity)

    func test_exit_dataSurvivestoreClose() {
        let store = makeStore(visitReference: "JOB-EXIT")
        let photo = CapturedPhotoDraft(localFilename: "evidence.jpg")
        store.addPhoto(photo)
        store.saveNow()

        // Simulate close + reopen by loading from disk
        let reloaded = persistence.load(id: store.draft.id)
        XCTAssertNotNil(reloaded)
        XCTAssertEqual(reloaded?.photos.count, 1)
    }

    // MARK: - Delete

    func test_delete_removesFromPersistence() {
        let draft = CaptureSessionStore.newSession(visitReference: "JOB-DELETE")
        persistence.save(draft)

        persistence.delete(id: draft.id)

        XCTAssertNil(persistence.load(id: draft.id))
    }

    func test_delete_doesNotAffectOtherSessions() {
        let keep   = CaptureSessionStore.newSession(visitReference: "JOB-KEEP")
        let remove = CaptureSessionStore.newSession(visitReference: "JOB-REMOVE")
        persistence.save(keep)
        persistence.save(remove)

        persistence.delete(id: remove.id)

        let all = persistence.loadAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.visitReference, "JOB-KEEP")
    }

    // MARK: - Mark complete (exported)

    func test_markExported_setsExportedState() {
        let store = makeStore(visitReference: "JOB-MARK-EXPORTED")
        store.markExported()
        XCTAssertEqual(store.draft.exportState, .exported)
    }

    func test_markExported_persists() {
        let store = makeStore(visitReference: "JOB-EXPORT-PERSIST")
        store.markExported()

        let loaded = persistence.load(id: store.draft.id)
        XCTAssertEqual(loaded?.exportState, .exported)
    }

    // MARK: - Photo attachment

    func test_addPhoto_increasesCount() {
        let store = makeStore(visitReference: "JOB-PHOTO")
        store.addPhoto(CapturedPhotoDraft(localFilename: "evidence.jpg"))
        XCTAssertEqual(store.draft.photos.count, 1)
    }

    func test_addPhoto_filenamePreserved() {
        let store = makeStore(visitReference: "JOB-PHOTO-FNAME")
        store.addPhoto(CapturedPhotoDraft(localFilename: "my_photo.jpg"))
        XCTAssertEqual(store.draft.photos.first?.localFilename, "my_photo.jpg")
    }

    func test_addPhoto_photoPersistsAfterSave() {
        let store = makeStore(visitReference: "JOB-PHOTO-SAVE")
        store.addPhoto(CapturedPhotoDraft(localFilename: "saved_photo.jpg"))
        store.saveNow()

        let reloaded = persistence.load(id: store.draft.id)
        XCTAssertEqual(reloaded?.photos.first?.localFilename, "saved_photo.jpg")
    }

    // MARK: - Note attachment

    func test_addNote_increasesCount() {
        let store = makeStore(visitReference: "JOB-NOTE")
        var note = CapturedVoiceNoteDraft()
        note.transcript = "Boiler located in kitchen cupboard."
        note.endedAt = Date()
        store.addVoiceNote(note)
        XCTAssertEqual(store.draft.voiceNotes.count, 1)
    }

    func test_addNote_transcriptPreserved() {
        let store = makeStore(visitReference: "JOB-NOTE-TEXT")
        var note = CapturedVoiceNoteDraft()
        note.transcript = "The flue exits through the rear wall."
        note.endedAt = Date()
        store.addVoiceNote(note)
        XCTAssertEqual(store.draft.voiceNotes.first?.transcript, "The flue exits through the rear wall.")
    }

    func test_addNote_notePersistsAfterSave() {
        let store = makeStore(visitReference: "JOB-NOTE-SAVE")
        var note = CapturedVoiceNoteDraft()
        note.transcript = "Hot water cylinder in airing cupboard."
        note.endedAt = Date()
        store.addVoiceNote(note)
        store.saveNow()

        let reloaded = persistence.load(id: store.draft.id)
        XCTAssertEqual(reloaded?.voiceNotes.first?.transcript, "Hot water cylinder in airing cupboard.")
    }

    // MARK: - Export validation

    func test_export_requiresVisitReference() {
        let draft = CaptureSessionStore.newSession(visitReference: "")
        let errors = CaptureSessionExporter.validate(draft)
        XCTAssertTrue(errors.contains(.missingVisitReference))
    }

    func test_export_requiresSomeEvidence() {
        let draft = CaptureSessionStore.newSession(visitReference: "JOB-EMPTY")
        let errors = CaptureSessionExporter.validate(draft)
        XCTAssertTrue(errors.contains(.emptyPayload))
    }

    func test_export_succeedsWithPhotoOnly() throws {
        var draft = CaptureSessionStore.newSession(visitReference: "JOB-PHOTO-ONLY")
        draft.photos.append(CapturedPhotoDraft(localFilename: "photo.jpg"))
        XCTAssertNoThrow(try CaptureSessionExporter.export(draft))
    }

    func test_export_succeedsWithNoteOnly() throws {
        var draft = CaptureSessionStore.newSession(visitReference: "JOB-NOTE-ONLY")
        var note = CapturedVoiceNoteDraft()
        note.transcript = "Test note"
        note.endedAt = Date()
        draft.voiceNotes.append(note)
        XCTAssertNoThrow(try CaptureSessionExporter.export(draft))
    }

    func test_export_jsonContainsVisitReference() throws {
        var draft = CaptureSessionStore.newSession(visitReference: "REF-JSON-CHECK")
        draft.photos.append(CapturedPhotoDraft(localFilename: "photo.jpg"))

        let result = try CaptureSessionExporter.export(draft)
        let json = String(data: result.jsonData, encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("REF-JSON-CHECK"),
                      "Visit reference must appear in exported JSON")
    }

    func test_export_jsonDoesNotContainRawAudioFilename() throws {
        var draft = CaptureSessionStore.newSession(visitReference: "JOB-AUDIO-CHECK")
        // Voice note with transcript — raw audio filename should never leak
        var note = CapturedVoiceNoteDraft()
        note.transcript = "Transcript text only."
        note.endedAt = Date()
        draft.voiceNotes.append(note)

        let result = try CaptureSessionExporter.export(draft)
        let json = String(data: result.jsonData, encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains(".m4a"),
                       "Raw audio filename must not appear in exported JSON")
    }
}
