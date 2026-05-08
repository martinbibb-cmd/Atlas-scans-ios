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
            anchorConfidence: .raycastEstimated,
            hitNormal: SIMD3<Double>(0, 0, -1)
        )

        // 4. Attach a pin, photo, and voice note — all referencing the same capture point.
        let pin = SpatialPinV1(
            roomId: prospectiveRoomId,
            capturePointId: capturePoint.id,
            positionX: 1.5,
            positionY: 0.0,
            positionZ: 2.5,
            objectType: .boiler,
            anchorConfidence: .raycastEstimated
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

        // addVoiceNote is documented to create a matching ProcessedTranscriptV1 in the
        // session as a synchronous side-effect (see ScanSessionCoordinator.addVoiceNote).
        coordinator.addPhoto(photo)
        coordinator.addVoiceNote(voiceNote)

        // 5. Finish room — bundle all pending evidence into a RoomCaptureV2.
        var room = RoomCaptureV2(id: prospectiveRoomId, displayName: "Kitchen")
        room.pinnedObjects = [pin]
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
        let roomTranscripts = coordinator.session.transcripts.filter { $0.roomId == prospectiveRoomId }

        XCTAssertEqual(roomPhotos.count, 1, "One photo should be associated with the room.")
        XCTAssertEqual(roomVoices.count, 1, "One voice note should be associated with the room.")
        XCTAssertEqual(roomPins.count, 1, "One pin should be stored on the room.")
        XCTAssertEqual(roomTranscripts.count, 1, "Coordinator should have created a transcript for the voice note.")

        // 8. Assert all evidence references the same capturePointId.
        XCTAssertEqual(roomPhotos.first?.capturePointId, capturePoint.id,
                       "Photo capturePointId must match the capture point used.")
        XCTAssertEqual(roomVoices.first?.capturePointId, capturePoint.id,
                       "Voice note capturePointId must match the capture point used.")
        XCTAssertEqual(roomPins.first?.capturePointId, capturePoint.id,
                       "Pin capturePointId must match the capture point used.")
        XCTAssertEqual(roomTranscripts.first?.capturePointId, capturePoint.id,
                       "Transcript capturePointId must match the capture point used.")

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
        let photo = PhotoEvidenceV1(visitId: visitId, roomId: prospectiveRoomId, relativeFilePath: "draft.jpg")
        coordinator.addPhoto(photo)

        let transition = V2RoomLoopLifecycle.makeDraftRoomRecoveryTransition(
            prospectiveRoomId: prospectiveRoomId,
            pendingPins: [pin],
            pendingGhostPlacements: [],
            nextProspectiveRoomId: nextId
        )

        coordinator.addRoom(transition.draftRoom)
        await coordinator.saveSession()

        XCTAssertEqual(coordinator.session.rooms.count, 1)
        XCTAssertEqual(coordinator.session.rooms.first?.id, prospectiveRoomId)
        XCTAssertEqual(coordinator.session.photos.filter { $0.roomId == prospectiveRoomId }.count, 1)
        XCTAssertNotEqual(transition.nextProspectiveRoomId, prospectiveRoomId)
    }

    // MARK: - Discard recovery

    func test_discardRecovery_removesOnlyDiscardedRoomEvidence() async throws {
        let keptRoomId = UUID()
        let discardedRoomId = UUID()

        coordinator.addPhoto(PhotoEvidenceV1(visitId: visitId, roomId: keptRoomId, relativeFilePath: "kept.jpg"))
        coordinator.addPhoto(PhotoEvidenceV1(visitId: visitId, roomId: discardedRoomId, relativeFilePath: "discard.jpg"))

        coordinator.discardUnfinishedRoomEvidence(for: discardedRoomId)

        XCTAssertTrue(coordinator.session.photos.filter { $0.roomId == discardedRoomId }.isEmpty,
                      "Discarded room evidence must be removed.")
        XCTAssertEqual(coordinator.session.photos.filter { $0.roomId == keptRoomId }.count, 1,
                       "Evidence for other rooms must not be affected by discard.")
    }
}
