import XCTest
@testable import AtlasScan

// MARK: - ExportBuilderTests

final class ExportBuilderTests: XCTestCase {

    private var builder: ExportBuilder!

    override func setUp() {
        super.setUp()
        builder = ExportBuilder()
    }

    // MARK: Validation

    func test_validate_emptyAddress_returnsBlockingIssue() {
        var job = ScanJob(propertyAddress: "")
        job.rooms = [ScannedRoom(jobID: job.id, name: "Test Room")]

        let issues = builder.validate(job: job)

        XCTAssertTrue(issues.contains(where: {
            $0.severity == .blocking && $0.message.contains("address")
        }))
    }

    func test_validate_noRooms_returnsBlockingIssue() {
        let job = ScanJob(propertyAddress: "14 Test Street")

        let issues = builder.validate(job: job)

        XCTAssertTrue(issues.contains(where: {
            $0.severity == .blocking && $0.message.contains("room")
        }))
    }

    func test_validate_unreviewed_room_returnsWarning() {
        var job = ScanJob(propertyAddress: "14 Test Street")
        let room = ScannedRoom(jobID: job.id, name: "Kitchen", isReviewed: false)
        job.rooms = [room]

        let issues = builder.validate(job: job)

        XCTAssertTrue(issues.contains(where: {
            $0.severity == .warning && $0.message.contains("reviewed")
        }))
    }

    func test_validate_validJob_returnsNoBlockingIssues() {
        var job = ScanJob(propertyAddress: "14 Test Street")
        var room = ScannedRoom(jobID: job.id, name: "Living Room")
        room.isReviewed = true
        job.rooms = [room]

        let issues = builder.validate(job: job)

        XCTAssertFalse(issues.contains(where: { $0.severity == .blocking }))
    }

    // MARK: Bundle building

    func test_buildBundle_matchesSchemaVersion() {
        let job = makeValidJob()
        let bundle = builder.buildBundle(from: job)
        XCTAssertEqual(bundle.schemaVersion, BundleSchemaVersion.current)
    }

    func test_buildBundle_jobAddressPreserved() {
        let job = makeValidJob()
        let bundle = builder.buildBundle(from: job)
        XCTAssertEqual(bundle.job.propertyAddress, job.propertyAddress)
    }

    func test_buildBundle_roomCountMatches() {
        let job = makeValidJob(roomCount: 3)
        let bundle = builder.buildBundle(from: job)
        XCTAssertEqual(bundle.rooms.count, 3)
    }

    func test_buildBundle_taggedObjectsPreserved() {
        var job = makeValidJob()
        var room = ScannedRoom(jobID: job.id, name: "Room A", isReviewed: true)
        room.taggedObjects = [
            TaggedObject(roomID: room.id, category: .boiler),
            TaggedObject(roomID: room.id, category: .radiator),
        ]
        job.rooms = [room]

        let bundle = builder.buildBundle(from: job)
        XCTAssertEqual(bundle.rooms.first?.taggedObjects.count, 2)
        XCTAssertEqual(bundle.rooms.first?.taggedObjects.first?.category, "boiler")
    }

    func test_buildBundle_quickFieldValuesPreserved() {
        var job = makeValidJob()
        var room = ScannedRoom(jobID: job.id, name: "Utility", isReviewed: true)
        room.taggedObjects = [
            TaggedObject(
                roomID: room.id,
                category: .boiler,
                quickFieldValues: ["type": "Combi", "enclosed": "false"]
            )
        ]
        job.rooms = [room]

        let bundle = builder.buildBundle(from: job)
        let qf = bundle.rooms.first?.taggedObjects.first?.quickFieldValues
        XCTAssertEqual(qf?["type"], "Combi")
        XCTAssertEqual(qf?["enclosed"], "false")
    }

    // MARK: JSON encoding

    func test_encodeBundle_producesValidJSON() throws {
        let job = makeValidJob()
        let bundle = builder.buildBundle(from: job)
        let data = try builder.encode(bundle: bundle)

        XCTAssertFalse(data.isEmpty)
        let json = try JSONSerialization.jsonObject(with: data)
        XCTAssertNotNil(json)
    }

    func test_encodeBundle_containsSchemaVersion() throws {
        let job = makeValidJob()
        let bundle = builder.buildBundle(from: job)
        let data = try builder.encode(bundle: bundle)
        let str = String(decoding: data, as: UTF8.self)

        XCTAssertTrue(str.contains(BundleSchemaVersion.current))
    }

    // MARK: Helpers

    private func makeValidJob(roomCount: Int = 1) -> ScanJob {
        var job = ScanJob(propertyAddress: "14 Test Street, Anytown")
        job.rooms = (0..<roomCount).map { i in
            var room = ScannedRoom(jobID: job.id, name: "Room \(i + 1)")
            room.isReviewed = true
            return room
        }
        return job
    }
}
