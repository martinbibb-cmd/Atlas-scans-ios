import XCTest
@testable import AtlasScan

// MARK: - SessionCompletionTests
//
// Unit tests for PR 6 additions:
//   • HandoffState enum
//   • PropertyScanSession.handoffState field (persistence + backward compat default)
//   • PropertyScanSession.handoffReadiness computed property
//   • SessionCaptureViewModel.markHandoffSent / markHandoffExported

final class SessionCompletionTests: XCTestCase {

    // MARK: - HandoffState defaults

    func test_handoffState_defaultsToNotSent() {
        let session = PropertyScanSession(propertyAddress: "1 Test Street")
        XCTAssertEqual(session.handoffState, .notSent)
    }

    func test_handoffState_canBeInitialisedAsSent() {
        let session = PropertyScanSession(propertyAddress: "1 Test Street", handoffState: .sent)
        XCTAssertEqual(session.handoffState, .sent)
    }

    func test_handoffState_canBeInitialisedAsExported() {
        let session = PropertyScanSession(propertyAddress: "1 Test Street", handoffState: .exported)
        XCTAssertEqual(session.handoffState, .exported)
    }

    // MARK: - HandoffState display names

    func test_handoffState_notSent_displayName() {
        XCTAssertEqual(HandoffState.notSent.displayName, "Not Sent")
    }

    func test_handoffState_sent_displayName() {
        XCTAssertEqual(HandoffState.sent.displayName, "Sent to Atlas Mind")
    }

    func test_handoffState_exported_displayName() {
        XCTAssertEqual(HandoffState.exported.displayName, "Exported")
    }

    // MARK: - HandoffState round-trip (Codable)

    func test_handoffState_roundTrips_notSent() throws {
        let session = PropertyScanSession(propertyAddress: "1 Test Street", handoffState: .notSent)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let data = try encoder.encode(session)
        let decoded = try decoder.decode(PropertyScanSession.self, from: data)
        XCTAssertEqual(decoded.handoffState, .notSent)
    }

    func test_handoffState_roundTrips_sent() throws {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        session.handoffState = .sent
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let data = try encoder.encode(session)
        let decoded = try decoder.decode(PropertyScanSession.self, from: data)
        XCTAssertEqual(decoded.handoffState, .sent)
    }

    func test_handoffState_roundTrips_exported() throws {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        session.handoffState = .exported
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let data = try encoder.encode(session)
        let decoded = try decoder.decode(PropertyScanSession.self, from: data)
        XCTAssertEqual(decoded.handoffState, .exported)
    }

    /// Sessions persisted before handoffState was added should decode as .notSent.
    func test_handoffState_backwardCompat_missingKeyDecodesAsNotSent() throws {
        // Build a JSON blob without the handoffState key.
        let legacyJSON = """
        {
            "id": "00000000-0000-0000-0000-000000000001",
            "jobReference": "ATL-LEGACY",
            "propertyAddress": "Legacy Street",
            "engineerName": "",
            "createdAt": "2024-01-01T00:00:00Z",
            "updatedAt": "2024-01-01T00:00:00Z"
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(PropertyScanSession.self, from: legacyJSON)
        XCTAssertEqual(decoded.handoffState, .notSent)
    }

    // MARK: - HandoffReadiness — empty session

    func test_readiness_emptySession_isNotReady() {
        let session = PropertyScanSession(propertyAddress: "1 Test Street")
        XCTAssertFalse(session.handoffReadiness.isReady)
    }

    func test_readiness_emptySession_flagsNoRooms() {
        let session = PropertyScanSession(propertyAddress: "1 Test Street")
        let readiness = session.handoffReadiness
        XCTAssertTrue(readiness.missingEssentials.contains("No rooms captured"))
    }

    func test_readiness_emptySession_flagsNoObjects() {
        let session = PropertyScanSession(propertyAddress: "1 Test Street")
        let readiness = session.handoffReadiness
        XCTAssertTrue(readiness.missingEssentials.contains("No objects tagged"))
    }

    func test_readiness_emptySession_flagsNoPhotos() {
        let session = PropertyScanSession(propertyAddress: "1 Test Street")
        let readiness = session.handoffReadiness
        XCTAssertTrue(readiness.missingEssentials.contains("No photos taken"))
    }

    // MARK: - HandoffReadiness — partial sessions

    func test_readiness_withRoomsOnly_isNotReady() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        session.rooms = [makeRoom()]
        XCTAssertFalse(session.handoffReadiness.isReady)
    }

    func test_readiness_withRoomsAndObjects_noPhotos_isNotReady() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        let room = makeRoom()
        session.rooms = [room]
        session.taggedObjects = [makeObject(roomID: room.id)]
        XCTAssertFalse(session.handoffReadiness.isReady)
        XCTAssertTrue(session.handoffReadiness.missingEssentials.contains("No photos taken"))
    }

    func test_readiness_withRoomsAndPhotos_noObjects_isNotReady() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        let room = makeRoom()
        session.rooms = [room]
        session.photos = [makePhoto()]
        XCTAssertFalse(session.handoffReadiness.isReady)
        XCTAssertTrue(session.handoffReadiness.missingEssentials.contains("No objects tagged"))
    }

    // MARK: - HandoffReadiness — ready session

    func test_readiness_withAllEssentials_isReady() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        let room = makeRoom()
        session.rooms = [room]
        session.taggedObjects = [makeObject(roomID: room.id)]
        session.photos = [makePhoto()]
        let readiness = session.handoffReadiness
        XCTAssertTrue(readiness.isReady)
        XCTAssertTrue(readiness.missingEssentials.isEmpty)
    }

    func test_readiness_objectsInRooms_count_towardObjects() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        var room = makeRoom()
        room.taggedObjects = [makeObject(roomID: room.id)]
        session.rooms = [room]
        session.photos = [makePhoto()]
        // Room-level objects count toward totalTaggedObjects, so readiness should be met
        XCTAssertTrue(session.handoffReadiness.isReady)
    }

    func test_readiness_photosInRooms_count_towardPhotos() {
        var session = PropertyScanSession(propertyAddress: "1 Test Street")
        var room = makeRoom()
        room.photos = [makePhoto()]
        room.taggedObjects = [makeObject(roomID: room.id)]
        session.rooms = [room]
        XCTAssertTrue(session.handoffReadiness.isReady)
    }

    // MARK: - ViewModel handoff state mutations

    func test_viewModel_markHandoffSent_setsStateSent() {
        let store = ScanSessionStore()
        let session = PropertyScanSession(propertyAddress: "1 Test Street")
        let vm = SessionCaptureViewModel(session: session, store: store, atlasSync: AtlasSync())
        XCTAssertEqual(vm.session.handoffState, .notSent)
        vm.markHandoffSent()
        XCTAssertEqual(vm.session.handoffState, .sent)
    }

    func test_viewModel_markHandoffExported_setsStateExported() {
        let store = ScanSessionStore()
        let session = PropertyScanSession(propertyAddress: "1 Test Street")
        let vm = SessionCaptureViewModel(session: session, store: store, atlasSync: AtlasSync())
        vm.markHandoffExported()
        XCTAssertEqual(vm.session.handoffState, .exported)
    }

    // MARK: - Helpers

    private func makeRoom() -> ScannedRoom {
        ScannedRoom(
            id: UUID(),
            jobID: UUID(),
            name: "Test Room",
            floor: 0
        )
    }

    private func makeObject(roomID: UUID) -> TaggedObject {
        TaggedObject(
            id: UUID(),
            roomID: roomID,
            category: .radiator,
            label: "Radiator",
            normalizedPosition: NormalizedPoint2D(x: 0.5, y: 0.5),
            placementMode: .wallMounted,
            rotation: 0.0
        )
    }

    private func makePhoto() -> TaggedPhoto {
        TaggedPhoto(filename: "test.jpg")
    }
}
