import XCTest
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
}
