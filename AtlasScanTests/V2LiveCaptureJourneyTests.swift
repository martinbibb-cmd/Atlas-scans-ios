/// V2LiveCaptureJourneyTests — End-to-end smoke test for the V2 live scan lifecycle.
///
/// Covers:
///   - Start visit → create prospective room → create capture point
///   - Attach pin / photo / voice to the same capturePointId
///   - Finish room → saved room exists on coordinator
///   - All evidence references the same roomId
///   - All evidence references the same capturePointId
///   - Start next room → new prospectiveRoomId is different

import XCTest
import AtlasScanCore
@testable import AtlasScan

@MainActor
final class V2LiveCaptureJourneyTests: XCTestCase {

    private var store: AtomicSessionStore!
    private var coordinator: ScanSessionCoordinator!
    private var visitId: UUID!

    override func setUp() {
        super.setUp()
        visitId = UUID()
        store = AtomicSessionStore()
        coordinator = ScanSessionCoordinator(visitId: visitId, store: store)
    }

    override func tearDown() {
        try? store.delete(visitId: visitId)
        coordinator = nil
        store = nil
        super.tearDown()
    }

    // MARK: - Smoke test

    func test_fullScanJourney_endToEnd() async throws {
        // 1. Start visit — session is empty.
        XCTAssertTrue(coordinator.session.rooms.isEmpty)
        XCTAssertTrue(coordinator.session.photos.isEmpty)
        XCTAssertTrue(coordinator.session.voiceNotes.isEmpty)

        // 2. Create a prospective room ID shared with all evidence.
        let prospectiveRoomId = UUID()

        // 3. Create a capture point at view-centre (simulates reticle tap).
        let capturePoint = LiveCapturePointV1(
            roomId: prospectiveRoomId,
            screenPoint: CGPointCodable(x: 0.5, y: 0.5),
            worldPosition: SIMD3<Double>(1.5, 0.0, 2.5),
            anchorConfidence: .worldLocked,
            hitNormal: SIMD3<Double>(0, 0, -1),
            anchorId: UUID(),
            worldTransform: WorldTransformV1(elements: [1, 0, 0, 0,
                                                        0, 1, 0, 0,
                                                        0, 0, 1, 0,
                                                        1.5, 0, 2.5, 1])
        )

        // 4. Attach a pin, photo, and voice note — all referencing the same capture point.
        let pin = SpatialPinV1(
            roomId: prospectiveRoomId,
            capturePointId: capturePoint.id,
            anchorId: capturePoint.anchorId,
            worldTransform: capturePoint.worldTransform,
            positionX: 1.5,
            positionY: 0.0,
            positionZ: 2.5,
            objectType: .boiler,
            anchorConfidence: .worldLocked
        )

        let photo = PhotoEvidenceV1(
            visitId: visitId,
            roomId: prospectiveRoomId,
            capturePointId: capturePoint.id,
            relativeFilePath: "photo_boiler.jpg"
        )

        let voiceNote = VoiceNoteV1(
            visitId: visitId,
            roomId: prospectiveRoomId,
            capturePointId: capturePoint.id,
            processedTranscript: "Worcester Combi 30i, installed 2018"
        )

        let customDefinition = CustomApplianceDefinitionV1(
            id: "custom-wall-boiler",
            brand: "Custom",
            modelName: "Wall Boiler",
            applianceType: "boiler",
            dimensionsMm: .init(width: 640, height: 780, depth: 320),
            clearanceOffsetsMm: .init(top: 150, front: 600, back: 40, left: 75, right: 75)
        )
        let ghostPlacement = GhostAppliancePlacementV1(
            roomId: prospectiveRoomId,
            capturePointId: capturePoint.id,
            applianceModelId: customDefinition.id,
            customApplianceDefinitionId: customDefinition.id,
            screenPoint: capturePoint.screenPoint,
            placementPlane: .wall,
            planeNormalX: 0,
            planeNormalY: 0,
            planeNormalZ: -1,
            worldPositionX: 1.5,
            worldPositionY: 1.0,
            worldPositionZ: 2.66,
            rotationYaw: 15,
            dimensionsMm: customDefinition.dimensionsMm,
            clearanceOffsetsMm: customDefinition.clearanceOffsetsMm,
            anchorConfidence: .raycastEstimated,
            notes: "Custom appliance"
        )

        // addVoiceNote is documented to create a matching ProcessedTranscriptV1 in the
        // session as a synchronous side-effect (see ScanSessionCoordinator.addVoiceNote).
        coordinator.addPhoto(photo)
        coordinator.addVoiceNote(voiceNote)

        // 5. Finish room — bundle all pending evidence into a RoomCaptureV2.
        var room = RoomCaptureV2(id: prospectiveRoomId, displayName: "Kitchen")
        room.pinnedObjects = [pin]
        room.ghostAppliancePlacements = [ghostPlacement]
        room.customApplianceDefinitions = [customDefinition]
        coordinator.addRoom(room)
        await coordinator.saveSession()

        // 6. Assert saved room exists on coordinator.
        let savedRoom = coordinator.room(withId: prospectiveRoomId)
        XCTAssertNotNil(savedRoom, "Room should be retrievable by its prospective UUID after save.")
        XCTAssertEqual(savedRoom?.displayName, "Kitchen")

        // 7. Assert all evidence references the same roomId.
        let roomPhotos     = coordinator.session.photos.filter { $0.roomId == prospectiveRoomId }
        let roomVoices     = coordinator.session.voiceNotes.filter { $0.roomId == prospectiveRoomId }
        let roomPins       = savedRoom?.pinnedObjects ?? []
        let roomGhosts     = savedRoom?.ghostAppliancePlacements ?? []
        let roomTranscripts = coordinator.session.transcripts.filter { $0.roomId == prospectiveRoomId }

        XCTAssertEqual(roomPhotos.count, 1, "One photo should be associated with the room.")
        XCTAssertEqual(roomVoices.count, 1, "One voice note should be associated with the room.")
        XCTAssertEqual(roomPins.count, 1, "One pin should be stored on the room.")
        XCTAssertEqual(roomGhosts.count, 1, "One ghost appliance should be stored on the room.")
        XCTAssertEqual(roomTranscripts.count, 1, "Coordinator should have created a transcript for the voice note.")

        // 8. Assert all evidence references the same capturePointId.
        XCTAssertEqual(roomPhotos.first?.capturePointId, capturePoint.id,
                       "Photo capturePointId must match the capture point used.")
        XCTAssertEqual(roomVoices.first?.capturePointId, capturePoint.id,
                       "Voice note capturePointId must match the capture point used.")
        XCTAssertEqual(roomPins.first?.capturePointId, capturePoint.id,
                       "Pin capturePointId must match the capture point used.")
        XCTAssertEqual(roomPins.first?.anchorId, capturePoint.anchorId,
                       "Pin anchorId must be preserved for anchored evidence.")
        XCTAssertEqual(roomPins.first?.worldTransform, capturePoint.worldTransform,
                       "Pin world transform must be preserved for anchored evidence.")
        XCTAssertEqual(roomGhosts.first?.capturePointId, capturePoint.id,
                       "Ghost placement capturePointId must match the capture point used.")
        XCTAssertEqual(roomTranscripts.first?.capturePointId, capturePoint.id,
                       "Transcript capturePointId must match the capture point used.")
        XCTAssertEqual(roomGhosts.first?.roomId, prospectiveRoomId,
                       "Ghost placement roomId must match the active room.")
        XCTAssertEqual(roomGhosts.first?.dimensionsMm, customDefinition.dimensionsMm,
                       "Custom appliance dimensions must be preserved.")
        XCTAssertEqual(roomGhosts.first?.screenPoint, capturePoint.screenPoint,
                       "Ghost placement should retain the tapped screen point.")

        // 9. Start next room — new prospectiveRoomId must differ.
        let nextProspectiveRoomId = UUID()
        XCTAssertNotEqual(nextProspectiveRoomId, prospectiveRoomId,
                          "Each room's prospectiveRoomId must be unique.")

        // 10. A second room can be saved independently without contaminating the first.
        var room2 = RoomCaptureV2(id: nextProspectiveRoomId, displayName: "Bathroom")
        coordinator.addRoom(room2)
        await coordinator.saveSession()

        XCTAssertEqual(coordinator.session.rooms.count, 2)
        let ids = coordinator.session.rooms.map(\.id)
        XCTAssertTrue(Set(ids).count == 2, "Both rooms must have distinct IDs.")
        XCTAssertTrue(coordinator.session.photos.filter { $0.roomId == nextProspectiveRoomId }.isEmpty,
                      "Second room must not inherit evidence from the first room.")
    }

    // MARK: - Draft recovery

    func test_draftRecovery_evidenceAttachedToCorrectRoom() async throws {
        let prospectiveRoomId = UUID()
        let nextId = UUID()

        let pin = SpatialPinV1(
            roomId: prospectiveRoomId,
            positionX: 0, positionY: 0, positionZ: 0,
            objectType: .hotWaterCylinder,
            anchorConfidence: .screenOnly
        )
        let ghostPlacement = GhostAppliancePlacementV1(
            roomId: prospectiveRoomId,
            capturePointId: UUID(),
            applianceModelId: "custom-draft-ghost",
            screenPoint: .init(x: 0.5, y: 0.5),
            placementPlane: .unknown,
            dimensionsMm: .init(width: 600, height: 700, depth: 300),
            anchorConfidence: .screenOnly
        )
        let photo = PhotoEvidenceV1(visitId: visitId, roomId: prospectiveRoomId, relativeFilePath: "draft.jpg")
        coordinator.addPhoto(photo)

        let transition = V2RoomLoopLifecycle.makeDraftRoomRecoveryTransition(
            prospectiveRoomId: prospectiveRoomId,
            pendingPins: [pin],
            pendingGhostPlacements: [ghostPlacement],
            nextProspectiveRoomId: nextId
        )

        coordinator.addRoom(transition.draftRoom)
        await coordinator.saveSession()

        XCTAssertEqual(coordinator.session.rooms.count, 1)
        XCTAssertEqual(coordinator.session.rooms.first?.id, prospectiveRoomId)
        XCTAssertEqual(coordinator.session.photos.filter { $0.roomId == prospectiveRoomId }.count, 1)
        XCTAssertEqual(coordinator.session.rooms.first?.ghostAppliancePlacements.map(\.roomId), [prospectiveRoomId])
        XCTAssertNotEqual(transition.nextProspectiveRoomId, prospectiveRoomId)
    }

    // MARK: - Discard recovery

    func test_discardRecovery_removesOnlyDiscardedRoomEvidence() async throws {
        let keptRoomId = UUID()
        let discardedRoomId = UUID()
        let keptGhost = GhostAppliancePlacementV1(
            roomId: keptRoomId,
            capturePointId: UUID(),
            applianceModelId: "kept-ghost",
            screenPoint: .init(x: 0.4, y: 0.4),
            placementPlane: .floor,
            worldPositionX: 1,
            worldPositionY: 0.35,
            worldPositionZ: 1,
            dimensionsMm: .init(width: 600, height: 700, depth: 300),
            anchorConfidence: .high
        )
        let discardedGhost = GhostAppliancePlacementV1(
            roomId: discardedRoomId,
            capturePointId: UUID(),
            applianceModelId: "discard-ghost",
            screenPoint: .init(x: 0.6, y: 0.6),
            placementPlane: .unknown,
            dimensionsMm: .init(width: 500, height: 600, depth: 250),
            anchorConfidence: .screenOnly
        )

        coordinator.addPhoto(PhotoEvidenceV1(visitId: visitId, roomId: keptRoomId, relativeFilePath: "kept.jpg"))
        coordinator.addPhoto(PhotoEvidenceV1(visitId: visitId, roomId: discardedRoomId, relativeFilePath: "discard.jpg"))
        var keptRoom = RoomCaptureV2(id: keptRoomId, displayName: "Kept Room")
        keptRoom.ghostAppliancePlacements = [keptGhost]
        coordinator.addRoom(keptRoom)
        var discardedRoom = RoomCaptureV2(id: discardedRoomId, displayName: "Discarded Room")
        discardedRoom.ghostAppliancePlacements = [discardedGhost]
        coordinator.addRoom(discardedRoom)

        coordinator.discardUnfinishedRoomEvidence(for: discardedRoomId)

        XCTAssertTrue(coordinator.session.photos.filter { $0.roomId == discardedRoomId }.isEmpty,
                      "Discarded room evidence must be removed.")
        XCTAssertEqual(coordinator.session.photos.filter { $0.roomId == keptRoomId }.count, 1,
                       "Evidence for other rooms must not be affected by discard.")
        XCTAssertFalse(coordinator.session.rooms.contains { $0.id == discardedRoomId },
                       "Discarded room ghost placements should be removed with the room.")
        XCTAssertEqual(coordinator.session.rooms.first(where: { $0.id == keptRoomId })?.ghostAppliancePlacements.count, 1,
                       "Ghost placements for other rooms must be preserved.")
    }

    // MARK: - deleteEvidenceItem

    func test_deleteEvidenceItem_removesPhotoFromSession() async throws {
        let roomId = UUID()
        let photo = PhotoEvidenceV1(visitId: visitId, roomId: roomId, relativeFilePath: "test.jpg")
        coordinator.addPhoto(photo)
        XCTAssertEqual(coordinator.session.photos.count, 1)

        let item = RecentCaptureItemV1.from(photo: photo)
        coordinator.deleteEvidenceItem(item)

        XCTAssertTrue(coordinator.session.photos.isEmpty, "Photo should be removed from session.")
    }

    func test_deleteEvidenceItem_removesVoiceNoteAndCompanionTranscript() async throws {
        let roomId = UUID()
        let capturePointId = UUID()
        let note = VoiceNoteV1(
            visitId: visitId,
            roomId: roomId,
            capturePointId: capturePointId,
            processedTranscript: "Test transcript unique-\(UUID().uuidString)"
        )
        coordinator.addVoiceNote(note)
        XCTAssertEqual(coordinator.session.voiceNotes.count, 1)
        XCTAssertEqual(coordinator.session.transcripts.count, 1)

        let item = RecentCaptureItemV1.from(voiceNote: note)
        coordinator.deleteEvidenceItem(item)

        XCTAssertTrue(coordinator.session.voiceNotes.isEmpty, "Voice note should be removed.")
        XCTAssertTrue(coordinator.session.transcripts.isEmpty, "Companion transcript should be removed.")
    }

    func test_deleteEvidenceItem_removesPinFromSavedRoom() async throws {
        let roomId = UUID()
        let pin = SpatialPinV1(
            roomId: roomId,
            positionX: 1, positionY: 0, positionZ: 1,
            objectType: .boiler,
            anchorConfidence: .raycastEstimated
        )
        var room = RoomCaptureV2(id: roomId, displayName: "Boiler Room")
        room.pinnedObjects = [pin]
        coordinator.addRoom(room)

        let item = RecentCaptureItemV1.from(pin: pin)
        coordinator.deleteEvidenceItem(item)

        let savedRoom = coordinator.room(withId: roomId)
        XCTAssertTrue(savedRoom?.pinnedObjects.isEmpty ?? false, "Pin should be removed from saved room.")
    }

    func test_deleteEvidenceItem_removesGhostFromSavedRoom() async throws {
        let roomId = UUID()
        let ghost = GhostAppliancePlacementV1(
            roomId: roomId,
            capturePointId: UUID(),
            applianceModelId: "test-model",
            dimensionsMm: .init(width: 600, height: 750, depth: 350),
            anchorConfidence: .screenOnly
        )
        var room = RoomCaptureV2(id: roomId, displayName: "Test Room")
        room.ghostAppliancePlacements = [ghost]
        coordinator.addRoom(room)

        let item = RecentCaptureItemV1.from(ghost: ghost, displayLabel: "Test Appliance")
        coordinator.deleteEvidenceItem(item)

        let savedRoom = coordinator.room(withId: roomId)
        XCTAssertTrue(savedRoom?.ghostAppliancePlacements.isEmpty ?? false,
                      "Ghost placement should be removed from saved room.")
    }

    func test_deleteEvidenceItem_doesNotRemoveRoomRecord() async throws {
        let roomId = UUID()
        let photo = PhotoEvidenceV1(visitId: visitId, roomId: roomId, relativeFilePath: "photo.jpg")
        coordinator.addPhoto(photo)
        var room = RoomCaptureV2(id: roomId, displayName: "Protected Room")
        coordinator.addRoom(room)

        let item = RecentCaptureItemV1.from(photo: photo)
        coordinator.deleteEvidenceItem(item)

        XCTAssertNotNil(coordinator.room(withId: roomId),
                        "deleteEvidenceItem must never remove the room record itself.")
    }

    func test_deleteEvidenceItem_unknownIdIsNoOp() async throws {
        let roomId = UUID()
        let photo = PhotoEvidenceV1(visitId: visitId, roomId: roomId, relativeFilePath: "photo.jpg")
        coordinator.addPhoto(photo)

        // Delete using a different (unrelated) evidence id.
        let fakePhoto = PhotoEvidenceV1(visitId: visitId, roomId: roomId, relativeFilePath: "other.jpg")
        let item = RecentCaptureItemV1.from(photo: fakePhoto)
        coordinator.deleteEvidenceItem(item)

        XCTAssertEqual(coordinator.session.photos.count, 1,
                       "Deleting an unknown id must not affect unrelated evidence.")
    }

    // MARK: - Spatial measurements

    func test_spatialMeasurement_persistsOnRoom() async throws {
        let roomId = UUID()
        let startPt = LiveCapturePointV1(
            roomId: roomId,
            screenPoint: CGPointCodable(x: 0.5, y: 0.5),
            worldPosition: SIMD3<Double>(0, 0, 0),
            anchorConfidence: .raycastEstimated,
            hitNormal: SIMD3<Double>(0, 0, -1)
        )
        let endPt = LiveCapturePointV1(
            roomId: roomId,
            screenPoint: CGPointCodable(x: 0.6, y: 0.5),
            worldPosition: SIMD3<Double>(2.5, 0, 0),
            anchorConfidence: .raycastEstimated,
            hitNormal: SIMD3<Double>(0, 0, -1)
        )
        let measurement = SpatialMeasurementV1(
            roomId: roomId,
            startCapturePointId: startPt.id,
            endCapturePointId: endPt.id,
            startWorldPosition: startPt.worldPosition!,
            endWorldPosition: endPt.worldPosition!,
            startSurfaceSemantic: startPt.surfaceSemantic ?? .unknown,
            endSurfaceSemantic: endPt.surfaceSemantic ?? .unknown,
            anchorConfidence: .raycastEstimated
        )

        var room = RoomCaptureV2(id: roomId, displayName: "Measured Room")
        room.measurements = [measurement]
        coordinator.addRoom(room)
        await coordinator.saveSession()

        let savedRoom = coordinator.room(withId: roomId)
        XCTAssertEqual(savedRoom?.measurements.count, 1, "Measurement must be persisted on the room.")
        XCTAssertEqual(savedRoom?.measurements.first?.id, measurement.id)
        XCTAssertFalse(savedRoom?.measurements.first?.needsReview ?? true,
                       "Fully anchored measurement must not require review.")
    }

    func test_spatialMeasurement_distanceComputed() {
        let roomId = UUID()
        let start = SIMD3<Double>(0, 0, 0)
        let end = SIMD3<Double>(3, 4, 0)
        let m = SpatialMeasurementV1(
            roomId: roomId,
            startCapturePointId: UUID(),
            endCapturePointId: UUID(),
            startWorldPosition: start,
            endWorldPosition: end,
            anchorConfidence: .high
        )
        XCTAssertEqual(m.distanceMeters, 5.0, accuracy: 0.001)
        XCTAssertEqual(m.horizontalDistanceMeters, 5.0, accuracy: 0.001)
        XCTAssertEqual(m.verticalOffsetMeters, 0.0, accuracy: 0.001)
    }

    func test_spatialMeasurement_verticalOffsetCorrect() {
        let roomId = UUID()
        let m = SpatialMeasurementV1(
            roomId: roomId,
            startCapturePointId: UUID(),
            endCapturePointId: UUID(),
            startWorldPosition: SIMD3<Double>(0, 0, 0),
            endWorldPosition: SIMD3<Double>(0, 1.5, 0),
            anchorConfidence: .high
        )
        XCTAssertEqual(m.distanceMeters, 1.5, accuracy: 0.001)
        XCTAssertEqual(m.horizontalDistanceMeters, 0.0, accuracy: 0.001)
        XCTAssertEqual(m.verticalOffsetMeters, 1.5, accuracy: 0.001)
        XCTAssertFalse(m.needsReview)
    }

    func test_spatialMeasurement_screenOnlyNeedsReview() {
        let m = SpatialMeasurementV1(
            roomId: UUID(),
            startCapturePointId: UUID(),
            endCapturePointId: UUID(),
            startWorldPosition: SIMD3<Double>(0, 0, 0),
            endWorldPosition: SIMD3<Double>(1, 0, 0),
            anchorConfidence: .screenOnly
        )
        XCTAssertTrue(m.needsReview, "Screen-only measurement must require review.")
    }

    func test_deleteEvidenceItem_removesMeasurementFromSavedRoom() async throws {
        let roomId = UUID()
        let measurement = SpatialMeasurementV1(
            roomId: roomId,
            startCapturePointId: UUID(),
            endCapturePointId: UUID(),
            startWorldPosition: SIMD3<Double>(0, 0, 0),
            endWorldPosition: SIMD3<Double>(1, 0, 0),
            anchorConfidence: .raycastEstimated
        )
        var room = RoomCaptureV2(id: roomId, displayName: "Room With Measurement")
        room.measurements = [measurement]
        coordinator.addRoom(room)

        let item = RecentCaptureItemV1.from(measurement: measurement)
        coordinator.deleteEvidenceItem(item)

        let savedRoom = coordinator.room(withId: roomId)
        XCTAssertTrue(savedRoom?.measurements.isEmpty ?? false,
                      "Measurement should be removed from saved room.")
    }

    func test_draftRecovery_measurementAttachedToCorrectRoom() async throws {
        let prospectiveRoomId = UUID()
        let nextId = UUID()
        let measurement = SpatialMeasurementV1(
            roomId: prospectiveRoomId,
            startCapturePointId: UUID(),
            endCapturePointId: UUID(),
            startWorldPosition: SIMD3<Double>(0, 0, 0),
            endWorldPosition: SIMD3<Double>(2, 0, 0),
            anchorConfidence: .raycastEstimated
        )
        let otherRoomId = UUID()
        let otherMeasurement = SpatialMeasurementV1(
            roomId: otherRoomId,
            startCapturePointId: UUID(),
            endCapturePointId: UUID(),
            startWorldPosition: SIMD3<Double>(0, 0, 0),
            endWorldPosition: SIMD3<Double>(1, 0, 0),
            anchorConfidence: .screenOnly
        )

        let transition = V2RoomLoopLifecycle.makeDraftRoomRecoveryTransition(
            prospectiveRoomId: prospectiveRoomId,
            pendingPins: [],
            pendingGhostPlacements: [],
            pendingMeasurements: [measurement, otherMeasurement],
            nextProspectiveRoomId: nextId
        )

        XCTAssertEqual(transition.draftRoom.measurements.count, 1)
        XCTAssertEqual(transition.draftRoom.measurements.first?.id, measurement.id)
        XCTAssertEqual(transition.remainingPendingMeasurements.count, 1)
        XCTAssertEqual(transition.remainingPendingMeasurements.first?.id, otherMeasurement.id)
    }

    func test_discardRecovery_removesMeasurementsForDiscardedRoom() async throws {
        let keptRoomId = UUID()
        let discardedRoomId = UUID()

        let keptMeasurement = SpatialMeasurementV1(
            roomId: keptRoomId,
            startCapturePointId: UUID(),
            endCapturePointId: UUID(),
            startWorldPosition: SIMD3<Double>(0, 0, 0),
            endWorldPosition: SIMD3<Double>(1, 0, 0),
            anchorConfidence: .high
        )
        let discardedMeasurement = SpatialMeasurementV1(
            roomId: discardedRoomId,
            startCapturePointId: UUID(),
            endCapturePointId: UUID(),
            startWorldPosition: SIMD3<Double>(0, 0, 0),
            endWorldPosition: SIMD3<Double>(2, 0, 0),
            anchorConfidence: .high
        )

        var keptRoom = RoomCaptureV2(id: keptRoomId, displayName: "Kept")
        keptRoom.measurements = [keptMeasurement]
        var discardedRoom = RoomCaptureV2(id: discardedRoomId, displayName: "Discarded")
        discardedRoom.measurements = [discardedMeasurement]

        coordinator.addRoom(keptRoom)
        coordinator.addRoom(discardedRoom)

        coordinator.discardUnfinishedRoomEvidence(for: discardedRoomId)

        XCTAssertFalse(coordinator.session.rooms.contains { $0.id == discardedRoomId },
                       "Discarded room must be removed (including its measurements).")
        XCTAssertEqual(coordinator.session.rooms.first(where: { $0.id == keptRoomId })?.measurements.count, 1,
                       "Measurements for other rooms must be preserved.")
    }

    func test_roomCaptureV2_decodesWithoutMeasurements() throws {
        // Simulate old serialised data that has no measurements key.
        let json = """
        {
            "id": "00000000-0000-0000-0000-000000000001",
            "displayName": "Old Room",
            "polygonVertices": [],
            "floorLevelY": 0.0,
            "ceilingHeightM": 2.4,
            "pinnedObjects": [],
            "ghostAppliancePlacements": [],
            "customApplianceDefinitions": [],
            "capturedAt": "2024-01-01T00:00:00Z"
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let room = try decoder.decode(RoomCaptureV2.self, from: json)
        XCTAssertTrue(room.measurements.isEmpty,
                      "Room decoded from old data must default to empty measurements array.")
        XCTAssertEqual(room.displayName, "Old Room")
    }

    func test_spatialPin_hasResolvedWorldAnchor_whenAnchorIdPresentAtOrigin() {
        let pin = SpatialPinV1(
            roomId: UUID(),
            anchorId: UUID(),
            positionX: 0,
            positionY: 0,
            positionZ: 0,
            objectType: .boiler,
            anchorConfidence: .worldLocked
        )
        XCTAssertTrue(pin.hasResolvedWorldAnchor,
                      "Anchor-backed pins at origin must still be treated as resolved world anchors.")
    }
