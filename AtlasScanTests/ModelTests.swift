import XCTest
import Combine
@testable import AtlasScan

// MARK: - ScanJobTests

final class ScanJobTests: XCTestCase {

    func test_newJob_hasCorrectDefaults() {
        let job = ScanJob(propertyAddress: "14 Test Street")
        XCTAssertEqual(job.status, .draft)
        XCTAssertTrue(job.rooms.isEmpty)
        XCTAssertFalse(job.isReadyToExport)
        XCTAssertEqual(job.totalTaggedObjects, 0)
    }

    func test_addRoom_updatesRoomCount() {
        var job = ScanJob(propertyAddress: "14 Test Street")
        let room = ScannedRoom(jobID: job.id, name: "Living Room")
        job.addRoom(room)
        XCTAssertEqual(job.rooms.count, 1)
    }

    func test_removeRoom_decreasesCount() {
        var job = ScanJob(propertyAddress: "14 Test Street")
        let room = ScannedRoom(jobID: job.id, name: "Living Room")
        job.addRoom(room)
        job.removeRoom(id: room.id)
        XCTAssertEqual(job.rooms.count, 0)
    }

    func test_isReadyToExport_requiresAllRoomsReviewed() {
        var job = ScanJob(propertyAddress: "14 Test Street")
        var room = ScannedRoom(jobID: job.id, name: "Living Room")
        job.addRoom(room)
        XCTAssertFalse(job.isReadyToExport)

        room.isReviewed = true
        job.updateRoom(room)
        XCTAssertTrue(job.isReadyToExport)
    }

    func test_totalTaggedObjects_countsAcrossRooms() {
        var job = ScanJob(propertyAddress: "14 Test Street")
        var room1 = ScannedRoom(jobID: job.id, name: "Room 1")
        var room2 = ScannedRoom(jobID: job.id, name: "Room 2")
        room1.taggedObjects = [TaggedObject(roomID: room1.id, category: .boiler)]
        room2.taggedObjects = [
            TaggedObject(roomID: room2.id, category: .radiator),
            TaggedObject(roomID: room2.id, category: .thermostat),
        ]
        job.rooms = [room1, room2]
        XCTAssertEqual(job.totalTaggedObjects, 3)
    }
}

// MARK: - ScannedRoomTests

final class ScannedRoomTests: XCTestCase {

    func test_addTaggedObject_updatesCount() {
        var room = ScannedRoom(jobID: UUID(), name: "Kitchen")
        let obj = TaggedObject(roomID: room.id, category: .radiator)
        room.addTaggedObject(obj)
        XCTAssertEqual(room.taggedObjects.count, 1)
    }

    func test_removeTaggedObject_byID() {
        var room = ScannedRoom(jobID: UUID(), name: "Kitchen")
        let obj = TaggedObject(roomID: room.id, category: .radiator)
        room.addTaggedObject(obj)
        room.removeTaggedObject(id: obj.id)
        XCTAssertEqual(room.taggedObjects.count, 0)
    }

    func test_updateTaggedObject_replacesInPlace() {
        var room = ScannedRoom(jobID: UUID(), name: "Kitchen")
        var obj = TaggedObject(roomID: room.id, category: .radiator)
        room.addTaggedObject(obj)

        obj.label = "Updated Label"
        room.updateTaggedObject(obj)

        XCTAssertEqual(room.taggedObjects.first?.label, "Updated Label")
    }

    func test_displayFloor_groundFloor() {
        let room = ScannedRoom(jobID: UUID(), name: "Hall", floor: 0)
        XCTAssertEqual(room.displayFloor, "Ground Floor")
    }

    func test_displayFloor_firstFloor() {
        let room = ScannedRoom(jobID: UUID(), name: "Bedroom", floor: 1)
        XCTAssertEqual(room.displayFloor, "First Floor")
    }

    func test_displayFloor_basement() {
        let room = ScannedRoom(jobID: UUID(), name: "Cellar", floor: -1)
        XCTAssertEqual(room.displayFloor, "Basement")
    }
}

// MARK: - TaggedObjectTests

final class TaggedObjectTests: XCTestCase {

    func test_defaultLabel_usesCategory() {
        let obj = TaggedObject(roomID: UUID(), category: .boiler, label: "")
        XCTAssertEqual(obj.displayLabel, "Boiler")
    }

    func test_customLabel_preferred() {
        let obj = TaggedObject(roomID: UUID(), category: .boiler, label: "Main Boiler")
        XCTAssertEqual(obj.displayLabel, "Main Boiler")
    }

    func test_normalizedPoint_clamped() {
        let point = NormalizedPoint2D(x: 1.5, y: -0.3)
        XCTAssertEqual(point.x, 1.0)
        XCTAssertEqual(point.y, 0.0)
    }
}

// MARK: - ServiceObjectCategoryTests

final class ServiceObjectCategoryTests: XCTestCase {

    func test_allCategories_haveDisplayName() {
        for cat in ServiceObjectCategory.allCases {
            XCTAssertFalse(cat.displayName.isEmpty, "\(cat.rawValue) has empty displayName")
        }
    }

    func test_allCategories_haveGroupName() {
        for cat in ServiceObjectCategory.allCases {
            XCTAssertFalse(cat.groupName.isEmpty, "\(cat.rawValue) has empty groupName")
        }
    }

    func test_allCategories_haveSymbolName() {
        for cat in ServiceObjectCategory.allCases {
            XCTAssertFalse(cat.symbolName.isEmpty, "\(cat.rawValue) has empty symbolName")
        }
    }

    func test_boiler_quickFields_notEmpty() {
        XCTAssertFalse(ServiceObjectCategory.boiler.quickFields.isEmpty)
    }

    func test_radiator_quickFields_notEmpty() {
        XCTAssertFalse(ServiceObjectCategory.radiator.quickFields.isEmpty)
    }

    func test_other_quickFields_empty() {
        XCTAssertTrue(ServiceObjectCategory.other.quickFields.isEmpty)
    }

    func test_defaultEvidenceKind_boiler_isPlant() {
        XCTAssertEqual(ServiceObjectCategory.boiler.defaultEvidenceKind, .plant)
    }

    func test_defaultEvidenceKind_radiator_isEmitter() {
        XCTAssertEqual(ServiceObjectCategory.radiator.defaultEvidenceKind, .emitter)
    }

    func test_defaultEvidenceKind_flue_isFlue() {
        XCTAssertEqual(ServiceObjectCategory.flue.defaultEvidenceKind, .flue)
    }

    func test_defaultEvidenceKind_thermostat_isControl() {
        XCTAssertEqual(ServiceObjectCategory.thermostat.defaultEvidenceKind, .control)
    }

    func test_defaultEvidenceKind_airingCupboard_isCupboard() {
        XCTAssertEqual(ServiceObjectCategory.airingCupboard.defaultEvidenceKind, .cupboard)
    }

    func test_defaultEvidenceKind_other_isOther() {
        XCTAssertEqual(ServiceObjectCategory.other.defaultEvidenceKind, .other)
    }

    func test_allCategories_haveDefaultEvidenceKind() {
        // Verify every category returns a valid (non-crashing) evidence kind.
        for cat in ServiceObjectCategory.allCases {
            let kind = cat.defaultEvidenceKind
            XCTAssertFalse(kind.displayName.isEmpty,
                "\(cat.rawValue) defaultEvidenceKind has empty displayName")
        }
    }
}

// MARK: - RoomCaptureViewModelTests

/// A synchronous test adapter that immediately delivers a scan result when `complete()` is called.
/// Avoids the artificial delays in MockScannerAdapter so tests stay fast.
private final class ImmediateScanAdapter: ScannerAdapterProtocol {

    private let stateSubject   = PassthroughSubject<ScannerState, Never>()
    private let capturedSubject = PassthroughSubject<ScannedRoom, Never>()

    var statePublisher: AnyPublisher<ScannerState, Never> { stateSubject.eraseToAnyPublisher() }
    var capturedRoomPublisher: AnyPublisher<ScannedRoom, Never> { capturedSubject.eraseToAnyPublisher() }

    func startCapture(jobID: UUID, roomName: String) {}
    func stopCapture() {}
    func cancelCapture() {}

    /// Fires the `.completed` state with a bare room carrying the given jobID + name.
    func complete(jobID: UUID, name: String) {
        let room = ScannedRoom(jobID: jobID, name: name)
        stateSubject.send(.completed(room))
        capturedSubject.send(room)
    }
}

@MainActor
final class RoomCaptureViewModelTests: XCTestCase {

    // MARK: - In-scan object tagging

    func test_pendingObjects_mergedIntoCompletedRoom() async throws {
        let adapter = ImmediateScanAdapter()
        let jobID = UUID()
        let vm = RoomCaptureViewModel(adapter: adapter, jobID: jobID, roomName: "Test Room", floor: 1)

        let boiler = TaggedObject(roomID: vm.placeholderRoomID, category: .boiler)
        vm.addPendingObject(boiler)

        adapter.complete(jobID: jobID, name: "Test Room")

        // Allow Combine receive(on: DispatchQueue.main) to deliver.
        try await Task.sleep(nanoseconds: 50_000_000)

        let room = try XCTUnwrap(vm.capturedRoom, "capturedRoom should be set after completion")
        XCTAssertEqual(room.taggedObjects.count, 1)
        XCTAssertEqual(room.taggedObjects.first?.category, .boiler)
        // roomID on the object must be re-bound to the real (captured) room's ID.
        XCTAssertEqual(room.taggedObjects.first?.roomID, room.id)
    }

    func test_noPendingObjects_completedRoomIsEmpty() async throws {
        let adapter = ImmediateScanAdapter()
        let jobID = UUID()
        let vm = RoomCaptureViewModel(adapter: adapter, jobID: jobID, roomName: "Hallway", floor: 0)

        adapter.complete(jobID: jobID, name: "Hallway")
        try await Task.sleep(nanoseconds: 50_000_000)

        let room = try XCTUnwrap(vm.capturedRoom)
        XCTAssertTrue(room.taggedObjects.isEmpty)
    }

    func test_roomName_and_floor_applied_to_completedRoom() async throws {
        let adapter = ImmediateScanAdapter()
        let jobID = UUID()
        let vm = RoomCaptureViewModel(adapter: adapter, jobID: jobID, roomName: "Kitchen", floor: 2)

        // Adapter sends a raw room with a different name / zero floor – ViewModel should override.
        adapter.complete(jobID: jobID, name: "raw_internal_name")
        try await Task.sleep(nanoseconds: 50_000_000)

        let room = try XCTUnwrap(vm.capturedRoom)
        XCTAssertEqual(room.name, "Kitchen")
        XCTAssertEqual(room.floor, 2)
    }

    func test_multiplePendingObjects_allMerged() async throws {
        let adapter = ImmediateScanAdapter()
        let jobID = UUID()
        let vm = RoomCaptureViewModel(adapter: adapter, jobID: jobID, roomName: "Utility", floor: 0)

        vm.addPendingObject(TaggedObject(roomID: vm.placeholderRoomID, category: .boiler))
        vm.addPendingObject(TaggedObject(roomID: vm.placeholderRoomID, category: .thermostat))

        adapter.complete(jobID: jobID, name: "Utility")
        try await Task.sleep(nanoseconds: 50_000_000)

        let room = try XCTUnwrap(vm.capturedRoom)
        XCTAssertEqual(room.taggedObjects.count, 2)
        let categories = Set(room.taggedObjects.map(\.category))
        XCTAssertTrue(categories.contains(.boiler))
        XCTAssertTrue(categories.contains(.thermostat))
    }

    func test_addPendingObject_incrementsPendingCount() {
        let adapter = ImmediateScanAdapter()
        let vm = RoomCaptureViewModel(adapter: adapter, jobID: UUID(), roomName: "Room", floor: 0)

        XCTAssertEqual(vm.pendingTaggedObjects.count, 0)
        vm.addPendingObject(TaggedObject(roomID: vm.placeholderRoomID, category: .radiator))
        XCTAssertEqual(vm.pendingTaggedObjects.count, 1)
        vm.addPendingObject(TaggedObject(roomID: vm.placeholderRoomID, category: .cylinder))
        XCTAssertEqual(vm.pendingTaggedObjects.count, 2)
    }
}
