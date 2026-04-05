import XCTest
import AtlasContracts
@testable import AtlasScan

// MARK: - ExportBuilderTests

final class ExportBuilderTests: XCTestCase {

    private var builder: ExportBuilder!

    override func setUp() {
        super.setUp()
        builder = ExportBuilder()
    }

    // MARK: App-level validation

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

    // MARK: Bundle building — shared contract types

    func test_buildBundle_matchesSchemaVersion() {
        let job = makeValidJob()
        let bundle = builder.buildBundle(from: job)
        XCTAssertEqual(bundle.version, currentScanBundleVersion)
    }

    func test_buildBundle_addressPreservedInOperatorNotes() {
        let job = makeValidJob()
        let bundle = builder.buildBundle(from: job)
        XCTAssertTrue(
            bundle.meta.operatorNotes?.contains(job.propertyAddress) == true,
            "Expected propertyAddress in operatorNotes, got: \(bundle.meta.operatorNotes ?? "nil")"
        )
    }

    func test_buildBundle_roomCountMatches() {
        let job = makeValidJob(roomCount: 3)
        let bundle = builder.buildBundle(from: job)
        XCTAssertEqual(bundle.rooms.count, 3)
    }

    func test_buildBundle_roomHasRequiredContractFields() {
        let job = makeValidJob()
        let bundle = builder.buildBundle(from: job)
        let room = try! XCTUnwrap(bundle.rooms.first)

        XCTAssertFalse(room.id.isEmpty)
        XCTAssertGreaterThanOrEqual(room.floorIndex, -1)
        XCTAssertGreaterThanOrEqual(room.areaM2, 0.0)
        XCTAssertGreaterThanOrEqual(room.heightM, 0.0)
        XCTAssertNotNil(room.walls)
        XCTAssertNotNil(room.detectedObjects)
        XCTAssertNotNil(room.polygon)
    }

    func test_buildBundle_taggedObjectsMappedToDetectedObjects() {
        var job = makeValidJob()
        var room = ScannedRoom(jobID: job.id, name: "Room A", isReviewed: true)
        room.taggedObjects = [
            TaggedObject(roomID: room.id, category: .boiler),
            TaggedObject(roomID: room.id, category: .radiator),
        ]
        job.rooms = [room]

        let bundle = builder.buildBundle(from: job)
        XCTAssertEqual(bundle.rooms.first?.detectedObjects.count, 2)
        XCTAssertEqual(bundle.rooms.first?.detectedObjects.first?.category, "boiler")
    }

    func test_buildBundle_quickFieldValuesPreservedInQAFlags() {
        var job = makeValidJob()
        var room = ScannedRoom(jobID: job.id, name: "Utility", isReviewed: true)
        let obj = TaggedObject(
            roomID: room.id,
            category: .boiler,
            quickFieldValues: ["type": "Combi", "enclosed": "false"]
        )
        room.taggedObjects = [obj]
        job.rooms = [room]

        let bundle = builder.buildBundle(from: job)

        // Quick field values are carried as atlas.service_fields QA flags.
        let serviceFlag = bundle.qaFlags.first(where: { $0.code == "atlas.service_fields" })
        XCTAssertNotNil(serviceFlag, "Expected atlas.service_fields QA flag for object with quick fields")
        XCTAssertEqual(serviceFlag?.entityId, obj.id.uuidString)
        XCTAssertTrue(serviceFlag?.message.contains("Combi") == true)
    }

    func test_buildBundle_metaHasRequiredFields() {
        let job = makeValidJob()
        let bundle = builder.buildBundle(from: job)

        XCTAssertFalse(bundle.meta.capturedAt.isEmpty)
        XCTAssertFalse(bundle.meta.deviceModel.isEmpty)
        XCTAssertFalse(bundle.meta.scannerApp.isEmpty)
        XCTAssertEqual(bundle.meta.coordinateConvention, "metric_m")
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

        XCTAssertTrue(str.contains(currentScanBundleVersion))
    }

    // MARK: Contract-level validation

    func test_encodeBundle_passesContractValidation() throws {
        let job = makeValidJob()
        let bundle = builder.buildBundle(from: job)
        let data = try builder.encode(bundle: bundle)

        let result = builder.validateBundle(data: data)
        XCTAssertTrue(result.isSuccess, "Contract validation failed: \(result.errors)")
    }

    func test_invalidJSON_failsContractValidation() {
        let badData = Data("{\"version\":\"1.0\",\"bundleId\":\"x\"}".utf8)
        let result = builder.validateBundle(data: badData)

        XCTAssertFalse(result.isSuccess)
        XCTAssertFalse(result.errors.isEmpty)
    }

    func test_unsupportedVersion_failsContractValidation() throws {
        let job = makeValidJob()
        var bundle = builder.buildBundle(from: job)
        // Manually craft a bundle with an unsupported version field.
        let data = try builder.encode(bundle: bundle)
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        json["version"] = "99.0"
        let badData = try JSONSerialization.data(withJSONObject: json)

        let result = builder.validateBundle(data: badData)
        XCTAssertFalse(result.isSuccess)
        XCTAssertTrue(result.errors.first?.contains("not supported") == true)
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
