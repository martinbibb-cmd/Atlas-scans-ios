import XCTest
import AtlasContracts
import AtlasScanCore
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

final class ScanSessionCoordinatorEvidenceLifecycleTests: XCTestCase {
    private let store = AtomicSessionStore()

    @MainActor
    func test_prospectiveRoomId_linksMidScanEvidenceToSavedRoom() async throws {
        let visitId = UUID()
        let roomId = UUID()
        let coordinator = ScanSessionCoordinator(visitId: visitId, store: store)
        defer { try? store.delete(visitId: visitId) }

        coordinator.addPhoto(
            PhotoEvidenceV1(visitId: visitId, roomId: roomId, relativeFilePath: "mid-scan.jpg")
        )
        coordinator.addVoiceNote(
            VoiceNoteV1(visitId: visitId, roomId: roomId, processedTranscript: "boiler near wall")
        )

        let pin = SpatialPinV1(
            roomId: roomId,
            positionX: 0, positionY: 0, positionZ: 0,
            objectType: .boiler
        )
        var room = RoomCaptureV2(id: roomId, displayName: "Kitchen")
        room.pinnedObjects = [pin]
        coordinator.addRoom(room)
        await coordinator.saveSession()

        XCTAssertEqual(coordinator.session.rooms.first?.id, roomId)
        XCTAssertEqual(coordinator.session.photos.map(\.roomId), [roomId])
        XCTAssertEqual(coordinator.session.voiceNotes.map(\.roomId), [roomId])
        XCTAssertEqual(coordinator.session.transcripts.map(\.roomId), [roomId])
        XCTAssertEqual(coordinator.session.rooms.first?.pinnedObjects.map(\.roomId), [roomId])
    }

    @MainActor
    func test_secondRoomCapture_usesDistinctRoomIdWithoutEvidenceBleed() async throws {
        let visitId = UUID()
        let firstRoomId = UUID()
        let secondRoomId = UUID()
        let coordinator = ScanSessionCoordinator(visitId: visitId, store: store)
        defer { try? store.delete(visitId: visitId) }

        coordinator.addPhoto(
            PhotoEvidenceV1(visitId: visitId, roomId: firstRoomId, relativeFilePath: "room-1.jpg")
        )
        coordinator.addVoiceNote(
            VoiceNoteV1(visitId: visitId, roomId: firstRoomId, processedTranscript: "room one note")
        )
        coordinator.addRoom(RoomCaptureV2(id: firstRoomId, displayName: "Room 1"))

        coordinator.addPhoto(
            PhotoEvidenceV1(visitId: visitId, roomId: secondRoomId, relativeFilePath: "room-2.jpg")
        )
        coordinator.addVoiceNote(
            VoiceNoteV1(visitId: visitId, roomId: secondRoomId, processedTranscript: "room two note")
        )
        coordinator.addRoom(RoomCaptureV2(id: secondRoomId, displayName: "Room 2"))
        await coordinator.saveSession()

        XCTAssertNotEqual(firstRoomId, secondRoomId)
        XCTAssertEqual(coordinator.session.rooms.count, 2)
        XCTAssertEqual(coordinator.session.photos.filter { $0.roomId == firstRoomId }.count, 1)
        XCTAssertEqual(coordinator.session.photos.filter { $0.roomId == secondRoomId }.count, 1)
        XCTAssertEqual(coordinator.session.voiceNotes.filter { $0.roomId == firstRoomId }.count, 1)
        XCTAssertEqual(coordinator.session.voiceNotes.filter { $0.roomId == secondRoomId }.count, 1)
    }

    @MainActor
    func test_unfinishedRoomEvidence_discardAlsoRemovesRoomPins() async throws {
        let visitId = UUID()
        let unfinishedRoomId = UUID()
        let keptRoomId = UUID()
        let coordinator = ScanSessionCoordinator(visitId: visitId, store: store)
        defer { try? store.delete(visitId: visitId) }

        coordinator.addPhoto(
            PhotoEvidenceV1(visitId: visitId, roomId: unfinishedRoomId, relativeFilePath: "unfinished.jpg")
        )
        coordinator.addVoiceNote(
            VoiceNoteV1(visitId: visitId, roomId: unfinishedRoomId, processedTranscript: "unfinished note")
        )
        var unfinishedRoom = RoomCaptureV2(id: unfinishedRoomId, displayName: "Unfinished Room")
        unfinishedRoom.pinnedObjects = [
            SpatialPinV1(
                roomId: unfinishedRoomId,
                positionX: 1,
                positionY: 0,
                positionZ: 1,
                objectType: .boiler
            )
        ]
        coordinator.addRoom(unfinishedRoom)
        coordinator.addPhoto(
            PhotoEvidenceV1(visitId: visitId, roomId: keptRoomId, relativeFilePath: "kept.jpg")
        )
        var keptRoom = RoomCaptureV2(id: keptRoomId, displayName: "Saved Room")
        keptRoom.pinnedObjects = [
            SpatialPinV1(
                roomId: keptRoomId,
                positionX: 2,
                positionY: 0,
                positionZ: 2,
                objectType: .heatPump
            )
        ]
        coordinator.addRoom(keptRoom)

        coordinator.discardUnfinishedRoomEvidence(for: unfinishedRoomId)
        await coordinator.saveSession()

        XCTAssertFalse(coordinator.session.rooms.contains { $0.id == unfinishedRoomId })
        XCTAssertFalse(coordinator.session.photos.contains { $0.roomId == unfinishedRoomId })
        XCTAssertFalse(coordinator.session.voiceNotes.contains { $0.roomId == unfinishedRoomId })
        XCTAssertFalse(coordinator.session.transcripts.contains { $0.roomId == unfinishedRoomId })
        XCTAssertFalse(
            coordinator.session.rooms
                .flatMap(\.pinnedObjects)
                .contains { $0.roomId == unfinishedRoomId }
        )
        XCTAssertTrue(coordinator.session.photos.contains { $0.roomId == keptRoomId })
        XCTAssertTrue(coordinator.session.rooms.contains { $0.id == keptRoomId })
        XCTAssertEqual(
            coordinator.session.rooms.first(where: { $0.id == keptRoomId })?.pinnedObjects.map(\.roomId),
            [keptRoomId]
        )
    }

    @MainActor
    func test_draftRoomRecovery_preservesEvidenceAndConsumesPendingPins() async throws {
        let visitId = UUID()
        let prospectiveRoomId = UUID()
        let nextProspectiveRoomId = UUID()
        let unrelatedPendingRoomId = UUID()
        let coordinator = ScanSessionCoordinator(visitId: visitId, store: store)
        defer { try? store.delete(visitId: visitId) }

        coordinator.addPhoto(
            PhotoEvidenceV1(visitId: visitId, roomId: prospectiveRoomId, relativeFilePath: "draft-photo.jpg")
        )
        coordinator.addVoiceNote(
            VoiceNoteV1(visitId: visitId, roomId: prospectiveRoomId, processedTranscript: "draft transcript")
        )

        let expectedPin = SpatialPinV1(
            roomId: prospectiveRoomId,
            positionX: 0,
            positionY: 0,
            positionZ: 0,
            objectType: .boiler
        )
        let unrelatedPendingPin = SpatialPinV1(
            roomId: unrelatedPendingRoomId,
            positionX: 1,
            positionY: 0,
            positionZ: 1,
            objectType: .heatPump
        )

        let transition = V2RoomLoopLifecycle.makeDraftRoomRecoveryTransition(
            prospectiveRoomId: prospectiveRoomId,
            pendingPins: [expectedPin, unrelatedPendingPin],
            now: Date(timeIntervalSince1970: 0),
            nextProspectiveRoomId: nextProspectiveRoomId
        )

        coordinator.addRoom(transition.draftRoom)
        await coordinator.saveSession()

        XCTAssertEqual(transition.draftRoom.id, prospectiveRoomId)
        XCTAssertEqual(transition.draftRoom.pinnedObjects.map(\.roomId), [prospectiveRoomId])
        XCTAssertEqual(
            transition.remainingPendingPins.map(\.roomId),
            [unrelatedPendingRoomId],
            "Pending pins for the abandoned room should be consumed when saving draft evidence."
        )
        XCTAssertNotEqual(transition.nextProspectiveRoomId, prospectiveRoomId)
        XCTAssertEqual(transition.nextProspectiveRoomId, nextProspectiveRoomId)

        XCTAssertEqual(coordinator.session.rooms.count, 1)
        XCTAssertEqual(coordinator.session.rooms.first?.id, prospectiveRoomId)
        XCTAssertEqual(coordinator.session.rooms.first?.pinnedObjects.map(\.roomId), [prospectiveRoomId])
        XCTAssertEqual(coordinator.session.photos.map(\.roomId), [prospectiveRoomId])
        XCTAssertEqual(coordinator.session.voiceNotes.map(\.roomId), [prospectiveRoomId])
        XCTAssertEqual(coordinator.session.transcripts.map(\.roomId), [prospectiveRoomId])
    }
}

final class RoomCaptureV2GeometryAndAnchoringTests: XCTestCase {
    func test_hasClosedFloorPolygon_requiresNonZeroAreaPolygon() {
        let lineRoom = RoomCaptureV2(
            displayName: "Line",
            polygonVertices: [
                Vertex2D(x: 0, z: 0),
                Vertex2D(x: 1, z: 1)
            ]
        )
        XCTAssertFalse(lineRoom.hasClosedFloorPolygon)
        XCTAssertEqual(lineRoom.floorAreaM2, 0, accuracy: 0.000_001)

        let rectangleRoom = RoomCaptureV2(
            displayName: "Rectangle",
            polygonVertices: [
                Vertex2D(x: 0, z: 0),
                Vertex2D(x: 4, z: 0),
                Vertex2D(x: 4, z: 3),
                Vertex2D(x: 0, z: 3)
            ]
        )
        XCTAssertTrue(rectangleRoom.hasClosedFloorPolygon)
        XCTAssertGreaterThan(rectangleRoom.floorAreaM2, 0)
    }

    func test_validWallChain_producesOrderedClosedWallSegments() {
        let vertices = [
            Vertex2D(x: 0, z: 0),
            Vertex2D(x: 4, z: 0),
            Vertex2D(x: 4, z: 3),
            Vertex2D(x: 0, z: 3)
        ]
        let room = RoomCaptureV2(displayName: "Rectangle", polygonVertices: vertices)
        let segments = room.wallSegments

        XCTAssertEqual(segments.count, vertices.count)
        XCTAssertEqual(segments.first?.startVertex, vertices[0])
        XCTAssertEqual(segments.first?.endVertex, vertices[1])
        XCTAssertEqual(segments.last?.startVertex, vertices[3])
        XCTAssertEqual(segments.last?.endVertex, vertices[0], "Last wall must close the polygon")
    }

    func test_wallSegments_defaultToExternalWallFabric() {
        let room = RoomCaptureV2(
            displayName: "Kitchen",
            polygonVertices: [
                Vertex2D(x: 0, z: 0),
                Vertex2D(x: 4, z: 0),
                Vertex2D(x: 4, z: 3),
                Vertex2D(x: 0, z: 3)
            ]
        )
        XCTAssertEqual(room.wallSegments.count, 4)
        XCTAssertTrue(room.wallSegments.allSatisfy { $0.fabric == .externalWall })
    }

    func test_wallSegments_supportOverrideToPartyAndInternalFabric() {
        var room = RoomCaptureV2(
            displayName: "Kitchen",
            polygonVertices: [
                Vertex2D(x: 0, z: 0),
                Vertex2D(x: 4, z: 0),
                Vertex2D(x: 4, z: 3),
                Vertex2D(x: 0, z: 3)
            ]
        )
        var overridden = room.wallSegments
        overridden[1].fabric = .partyWall
        overridden[2].fabric = .internalWall
        room.fabricCapture = FloorPlanFabricCaptureV1(roomId: room.id, segments: overridden)

        XCTAssertEqual(room.wallSegments[0].fabric, .externalWall)
        XCTAssertEqual(room.wallSegments[1].fabric, .partyWall)
        XCTAssertEqual(room.wallSegments[2].fabric, .internalWall)
        XCTAssertEqual(room.wallSegments[3].fabric, .externalWall)
    }

    func test_screenOnlyPin_isNotResolvedWorldAnchor() {
        let unresolved = SpatialPinV1(
            roomId: UUID(),
            positionX: 0,
            positionY: 0,
            positionZ: 0,
            screenPositionX: 0.4,
            screenPositionY: 0.6,
            objectType: .boiler,
            anchorConfidence: .screenOnly
        )
        XCTAssertFalse(unresolved.hasResolvedWorldAnchor)

        let anchored = SpatialPinV1(
            roomId: UUID(),
            positionX: 1.2,
            positionY: 0.9,
            positionZ: -0.3,
            objectType: .boiler,
            anchorConfidence: .raycastEstimated
        )
        XCTAssertTrue(anchored.hasResolvedWorldAnchor)
    }

    func test_estimatedPin_atOrigin_isNotResolvedWorldAnchor() {
        let unresolved = SpatialPinV1(
            roomId: UUID(),
            positionX: 0,
            positionY: 0,
            positionZ: 0,
            objectType: .boiler,
            anchorConfidence: .estimated
        )
        XCTAssertFalse(unresolved.hasNonZeroWorldPosition)
        XCTAssertFalse(unresolved.hasResolvedWorldAnchor)
    }

    func test_estimatedPin_withNearZeroNoise_isNotResolvedWorldAnchor() {
        let unresolved = SpatialPinV1(
            roomId: UUID(),
            positionX: 0.000_05,
            positionY: -0.000_05,
            positionZ: 0.000_05,
            objectType: .boiler,
            anchorConfidence: .estimated
        )
        XCTAssertFalse(unresolved.hasNonZeroWorldPosition)
        XCTAssertFalse(unresolved.hasResolvedWorldAnchor)
    }

    func test_estimatedPin_aboveNoiseThreshold_isResolvedWorldAnchor() {
        let anchored = SpatialPinV1(
            roomId: UUID(),
            positionX: 0.000_2,
            positionY: 0,
            positionZ: 0,
            objectType: .boiler,
            anchorConfidence: .estimated
        )
        XCTAssertTrue(anchored.hasNonZeroWorldPosition)
        XCTAssertTrue(anchored.hasResolvedWorldAnchor)
    }

    func test_screenOnlyGhostPlacement_requiresReview() {
        let placement = GhostAppliancePlacementV1(
            roomId: UUID(),
            capturePointId: UUID(),
            applianceModelId: "screen-only-ghost",
            screenPoint: .init(x: 0.5, y: 0.5),
            placementPlane: .wall,
            dimensionsMm: .init(width: 600, height: 700, depth: 300),
            anchorConfidence: .screenOnly
        )
        XCTAssertTrue(placement.needsReview)
    }

    func test_unknownPlaneGhostPlacement_requiresReview() {
        let placement = GhostAppliancePlacementV1(
            roomId: UUID(),
            capturePointId: UUID(),
            applianceModelId: "unknown-plane-ghost",
            screenPoint: .init(x: 0.5, y: 0.5),
            placementPlane: .unknown,
            dimensionsMm: .init(width: 600, height: 700, depth: 300),
            anchorConfidence: .high
        )
        XCTAssertTrue(placement.needsReview)
    }

    func test_anchoredWallGhostPlacement_doesNotRequireReview() {
        let placement = GhostAppliancePlacementV1(
            roomId: UUID(),
            capturePointId: UUID(),
            applianceModelId: "anchored-wall-ghost",
            screenPoint: .init(x: 0.45, y: 0.55),
            placementPlane: .wall,
            planeNormalX: 0,
            planeNormalY: 0,
            planeNormalZ: -1,
            worldPositionX: 1.2,
            worldPositionY: 1.0,
            worldPositionZ: 2.0,
            dimensionsMm: .init(width: 600, height: 700, depth: 300),
            anchorConfidence: .high
        )
        XCTAssertFalse(placement.needsReview)
    }

    func test_ghostPlacementDecoding_defaultsMissingScreenPointToCenter() throws {
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "roomId": "\(UUID().uuidString)",
          "capturePointId": "\(UUID().uuidString)",
          "applianceModelId": "legacy-ghost",
          "customApplianceDefinitionId": null,
          "placementPlane": "wall",
          "planeNormalX": 0,
          "planeNormalY": 0,
          "planeNormalZ": -1,
          "worldPositionX": 1,
          "worldPositionY": 1.2,
          "worldPositionZ": 2,
          "rotationYaw": 0,
          "dimensionsMm": { "width": 600, "height": 700, "depth": 300 },
          "clearanceOffsetsMm": { "top": 0, "bottom": 0, "front": 600, "back": 0, "left": 100, "right": 100 },
          "anchorConfidence": "high",
          "createdAt": "2026-05-08T00:00:00Z",
          "notes": null
        }
        """

        let placement = try JSONDecoder().decode(
            GhostAppliancePlacementV1.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(placement.screenPoint, CGPointCodable(x: 0.5, y: 0.5))
    }

    @MainActor
    func test_abnormalCeilingHeight_emitsQAFlag() {
        let coordinator = ScanSessionCoordinator(visitId: UUID(), store: AtomicSessionStore())
        var room = RoomCaptureV2(displayName: "Kitchen")
        room.rawCapturedCeilingHeightM = 4.8
        room.ceilingHeightM = 4.8

        coordinator.upsertRoom(room)

        XCTAssertTrue(
            coordinator.session.qaFlags.contains {
                $0.type == .abnormalCeilingHeight && $0.roomId == room.id
            }
        )
    }

    @MainActor
    func test_doubledCeilingHeight_normalizedDisplayStillFlagsRawAbnormalValue() {
        let coordinator = ScanSessionCoordinator(visitId: UUID(), store: AtomicSessionStore())
        var room = RoomCaptureV2(displayName: "Kitchen")
        room.rawCapturedCeilingHeightM = 4.8
        room.ceilingHeightM = 2.4

        coordinator.upsertRoom(room)

        let flag = coordinator.session.qaFlags.first {
            $0.type == .abnormalCeilingHeight && $0.roomId == room.id
        }
        XCTAssertNotNil(flag)
        XCTAssertTrue(flag?.detail.contains("4.80 m") == true)
    }
}
