import XCTest
import AtlasContracts
@testable import AtlasScan

// MARK: - FieldVisitStoreTests
//
// Unit tests for FieldVisitStore.
// Covers:
//   - Loads visit with missing optional fields safely
//   - Derives readiness without crashing
//   - Derives planning readiness without crashing
//   - Updates lifecycle status when moving into capture/planning sections
//   - Persists modifications to field survey/planning overlay

@MainActor
final class FieldVisitStoreTests: XCTestCase {

    // MARK: - Helpers

    private func makeSession(address: String = "1 Test Street") -> PropertyScanSession {
        PropertyScanSession(jobReference: "JOB-TEST", propertyAddress: address)
    }

    private func makeStore(session: PropertyScanSession? = nil) -> FieldVisitStore {
        let s = session ?? makeSession()
        return FieldVisitStore(session: s, sessionStore: ScanSessionStore())
    }

    // MARK: - Safe loading with missing optional fields

    func test_init_emptySessionDoesNotCrash() {
        // An empty session (no rooms, no objects, no photos) must not crash
        // when the store is initialised.
        let store = makeStore()
        XCTAssertNotNil(store)
        XCTAssertEqual(store.session.visitLifecycle, .draft)
    }

    func test_fieldSurvey_emptySessionReturnsEmptySurvey() {
        let store = makeStore()
        let survey = store.fieldSurvey
        XCTAssertEqual(survey.roomCount, 0)
        XCTAssertEqual(survey.totalPhotoCount, 0)
        XCTAssertEqual(survey.totalVoiceNoteCount, 0)
        XCTAssertFalse(survey.hasBoiler)
        XCTAssertFalse(survey.hasFlue)
        XCTAssertFalse(survey.hasHotWaterSystem)
        XCTAssertFalse(survey.hasHeatingSystem)
    }

    func test_planningOverlay_emptySessionReturnsEmptyOverlay() {
        let store = makeStore()
        let overlay = store.planningOverlay
        XCTAssertTrue(overlay.isEmpty)
    }

    func test_visitReadiness_emptySessionAllFalse() {
        let store = makeStore()
        let readiness = store.visitReadiness
        XCTAssertFalse(readiness.hasRooms)
        XCTAssertFalse(readiness.hasPhotos)
        XCTAssertFalse(readiness.hasBoiler)
        XCTAssertFalse(readiness.hasFlue)
        XCTAssertFalse(readiness.isReady)
    }

    // MARK: - Derives readiness without crashing

    func test_visitReadiness_derivationDoesNotCrash() {
        var session = makeSession()
        session.addRoom(ScannedRoom(jobID: session.id, name: "Kitchen"))
        session.addPhoto(TaggedPhoto(filename: "p.jpg"))
        session.addTaggedObject(TaggedObject(roomID: session.id, category: .boiler))
        session.addTaggedObject(TaggedObject(roomID: session.id, category: .flue))

        let store = makeStore(session: session)
        let readiness = store.visitReadiness
        XCTAssertTrue(readiness.hasRooms)
        XCTAssertTrue(readiness.hasPhotos)
        XCTAssertTrue(readiness.hasBoiler)
        XCTAssertTrue(readiness.hasFlue)
        XCTAssertTrue(readiness.isReady)
    }

    func test_visitReadiness_heatPumpCountsAsBoiler() {
        var session = makeSession()
        session.addRoom(ScannedRoom(jobID: session.id, name: "Plant Room"))
        session.addPhoto(TaggedPhoto(filename: "p.jpg"))
        session.addTaggedObject(TaggedObject(roomID: session.id, category: .heatPump))
        session.addTaggedObject(TaggedObject(roomID: session.id, category: .flue))

        let store = makeStore(session: session)
        XCTAssertTrue(store.visitReadiness.hasBoiler, "Heat pump must satisfy the boiler check")
    }

    func test_visitReadiness_cylinderCountsAsHotWaterSystem() {
        var session = makeSession()
        session.addTaggedObject(TaggedObject(roomID: session.id, category: .cylinder))

        let store = makeStore(session: session)
        XCTAssertTrue(store.visitReadiness.hasHotWaterSystem)
    }

    func test_visitReadiness_missingItemsListsCorrectly() {
        let store = makeStore()
        let missing = store.visitReadiness.missingItems
        XCTAssertFalse(missing.isEmpty, "Empty session should have missing items")
        XCTAssertTrue(missing.contains(where: { $0.contains("room") || $0.contains("Room") }))
    }

    // MARK: - Derives planning readiness without crashing

    func test_planningReadiness_emptyOverlay() {
        let store = makeStore()
        let planning = store.planningReadiness
        XCTAssertEqual(planning.proposedEmittersCount, 0)
        XCTAssertEqual(planning.routesCount, 0)
        XCTAssertEqual(planning.accessNotesCount, 0)
        XCTAssertEqual(planning.roomPlansCount, 0)
        XCTAssertEqual(planning.specNotesCount, 0)
    }

    func test_planningReadiness_reflectsAnnotationCounts() {
        var session = makeSession()
        session.addPlanningAnnotation(PlanningAnnotation(text: "Check access under stairs", kind: .accessNote))
        session.addPlanningAnnotation(PlanningAnnotation(text: "Radiator in living room corner", kind: .roomPlanNote))
        session.addPlanningAnnotation(PlanningAnnotation(text: "Use 22mm pipe", kind: .specNote))

        let store = makeStore(session: session)
        let planning = store.planningReadiness
        XCTAssertEqual(planning.accessNotesCount, 1)
        XCTAssertEqual(planning.roomPlansCount, 1)
        XCTAssertEqual(planning.specNotesCount, 1)
    }

    func test_planningReadiness_proposedEmittersFromMarkupObjects() {
        var session = makeSession()
        let emitter = InstallMarkupObject(
            categoryRawValue: "radiator",
            label: "Hall rad",
            position: NormalizedPoint2D(x: 0.5, y: 0.5),
            layer: .proposed
        )
        session.installMarkupObjects.append(emitter)

        let store = makeStore(session: session)
        XCTAssertEqual(store.planningReadiness.proposedEmittersCount, 1)
    }

    func test_planningReadiness_existingLayerObjectsNotCounted() {
        var session = makeSession()
        let existingEmitter = InstallMarkupObject(
            categoryRawValue: "radiator",
            label: "Existing rad",
            position: NormalizedPoint2D(x: 0.5, y: 0.5),
            layer: .existing
        )
        session.installMarkupObjects.append(existingEmitter)

        let store = makeStore(session: session)
        XCTAssertEqual(store.planningReadiness.proposedEmittersCount, 0,
                       "Existing-layer objects must not count as proposed emitters")
    }

    // MARK: - Lifecycle transitions

    func test_enterCapturePhase_advancesFromDraft() {
        let store = makeStore()
        XCTAssertEqual(store.session.visitLifecycle, .draft)
        store.enterCapturePhase()
        XCTAssertEqual(store.session.visitLifecycle, .capturing)
    }

    func test_enterCapturePhase_doesNotDowngradeFromPlanning() {
        var session = makeSession()
        session.visitLifecycle = .planning
        let store = makeStore(session: session)
        store.enterCapturePhase()
        XCTAssertEqual(store.session.visitLifecycle, .planning,
                       "enterCapturePhase must not downgrade from planning")
    }

    func test_enterPlanningPhase_advancesFromCapturing() {
        var session = makeSession()
        session.visitLifecycle = .capturing
        let store = makeStore(session: session)
        store.enterPlanningPhase()
        XCTAssertEqual(store.session.visitLifecycle, .planning)
    }

    func test_enterPlanningPhase_advancesFromDraft() {
        let store = makeStore()
        store.enterPlanningPhase()
        XCTAssertEqual(store.session.visitLifecycle, .planning)
    }

    func test_enterPlanningPhase_doesNotChangeFromComplete() {
        var session = makeSession()
        session.visitLifecycle = .complete
        let store = makeStore(session: session)
        store.enterPlanningPhase()
        XCTAssertEqual(store.session.visitLifecycle, .complete,
                       "enterPlanningPhase must not change a completed visit")
    }

    func test_lifecycleBadgeStatus_showsReadyToCompleteWhenReadinessPasses() {
        var session = makeSession()
        session.visitLifecycle = .capturing
        session.addRoom(ScannedRoom(jobID: session.id, name: "Kitchen"))
        session.addPhoto(TaggedPhoto(filename: "p.jpg"))
        session.addTaggedObject(TaggedObject(roomID: session.id, category: .boiler))
        session.addTaggedObject(TaggedObject(roomID: session.id, category: .flue))
        session.addTaggedObject(TaggedObject(roomID: session.id, category: .cylinder))
        session.addTaggedObject(TaggedObject(roomID: session.id, category: .radiator))
        session.addVoiceNote(VoiceNote(localFilename: "note.m4a", duration: 10))

        let store = makeStore(session: session)
        XCTAssertEqual(store.lifecycleBadgeStatus, .readyToComplete,
                       "Badge must show readyToComplete when all completion checks pass")
    }

    func test_lifecycleBadgeStatus_showsStoredLifecycleWhenNotReady() {
        var session = makeSession()
        session.visitLifecycle = .capturing

        let store = makeStore(session: session)
        XCTAssertEqual(store.lifecycleBadgeStatus, .capturing,
                       "Badge must reflect stored lifecycle when readiness has not passed")
    }

    // MARK: - Persists modifications to field survey / planning overlay

    func test_update_mutationIsReflectedInSession() {
        let store = makeStore()
        store.update { session in
            let room = ScannedRoom(jobID: session.id, name: "Lounge")
            session.addRoom(room)
        }
        XCTAssertEqual(store.session.rooms.count, 1)
        XCTAssertEqual(store.session.rooms.first?.name, "Lounge")
    }

    func test_update_fieldSurveyReflectsMutation() {
        let store = makeStore()
        XCTAssertEqual(store.fieldSurvey.roomCount, 0)

        store.update { session in
            let room = ScannedRoom(jobID: session.id, name: "Lounge")
            session.addRoom(room)
        }
        XCTAssertEqual(store.fieldSurvey.roomCount, 1)
    }

    func test_addPlanningAnnotation_appearsInPlanningOverlay() {
        let store = makeStore()
        let annotation = PlanningAnnotation(text: "Tight access in hall", kind: .accessNote)
        store.update { $0.addPlanningAnnotation(annotation) }

        let overlay = store.planningOverlay
        XCTAssertEqual(overlay.accessNotes.count, 1)
        XCTAssertEqual(overlay.accessNotes.first?.text, "Tight access in hall")
    }

    func test_removePlanningAnnotation_removedFromOverlay() {
        var session = makeSession()
        let annotation = PlanningAnnotation(text: "Constraint note", kind: .specNote)
        session.addPlanningAnnotation(annotation)

        let store = makeStore(session: session)
        XCTAssertEqual(store.planningReadiness.specNotesCount, 1)

        store.update { $0.removePlanningAnnotation(id: annotation.id) }
        XCTAssertEqual(store.planningReadiness.specNotesCount, 0)
    }

    // MARK: - Backward-compatible decode

    func test_sessionWithoutNewFields_decodesWithDefaults() throws {
        // Simulate a session JSON from before visitLifecycle and planningAnnotations were added.
        let json = """
        {
            "id": "12345678-1234-1234-1234-123456789012",
            "jobReference": "JOB-OLD",
            "propertyAddress": "Old Session Street",
            "engineerName": "",
            "rooms": [],
            "photos": [],
            "voiceNotes": [],
            "taggedObjects": [],
            "issues": [],
            "roomAdjacencies": [],
            "roomPlacements": [],
            "roomScanEvidence": [],
            "externalClearanceScenes": [],
            "installMarkupObjects": [],
            "installMarkupRoutes": [],
            "extractedFacts": [],
            "scanState": "in_progress",
            "reviewState": "pending",
            "syncState": "local_only",
            "handoffState": "not_sent",
            "createdAt": "2024-01-01T10:00:00Z",
            "updatedAt": "2024-01-01T10:00:00Z"
        }
        """
        let data = Data(json.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let session = try decoder.decode(PropertyScanSession.self, from: data)

        // visitLifecycle must default to .draft, not crash
        XCTAssertEqual(session.visitLifecycle, .draft)
        // planningAnnotations must default to empty, not crash
        XCTAssertTrue(session.planningAnnotations.isEmpty)

        // Store must derive readiness without crashing
        let store = makeStore(session: session)
        let readiness = store.visitReadiness
        XCTAssertFalse(readiness.isReady)
        let planning = store.planningReadiness
        XCTAssertEqual(planning.proposedEmittersCount, 0)
    }

    // MARK: - Completion validation

    func test_completionValidation_emptySessionIsNotCompletable() {
        let store = makeStore()
        let result = store.completionValidation
        XCTAssertFalse(result.isCompletable)
        XCTAssertEqual(result.missingItems.count, 7, "All seven items must be listed as missing")
    }

    func test_canCompleteVisit_falseForEmptySession() {
        let store = makeStore()
        XCTAssertFalse(store.canCompleteVisit)
    }

    func test_canCompleteVisit_trueWhenAllItemsPresent() {
        let store = makeStore(session: makeFullyReadySession())
        XCTAssertTrue(store.canCompleteVisit)
    }

    func test_canCompleteVisit_falseWhenAlreadyComplete() {
        var session = makeFullyReadySession()
        session.visitLifecycle = .complete
        let store = makeStore(session: session)
        XCTAssertFalse(store.canCompleteVisit,
                       "canCompleteVisit must be false when the visit is already complete")
    }

    // MARK: - completeVisit

    func test_completeVisit_doesNotCompleteInvalidVisit() {
        let store = makeStore() // empty — not completable
        store.completeVisit()
        XCTAssertNotEqual(store.session.visitLifecycle, .complete)
        XCTAssertNotNil(store.completionError,
                        "completionError must be set when completion is attempted on an invalid visit")
    }

    func test_completeVisit_setsLifecycleToCompleteWhenValid() {
        let store = makeStore(session: makeFullyReadySession())
        store.completeVisit()
        XCTAssertEqual(store.session.visitLifecycle, .complete)
    }

    func test_completeVisit_writesCompletedAt() {
        let store = makeStore(session: makeFullyReadySession())
        let before = Date()
        store.completeVisit()
        let after = Date()
        guard let completedAt = store.session.completedAt else {
            return XCTFail("completedAt must be set after completeVisit()")
        }
        XCTAssertGreaterThanOrEqual(completedAt, before)
        XCTAssertLessThanOrEqual(completedAt, after)
    }

    func test_completeVisit_setsCompletionMethodToManual() {
        let store = makeStore(session: makeFullyReadySession())
        store.completeVisit()
        XCTAssertEqual(store.session.completionMethod, .manual)
    }

    func test_completeVisit_completedByUserIdIsNil() {
        let store = makeStore(session: makeFullyReadySession())
        store.completeVisit()
        XCTAssertNil(store.session.completedByUserId,
                     "completedByUserId must be nil when user identity is not wired")
    }

    func test_completeVisit_isCompletedAfterAction() {
        let store = makeStore(session: makeFullyReadySession())
        XCTAssertFalse(store.isCompleted)
        store.completeVisit()
        XCTAssertTrue(store.isCompleted)
    }

    func test_completeVisit_clearsCompletionError() {
        let store = makeStore()
        store.completeVisit() // invalid — sets error
        XCTAssertNotNil(store.completionError)
        store.clearCompletionError()
        XCTAssertNil(store.completionError)
    }

    func test_isCompleted_locksUpdateMutations() {
        let store = makeStore(session: makeFullyReadySession())
        store.completeVisit()
        XCTAssertTrue(store.isCompleted)

        let roomCountBefore = store.session.rooms.count
        store.update { $0.addRoom(ScannedRoom(jobID: $0.id, name: "New Room")) }
        XCTAssertEqual(store.session.rooms.count, roomCountBefore,
                       "update(_:) must be a no-op on a completed visit")
    }

    func test_completionMetadata_roundTripsViaJson() throws {
        let store = makeStore(session: makeFullyReadySession())
        store.completeVisit()
        XCTAssertTrue(store.isCompleted)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(store.session)
        let decoded = try decoder.decode(PropertyScanSession.self, from: data)

        XCTAssertEqual(decoded.visitLifecycle, .complete)
        XCTAssertNotNil(decoded.completedAt)
        XCTAssertEqual(decoded.completionMethod, .manual)
        XCTAssertNil(decoded.completedByUserId)
    }

    func test_sessionWithoutCompletionFields_decodesWithNilDefaults() throws {
        let json = """
        {
            "id": "12345678-1234-1234-1234-123456789012",
            "jobReference": "JOB-OLD",
            "propertyAddress": "Old Session Street",
            "engineerName": "",
            "rooms": [], "photos": [], "voiceNotes": [], "taggedObjects": [],
            "issues": [], "roomAdjacencies": [], "roomPlacements": [],
            "roomScanEvidence": [], "externalClearanceScenes": [],
            "installMarkupObjects": [], "installMarkupRoutes": [],
            "extractedFacts": [],
            "scanState": "in_progress", "reviewState": "pending",
            "syncState": "local_only", "handoffState": "not_sent",
            "visitLifecycle": "complete",
            "createdAt": "2024-01-01T10:00:00Z",
            "updatedAt": "2024-01-01T10:00:00Z"
        }
        """
        let data = Data(json.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let session = try decoder.decode(PropertyScanSession.self, from: data)

        XCTAssertEqual(session.visitLifecycle, .complete)
        XCTAssertNil(session.completedAt,
                     "completedAt must default to nil for sessions without that key")
        XCTAssertNil(session.completionMethod,
                     "completionMethod must default to nil for sessions without that key")
    }

    // MARK: - Helpers: fully ready session

    private func makeFullyReadySession() -> PropertyScanSession {
        var session = makeSession()
        session.addRoom(ScannedRoom(jobID: session.id, name: "Kitchen"))
        session.addPhoto(TaggedPhoto(filename: "p.jpg"))
        session.addTaggedObject(TaggedObject(roomID: session.id, category: .boiler))
        session.addTaggedObject(TaggedObject(roomID: session.id, category: .flue))
        session.addTaggedObject(TaggedObject(roomID: session.id, category: .cylinder))
        session.addTaggedObject(TaggedObject(roomID: session.id, category: .radiator))
        session.addVoiceNote(VoiceNote(localFilename: "note.m4a", duration: 30))
        return session
    }

    // MARK: - addRoom / removeRoom

    func test_addRoom_appendsRoomAndUpdatesFieldSurvey() {
        let store = makeStore()
        XCTAssertEqual(store.fieldSurvey.roomCount, 0)

        store.addRoom(label: "Kitchen")

        XCTAssertEqual(store.session.rooms.count, 1)
        XCTAssertEqual(store.session.rooms.first?.name, "Kitchen")
        XCTAssertEqual(store.fieldSurvey.roomCount, 1)
    }

    func test_addRoom_updatesReadinessHasRooms() {
        let store = makeStore()
        XCTAssertFalse(store.visitReadiness.hasRooms)

        store.addRoom(label: "Lounge")

        XCTAssertTrue(store.visitReadiness.hasRooms)
    }

    func test_addRoom_usesDefaultLabelWhenEmpty() {
        let store = makeStore()
        store.addRoom(label: "")
        // Empty label → no-op (addRoom guards against empty trimmed label)
        XCTAssertEqual(store.session.rooms.count, 0,
                       "addRoom must be a no-op when the trimmed label is empty")
    }

    func test_addRoom_trimsWhitespace() {
        let store = makeStore()
        store.addRoom(label: "  Hallway  ")
        XCTAssertEqual(store.session.rooms.first?.name, "Hallway")
    }

    func test_addRoom_withFloor() {
        let store = makeStore()
        store.addRoom(label: "Master Bedroom", floor: 1)
        XCTAssertEqual(store.session.rooms.first?.floor, 1)
    }

    func test_removeRoom_removesFromSessionAndUpdatesReadiness() {
        let store = makeStore()
        store.addRoom(label: "Kitchen")
        let roomID = store.session.rooms.first!.id
        XCTAssertTrue(store.visitReadiness.hasRooms)

        store.removeRoom(id: roomID)

        XCTAssertEqual(store.session.rooms.count, 0)
        XCTAssertFalse(store.visitReadiness.hasRooms)
    }

    // MARK: - addPhoto / removePhoto

    func test_addPhoto_appendsPhotoAndUpdatesReadiness() {
        let store = makeStore()
        XCTAssertFalse(store.visitReadiness.hasPhotos)

        store.addPhoto(TaggedPhoto(filename: "test.jpg"))

        XCTAssertEqual(store.session.photos.count, 1)
        XCTAssertTrue(store.visitReadiness.hasPhotos)
    }

    func test_removePhoto_removesPhotoAndUpdatesReadiness() {
        let store = makeStore()
        let photo = TaggedPhoto(filename: "test.jpg")
        store.addPhoto(photo)
        XCTAssertTrue(store.visitReadiness.hasPhotos)

        store.removePhoto(id: photo.id)

        XCTAssertEqual(store.session.photos.count, 0)
        XCTAssertFalse(store.visitReadiness.hasPhotos)
    }

    // MARK: - addKeyObject / removeKeyObject

    func test_addKeyObject_boilerUpdatesReadiness() {
        let store = makeStore()
        XCTAssertFalse(store.visitReadiness.hasBoiler)

        store.addKeyObject(category: .boiler)

        XCTAssertTrue(store.visitReadiness.hasBoiler)
    }

    func test_addKeyObject_fluUpdatesReadiness() {
        let store = makeStore()
        XCTAssertFalse(store.visitReadiness.hasFlue)

        store.addKeyObject(category: .flue)

        XCTAssertTrue(store.visitReadiness.hasFlue)
    }

    func test_addKeyObject_storedAtSessionLevel() {
        let store = makeStore()
        store.addKeyObject(category: .boiler, label: "Main Boiler")

        let obj = store.session.taggedObjects.first
        XCTAssertNotNil(obj)
        XCTAssertEqual(obj?.category, .boiler)
    }

    func test_addKeyObject_labelPreserved() {
        let store = makeStore()
        store.addKeyObject(category: .boiler, label: "Vaillant combi")

        XCTAssertEqual(store.session.taggedObjects.first?.label, "Vaillant combi")
    }

    func test_addKeyObject_notePreserved() {
        let store = makeStore()
        store.addKeyObject(category: .flue, note: "Rear-exit flue")

        XCTAssertEqual(store.session.taggedObjects.first?.notes, "Rear-exit flue")
    }

    func test_addKeyObject_multipleBoilersAllowed() {
        let store = makeStore()
        store.addKeyObject(category: .boiler)
        store.addKeyObject(category: .boiler, label: "Second boiler")

        let boilers = store.session.taggedObjects.filter { $0.category == .boiler }
        XCTAssertEqual(boilers.count, 2, "Multiple boilers must be allowed")
    }

    func test_removeKeyObject_removesFromSessionAndLosesReadiness() {
        let store = makeStore()
        store.addKeyObject(category: .boiler)
        let objectID = store.session.taggedObjects.first!.id
        XCTAssertTrue(store.visitReadiness.hasBoiler)

        store.removeKeyObject(id: objectID)

        XCTAssertEqual(store.session.taggedObjects.count, 0)
        XCTAssertFalse(store.visitReadiness.hasBoiler)
    }

    func test_removeKeyObject_flueReadinessFallsAfterRemoval() {
        let store = makeStore()
        store.addKeyObject(category: .flue)
        let objectID = store.session.taggedObjects.first!.id

        store.removeKeyObject(id: objectID)

        XCTAssertFalse(store.visitReadiness.hasFlue)
    }

    // MARK: - addTextNote / removeTextNote

    func test_addTextNote_updatesNotesReadiness() {
        let store = makeStore()
        XCTAssertFalse(store.visitReadiness.hasNotes)

        store.addTextNote("Boiler pressure low, advised customer.")

        XCTAssertTrue(store.visitReadiness.hasNotes)
    }

    func test_addTextNote_storedAsVoiceNote() {
        let store = makeStore()
        store.addTextNote("Boiler in utility room")

        XCTAssertEqual(store.session.voiceNotes.count, 1)
        let note = store.session.voiceNotes.first
        XCTAssertEqual(note?.caption, "Boiler in utility room")
        XCTAssertEqual(note?.transcript, "Boiler in utility room")
        XCTAssertEqual(note?.transcriptStatus, .completed)
        XCTAssertEqual(note?.localFilename, "")
    }

    func test_addTextNote_emptyTextIsNoOp() {
        let store = makeStore()
        store.addTextNote("   ")
        XCTAssertEqual(store.session.voiceNotes.count, 0,
                       "addTextNote must be a no-op when the trimmed text is empty")
    }

    func test_addTextNote_trimsWhitespace() {
        let store = makeStore()
        store.addTextNote("  Gas safe check done  ")
        XCTAssertEqual(store.session.voiceNotes.first?.caption, "Gas safe check done")
    }

    func test_removeTextNote_removesNoteAndLosesReadiness() {
        let store = makeStore()
        store.addTextNote("Customer asked about radiators")
        let noteID = store.session.voiceNotes.first!.id
        XCTAssertTrue(store.visitReadiness.hasNotes)

        store.removeTextNote(id: noteID)

        XCTAssertEqual(store.session.voiceNotes.count, 0)
        XCTAssertFalse(store.visitReadiness.hasNotes)
    }

    // MARK: - Completion lock blocks all new mutations

    func test_completionLock_blocksAddRoom() {
        let store = makeStore(session: makeFullyReadySession())
        store.completeVisit()
        XCTAssertTrue(store.isCompleted)

        store.addRoom(label: "New Room")

        XCTAssertEqual(store.session.rooms.count, 1,
                       "addRoom must be a no-op on a completed visit")
    }

    func test_completionLock_blocksAddPhoto() {
        let store = makeStore(session: makeFullyReadySession())
        store.completeVisit()
        let photosCountBefore = store.session.photos.count

        store.addPhoto(TaggedPhoto(filename: "new.jpg"))

        XCTAssertEqual(store.session.photos.count, photosCountBefore,
                       "addPhoto must be a no-op on a completed visit")
    }

    func test_completionLock_blocksAddKeyObject() {
        let store = makeStore(session: makeFullyReadySession())
        store.completeVisit()
        let objectsCountBefore = store.session.taggedObjects.count

        store.addKeyObject(category: .boiler)

        XCTAssertEqual(store.session.taggedObjects.count, objectsCountBefore,
                       "addKeyObject must be a no-op on a completed visit")
    }

    func test_completionLock_blocksAddTextNote() {
        let store = makeStore(session: makeFullyReadySession())
        store.completeVisit()
        let notesCountBefore = store.session.voiceNotes.count

        store.addTextNote("Late note")

        XCTAssertEqual(store.session.voiceNotes.count, notesCountBefore,
                       "addTextNote must be a no-op on a completed visit")
    }

    func test_completionLock_blocksRemoveRoom() {
        let store = makeStore(session: makeFullyReadySession())
        store.completeVisit()
        let roomID = store.session.rooms.first!.id
        let roomsCountBefore = store.session.rooms.count

        store.removeRoom(id: roomID)

        XCTAssertEqual(store.session.rooms.count, roomsCountBefore,
                       "removeRoom must be a no-op on a completed visit")
    }
}
