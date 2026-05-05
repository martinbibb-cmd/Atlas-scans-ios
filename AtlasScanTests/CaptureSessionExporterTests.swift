import XCTest
import AtlasContracts
@testable import AtlasScan

// MARK: - CaptureSessionExporterTests
//
// Tests for CaptureSessionExporter — the session-to-SessionCaptureV2 mapper.
//
// Covers:
//   - Valid session exports to SessionCaptureV2
//   - Missing optional sections still export
//   - Invalid session returns useful error
//   - Exported state updates correctly
//   - Raw audio not included in export payload
//   - Voice note transcript is included
//   - Schema version is correct
//   - All artefact types mapped correctly

final class CaptureSessionExporterTests: XCTestCase {

    // MARK: - Helpers

    private func makeDraft(
        visitReference: String = "JOB-EXPORT-TEST"
    ) -> CaptureSessionDraft {
        CaptureSessionStore.newSession(visitReference: visitReference)
    }

    private func draftWithRoomScan(
        visitReference: String = "JOB-EXPORT-TEST"
    ) -> CaptureSessionDraft {
        var draft = makeDraft(visitReference: visitReference)
        var scan = CapturedRoomScanDraft()
        scan.roomLabel = "Kitchen"
        draft.roomScans.append(scan)
        return draft
    }

    // MARK: - Validation

    func test_validate_missingVisitReference_returnsError() {
        let draft = makeDraft(visitReference: "")
        let errors = CaptureSessionExporter.validate(draft)
        XCTAssertTrue(errors.contains(.missingVisitReference))
    }

    func test_validate_whitespaceOnlyReference_returnsError() {
        let draft = makeDraft(visitReference: "   ")
        let errors = CaptureSessionExporter.validate(draft)
        XCTAssertTrue(errors.contains(.missingVisitReference))
    }

    func test_validate_emptyPayload_returnsError() {
        let draft = makeDraft(visitReference: "JOB-001")
        let errors = CaptureSessionExporter.validate(draft)
        XCTAssertTrue(errors.contains(.emptyPayload))
    }

    func test_validate_validSession_noErrors() {
        let draft = draftWithRoomScan()
        let errors = CaptureSessionExporter.validate(draft)
        XCTAssertTrue(errors.isEmpty)
    }

    func test_validate_photosOnly_noErrors() {
        var draft = makeDraft()
        draft.photos.append(CapturedPhotoDraft(localFilename: "p.jpg"))
        let errors = CaptureSessionExporter.validate(draft)
        XCTAssertTrue(errors.isEmpty)
    }

    // MARK: - Export

    func test_export_validSession_succeeds() throws {
        let draft = draftWithRoomScan()
        XCTAssertNoThrow(try CaptureSessionExporter.export(draft))
    }

    func test_export_missingReference_throws() {
        let draft = makeDraft(visitReference: "")
        XCTAssertThrowsError(try CaptureSessionExporter.export(draft))
    }

    func test_export_emptySession_throws() {
        let draft = makeDraft(visitReference: "JOB-001")
        XCTAssertThrowsError(try CaptureSessionExporter.export(draft))
    }

    // MARK: - Schema version

    func test_export_schemaVersionIsCurrentVersion() throws {
        let draft = draftWithRoomScan()
        let result = try CaptureSessionExporter.export(draft)
        XCTAssertEqual(result.payload.schemaVersion, currentSessionCaptureVersion)
    }

    func test_export_schemaVersionInSupportedList() throws {
        let draft = draftWithRoomScan()
        let result = try CaptureSessionExporter.export(draft)
        XCTAssertTrue(supportedSessionCaptureVersions.contains(result.payload.schemaVersion))
    }

    // MARK: - Session identity

    func test_export_sessionIdMatchesDraftId() throws {
        let draft = draftWithRoomScan()
        let result = try CaptureSessionExporter.export(draft)
        XCTAssertEqual(result.payload.sessionId, draft.id.uuidString)
    }

    func test_export_visitReferencePreserved() throws {
        let draft = draftWithRoomScan(visitReference: "MY-JOB-REFERENCE")
        let result = try CaptureSessionExporter.export(draft)
        XCTAssertEqual(result.payload.visitReference, "MY-JOB-REFERENCE")
    }

    // MARK: - Room scans

    func test_export_roomScansMapping() throws {
        var draft = makeDraft()
        var scan = CapturedRoomScanDraft()
        scan.roomLabel = "Living Room"
        scan.rawWidthM = 5.0
        scan.rawDepthM = 4.0
        scan.rawHeightM = 2.5
        scan.confidence = .high
        draft.roomScans.append(scan)

        let result = try CaptureSessionExporter.export(draft)

        XCTAssertEqual(result.payload.roomScans.count, 1)
        let exported = result.payload.roomScans.first!
        XCTAssertEqual(exported.id, scan.id.uuidString)
        XCTAssertEqual(exported.roomLabel, "Living Room")
        XCTAssertEqual(exported.rawWidthM, 5.0)
        XCTAssertEqual(exported.rawDepthM, 4.0)
        XCTAssertEqual(exported.rawHeightM, 2.5)
        XCTAssertEqual(exported.confidence, .high)
    }

    func test_export_roomScanWithoutLabel_labelIsNil() throws {
        var draft = makeDraft()
        var scan = CapturedRoomScanDraft()
        scan.roomLabel = nil
        draft.roomScans.append(scan)
        let result = try CaptureSessionExporter.export(draft)
        XCTAssertNil(result.payload.roomScans.first?.roomLabel)
    }

    // MARK: - Photos

    func test_export_photosMapping() throws {
        var draft = makeDraft()
        draft.photos.append(CapturedPhotoDraft(localFilename: "photo1.jpg"))
        let result = try CaptureSessionExporter.export(draft)
        XCTAssertEqual(result.payload.photos.count, 1)
        XCTAssertEqual(result.payload.photos.first?.localFilename, "photo1.jpg")
    }

    func test_export_photoRoomAssociation() throws {
        var draft = makeDraft()
        var scan = CapturedRoomScanDraft()
        let scanId = scan.id
        draft.roomScans.append(scan)

        var photo = CapturedPhotoDraft(localFilename: "room_photo.jpg")
        photo.roomId = scanId
        draft.photos.append(photo)

        let result = try CaptureSessionExporter.export(draft)
        XCTAssertEqual(result.payload.photos.first?.roomId, scanId.uuidString)
    }

    func test_export_sessionLevelPhoto_roomIdIsNil() throws {
        var draft = makeDraft()
        var photo = CapturedPhotoDraft(localFilename: "session.jpg")
        photo.roomId = nil
        draft.photos.append(photo)
        let result = try CaptureSessionExporter.export(draft)
        XCTAssertNil(result.payload.photos.first?.roomId)
    }

    // MARK: - Voice notes (transcript only, no audio)

    func test_export_voiceNoteTranscriptPreserved() throws {
        var draft = makeDraft()
        var note = CapturedVoiceNoteDraft()
        note.transcript = "The boiler is in the kitchen, near the back wall."
        draft.voiceNotes.append(note)
        let result = try CaptureSessionExporter.export(draft)
        XCTAssertEqual(result.payload.voiceNotes.first?.transcript,
                       "The boiler is in the kitchen, near the back wall.")
    }

    func test_export_voiceNoteNoRawAudioInPayload() throws {
        var draft = makeDraft()
        var note = CapturedVoiceNoteDraft()
        note.transcript = "Test transcript"
        draft.voiceNotes.append(note)

        let result = try CaptureSessionExporter.export(draft)
        let json = String(data: result.jsonData, encoding: .utf8) ?? ""

        // The exported JSON must not contain any audio file references
        XCTAssertFalse(json.contains(".m4a"), "m4a audio path must not appear in export")
        XCTAssertFalse(json.contains(".mp3"), "mp3 audio path must not appear in export")
        XCTAssertFalse(json.contains(".wav"), "wav audio path must not appear in export")
        XCTAssertFalse(json.contains("rawAudio"), "rawAudio field must not appear in export")
        XCTAssertFalse(json.contains("audioPath"), "audioPath field must not appear in export")
        XCTAssertFalse(json.contains("localFilename"), "audio localFilename must not appear in voice note export")
    }

    func test_export_voiceNoteRoomAssociation() throws {
        var draft = makeDraft()
        var scan = CapturedRoomScanDraft()
        draft.roomScans.append(scan)

        var note = CapturedVoiceNoteDraft()
        note.transcript = "Observation"
        note.roomId = scan.id
        draft.voiceNotes.append(note)

        let result = try CaptureSessionExporter.export(draft)
        XCTAssertEqual(result.payload.voiceNotes.first?.roomId, scan.id.uuidString)
    }

    func test_export_voiceNoteSessionLevel_roomIdNil() throws {
        var draft = makeDraft()
        var note = CapturedVoiceNoteDraft()
        note.transcript = "Session-level note"
        note.roomId = nil
        draft.voiceNotes.append(note)
        let result = try CaptureSessionExporter.export(draft)
        XCTAssertNil(result.payload.voiceNotes.first?.roomId)
    }

    // MARK: - Object pins

    func test_export_objectPinsMapping() throws {
        var draft = makeDraft()
        var pin = CapturedObjectPinDraft(type: .boiler)
        pin.label = "Worcester Bosch 30i"
        draft.objectPins.append(pin)
        let result = try CaptureSessionExporter.export(draft)
        XCTAssertEqual(result.payload.objectPins.count, 1)
        XCTAssertEqual(result.payload.objectPins.first?.type, "boiler")
        XCTAssertEqual(result.payload.objectPins.first?.label, "Worcester Bosch 30i")
    }

    func test_export_allObjectPinTypesExportable() throws {
        var draft = makeDraft()
        for type in ObjectPinType.allCases {
            draft.objectPins.append(CapturedObjectPinDraft(type: type))
        }
        let result = try CaptureSessionExporter.export(draft)
        XCTAssertEqual(result.payload.objectPins.count, ObjectPinType.allCases.count)
    }

    // MARK: - Missing optional sections

    func test_export_noPhotos_stillExports() throws {
        var draft = makeDraft()
        draft.roomScans.append(CapturedRoomScanDraft())
        let result = try CaptureSessionExporter.export(draft)
        XCTAssertTrue(result.payload.photos.isEmpty)
    }

    func test_export_noVoiceNotes_stillExports() throws {
        var draft = makeDraft()
        draft.roomScans.append(CapturedRoomScanDraft())
        let result = try CaptureSessionExporter.export(draft)
        XCTAssertTrue(result.payload.voiceNotes.isEmpty)
    }

    func test_export_noObjectPins_stillExports() throws {
        var draft = makeDraft()
        draft.roomScans.append(CapturedRoomScanDraft())
        let result = try CaptureSessionExporter.export(draft)
        XCTAssertTrue(result.payload.objectPins.isEmpty)
    }

    func test_export_onlyObjectPins_succeeds() throws {
        var draft = makeDraft()
        draft.objectPins.append(CapturedObjectPinDraft(type: .radiator))
        XCTAssertNoThrow(try CaptureSessionExporter.export(draft))
    }

    // MARK: - Object pin attachment modes

    /// An object pin with a roomId links to that room scan.
    func test_objectPin_withRoomId_linksToRoom() throws {
        var draft = makeDraft()
        let roomScan = CapturedRoomScanDraft()
        draft.roomScans.append(roomScan)

        var pin = CapturedObjectPinDraft(type: .boiler)
        pin.roomId = roomScan.id
        draft.objectPins.append(pin)

        let result = try CaptureSessionExporter.export(draft)
        XCTAssertEqual(result.payload.objectPins.first?.roomId, roomScan.id.uuidString)
        XCTAssertNil(result.payload.objectPins.first?.linkedPhotoId)
    }

    /// An object pin can link to a photo via linkedPhotoId even when no room scan exists.
    func test_objectPin_withPhotoId_linksToPhoto_noRoomRequired() throws {
        var draft = makeDraft()
        // No room scan — photo-only job
        let photo = CapturedPhotoDraft(localFilename: "boiler_overview.jpg")
        draft.photos.append(photo)

        var pin = CapturedObjectPinDraft(type: .boiler)
        pin.linkedPhotoId = photo.id
        // roomId is intentionally nil
        draft.objectPins.append(pin)

        let result = try CaptureSessionExporter.export(draft)
        let exported = try XCTUnwrap(result.payload.objectPins.first)
        XCTAssertEqual(exported.linkedPhotoId, photo.id.uuidString)
        XCTAssertNil(exported.roomId, "Photo-linked pin must not carry a roomId")
    }

    /// An object pin with neither a roomId nor a linkedPhotoId is visit-level evidence.
    func test_objectPin_noRoomNoPhoto_isSessionLevelEvidence() throws {
        var draft = makeDraft()
        let pin = CapturedObjectPinDraft(type: .evidencePoint)
        // Both roomId and linkedPhotoId are nil — session-level
        draft.objectPins.append(pin)

        let result = try CaptureSessionExporter.export(draft)
        let exported = try XCTUnwrap(result.payload.objectPins.first)
        XCTAssertNil(exported.roomId, "Session-level pin must have nil roomId")
        XCTAssertNil(exported.linkedPhotoId, "Session-level pin must have nil linkedPhotoId")
        XCTAssertEqual(exported.id, pin.id.uuidString)
    }

    /// Photo-only jobs are first-class: a draft with only photos and object pins
    /// passes validation and exports without errors.
    func test_photoOnlyJob_withObjectPin_isValid() throws {
        var draft = makeDraft()
        draft.photos.append(CapturedPhotoDraft(localFilename: "overview.jpg"))
        draft.objectPins.append(CapturedObjectPinDraft(type: .boiler))

        let errors = CaptureSessionExporter.validate(draft)
        XCTAssertTrue(errors.isEmpty, "Photo-only job with an object pin must pass validation")
        XCTAssertNoThrow(try CaptureSessionExporter.export(draft))
    }

    // MARK: - JSON encoding

    func test_export_encodesToValidJSON() throws {
        let draft = draftWithRoomScan()
        let result = try CaptureSessionExporter.export(draft)
        XCTAssertFalse(result.jsonData.isEmpty)

        // Verify the JSON is valid and round-trips correctly.
        let decoded = try JSONDecoder().decode(SessionCaptureV2.self, from: result.jsonData)
        XCTAssertEqual(decoded.schemaVersion, currentSessionCaptureVersion)
        XCTAssertEqual(decoded.sessionId, draft.id.uuidString)
    }

    func test_export_jsonContainsVisitReference() throws {
        let draft = draftWithRoomScan(visitReference: "JOB-JSON-CHECK")
        let result = try CaptureSessionExporter.export(draft)
        let json = String(data: result.jsonData, encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("JOB-JSON-CHECK"))
    }

    // MARK: - QA flags

    func test_export_untranscribedVoiceNote_producesQAFlag() throws {
        var draft = makeDraft()
        var note = CapturedVoiceNoteDraft()
        note.transcript = ""  // empty — no transcript
        draft.voiceNotes.append(note)
        let result = try CaptureSessionExporter.export(draft)
        XCTAssertTrue(result.payload.qaFlags.contains(where: { $0.code == "VOICE_NOTE_NO_TRANSCRIPT" }))
    }

    func test_export_fullyTranscribedNotes_noTranscriptQAFlag() throws {
        var draft = makeDraft()
        var note = CapturedVoiceNoteDraft()
        note.transcript = "This is a proper transcript."
        draft.voiceNotes.append(note)
        let result = try CaptureSessionExporter.export(draft)
        XCTAssertFalse(result.payload.qaFlags.contains(where: { $0.code == "VOICE_NOTE_NO_TRANSCRIPT" }))
    }

    // MARK: - quotePlannerEvidence export

    func test_export_quotePlannerAnchor_isIncludedInPayload() throws {
        var draft = draftWithRoomScan()
        var anchor = CapturedQuotePlannerAnchorDraft()
        anchor.kind = .existingBoiler
        anchor.label = "Kitchen boiler"
        anchor.provenance = .manual
        draft.quotePlannerAnchors.append(anchor)

        let result = try CaptureSessionExporter.export(draft)

        XCTAssertNotNil(result.payload.quotePlannerEvidence,
                        "quotePlannerEvidence must be present when anchors are captured")
        XCTAssertEqual(result.payload.quotePlannerEvidence?.candidateLocations.count, 1)
        let loc = result.payload.quotePlannerEvidence?.candidateLocations.first
        XCTAssertEqual(loc?.kind, "existing_boiler")
        XCTAssertEqual(loc?.label, "Kitchen boiler")
        XCTAssertEqual(loc?.confidence, "confirmed")
    }

    func test_export_noAnchors_quotePlannerEvidenceIsNil() throws {
        let draft = draftWithRoomScan()
        let result = try CaptureSessionExporter.export(draft)
        XCTAssertNil(result.payload.quotePlannerEvidence,
                     "quotePlannerEvidence must be nil when no anchors or routes recorded")
    }

    func test_export_candidateRoute_isIncludedInPayload() throws {
        var draft = draftWithRoomScan()
        var route = CapturedCandidateRouteDraft()
        route.routeType = .gas
        route.status = .proposed
        route.provenance = .manual
        draft.candidateRoutes.append(route)

        let result = try CaptureSessionExporter.export(draft)

        XCTAssertNotNil(result.payload.quotePlannerEvidence)
        XCTAssertEqual(result.payload.quotePlannerEvidence?.candidateRoutes.count, 1)
        let exported = result.payload.quotePlannerEvidence?.candidateRoutes.first
        XCTAssertEqual(exported?.routeType, "gas")
        XCTAssertEqual(exported?.status, "proposed")
    }

    func test_export_routeWithEmptyNotes_notesIsNil() throws {
        var draft = draftWithRoomScan()
        var route = CapturedCandidateRouteDraft()
        route.routeType = .condensate
        route.notes = ""
        draft.candidateRoutes.append(route)

        let result = try CaptureSessionExporter.export(draft)

        XCTAssertNil(result.payload.quotePlannerEvidence?.candidateRoutes.first?.notes,
                     "Empty notes must export as nil")
    }

    func test_export_anchorsAndRoutes_bothExported() throws {
        var draft = draftWithRoomScan()
        var anchor = CapturedQuotePlannerAnchorDraft()
        anchor.kind = .gasMeter
        draft.quotePlannerAnchors.append(anchor)

        var route = CapturedCandidateRouteDraft()
        route.routeType = .gas
        draft.candidateRoutes.append(route)

        let result = try CaptureSessionExporter.export(draft)

        XCTAssertNotNil(result.payload.quotePlannerEvidence)
        XCTAssertEqual(result.payload.quotePlannerEvidence?.candidateLocations.count, 1)
        XCTAssertEqual(result.payload.quotePlannerEvidence?.candidateRoutes.count, 1)
    }

    func test_export_quotePlannerEvidence_roundTripsJSON() throws {
        var draft = draftWithRoomScan()
        var anchor = CapturedQuotePlannerAnchorDraft()
        anchor.kind = .proposedBoiler
        anchor.provenance = .arPin
        draft.quotePlannerAnchors.append(anchor)

        let result = try CaptureSessionExporter.export(draft)
        let decoded = try JSONDecoder().decode(SessionCaptureV2.self, from: result.jsonData)

        XCTAssertNotNil(decoded.quotePlannerEvidence)
        XCTAssertEqual(decoded.quotePlannerEvidence?.candidateLocations.first?.kind, "proposed_boiler")
        XCTAssertEqual(decoded.quotePlannerEvidence?.candidateLocations.first?.confidence, "measured")
    }
}

// MARK: - VoiceNoteRecorderViewModelTests

final class VoiceNoteRecorderViewModelTests: XCTestCase {

    // MARK: - Lifecycle

    @MainActor func test_initialState_isIdle() {
        let vm = VoiceNoteRecorderViewModel()
        XCTAssertEqual(vm.state, .idle)
    }

    @MainActor func test_start_transitionsToRecording() {
        let vm = VoiceNoteRecorderViewModel()
        vm.start()
        XCTAssertEqual(vm.state, .recording)
    }

    @MainActor func test_pause_transitionsToPaused() {
        let vm = VoiceNoteRecorderViewModel()
        vm.start()
        vm.pause()
        XCTAssertEqual(vm.state, .paused)
    }

    @MainActor func test_resume_transitionsToRecording() {
        let vm = VoiceNoteRecorderViewModel()
        vm.start()
        vm.pause()
        vm.resume()
        XCTAssertEqual(vm.state, .recording)
    }

    @MainActor func test_stop_transitionsToStopped() {
        let vm = VoiceNoteRecorderViewModel()
        vm.start()
        vm.stop()
        XCTAssertEqual(vm.state, .stopped)
    }

    @MainActor func test_commit_returnsNoteWithTranscript() {
        let vm = VoiceNoteRecorderViewModel()
        vm.start()
        vm.stop()
        vm.transcript = "Test observation"
        let note = vm.commit()
        XCTAssertNotNil(note)
        XCTAssertEqual(note?.transcript, "Test observation")
    }

    @MainActor func test_commit_returnsNilWhenNotStopped() {
        let vm = VoiceNoteRecorderViewModel()
        vm.start()
        // Still recording — commit should not succeed
        let note = vm.commit()
        XCTAssertNil(note)
    }

    @MainActor func test_commit_resetsStateToIdle() {
        let vm = VoiceNoteRecorderViewModel()
        vm.start()
        vm.stop()
        _ = vm.commit()
        XCTAssertEqual(vm.state, .idle)
    }

    @MainActor func test_discard_resetsStateToIdle() {
        let vm = VoiceNoteRecorderViewModel()
        vm.start()
        vm.discard()
        XCTAssertEqual(vm.state, .idle)
    }

    @MainActor func test_commit_committedNote_hasNoRawAudioRef() {
        let vm = VoiceNoteRecorderViewModel()
        vm.start()
        vm.stop()
        vm.transcript = "Boiler note"
        let note = vm.commit()
        // CapturedVoiceNoteDraft must not contain any audio file reference
        // (the struct itself has no audioPath field — this is a type-safety test)
        XCTAssertNotNil(note)
        // If this test compiles, the type constraint is satisfied:
        // CapturedVoiceNoteDraft has no audio path field.
        let mirror = Mirror(reflecting: note!)
        let fieldNames = mirror.children.compactMap(\.label)
        XCTAssertFalse(fieldNames.contains("audioPath"), "audioPath must not exist in CapturedVoiceNoteDraft")
        XCTAssertFalse(fieldNames.contains("rawAudioPath"), "rawAudioPath must not exist in CapturedVoiceNoteDraft")
        XCTAssertFalse(fieldNames.contains("localFilename"), "localFilename must not exist in CapturedVoiceNoteDraft")
    }

    @MainActor func test_roomAssociation_passedToCommittedNote() {
        let vm = VoiceNoteRecorderViewModel()
        let roomId = UUID()
        vm.start(roomId: roomId)
        vm.stop()
        let note = vm.commit()
        XCTAssertEqual(note?.roomId, roomId)
    }
}
