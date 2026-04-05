import XCTest
import AtlasContracts
@testable import AtlasScan

// MARK: - HandoffTests
//
// Tests for export readiness evaluation, export package generation,
// and blocking export conditions.

final class HandoffTests: XCTestCase {

    private var builder: ExportBuilder!
    private var packageBuilder: ExportPackageBuilder!

    override func setUp() {
        super.setUp()
        builder = ExportBuilder()
        packageBuilder = ExportPackageBuilder()
    }

    override func tearDown() {
        // Clean up any temp packages created during tests.
        ExportPackageBuilder.cleanupAllTempPackages()
        super.tearDown()
    }

    // MARK: - Export readiness: blocking states

    func test_validate_emptyAddress_isBlocking() {
        var job = ScanJob(propertyAddress: "")
        job.rooms = [makeReviewedRoom(jobID: job.id)]

        let issues = builder.validate(job: job)

        XCTAssertTrue(issues.contains(where: { $0.severity == .blocking && $0.message.contains("address") }))
    }

    func test_validate_noRooms_isBlocking() {
        let job = ScanJob(propertyAddress: "14 Test Street")

        let issues = builder.validate(job: job)

        XCTAssertTrue(issues.contains(where: { $0.severity == .blocking && $0.message.contains("room") }))
    }

    func test_validate_noBlockers_whenAddressAndRoomsPresent() {
        var job = ScanJob(propertyAddress: "14 Test Street")
        job.rooms = [makeReviewedRoom(jobID: job.id)]

        let issues = builder.validate(job: job)

        XCTAssertFalse(issues.contains(where: { $0.severity == .blocking }))
    }

    // MARK: - Export readiness: warning states

    func test_validate_unreviewedRoom_isWarning() {
        var job = ScanJob(propertyAddress: "14 Test Street")
        let room = ScannedRoom(jobID: job.id, name: "Kitchen", isReviewed: false)
        job.rooms = [room]

        let issues = builder.validate(job: job)

        XCTAssertTrue(issues.contains(where: { $0.severity == .warning && $0.message.contains("reviewed") }))
    }

    func test_validate_unplacedBoiler_isWarning() {
        var job = ScanJob(propertyAddress: "14 Test Street")
        var room = makeReviewedRoom(jobID: job.id)
        var boiler = TaggedObject(roomID: room.id, category: .boiler)
        boiler.placementMode = .unplaced
        room.taggedObjects = [boiler]
        job.rooms = [room]

        let issues = builder.validate(job: job)

        XCTAssertTrue(issues.contains(where: {
            $0.severity == .warning && $0.message.contains("placed")
        }))
    }

    func test_validate_unplacedCylinder_isWarning() {
        var job = ScanJob(propertyAddress: "14 Test Street")
        var room = makeReviewedRoom(jobID: job.id)
        var cylinder = TaggedObject(roomID: room.id, category: .cylinder)
        cylinder.placementMode = .unplaced
        room.taggedObjects = [cylinder]
        job.rooms = [room]

        let issues = builder.validate(job: job)

        XCTAssertTrue(issues.contains(where: {
            $0.severity == .warning && $0.message.contains("placed")
        }))
    }

    func test_validate_placedBoiler_noUnplacedWarning() {
        var job = ScanJob(propertyAddress: "14 Test Street")
        var room = makeReviewedRoom(jobID: job.id)
        var boiler = TaggedObject(roomID: room.id, category: .boiler)
        boiler.placementMode = .floorPlaced
        room.taggedObjects = [boiler]
        job.rooms = [room]

        let issues = builder.validate(job: job)

        XCTAssertFalse(issues.contains(where: {
            $0.severity == .warning && $0.message.contains("placed")
        }))
    }

    func test_validate_tentativeAdjacency_isWarning() {
        var job = ScanJob(propertyAddress: "14 Test Street")
        job.rooms = [makeReviewedRoom(jobID: job.id)]
        let adj = RoomAdjacency(
            fromRoomID: UUID(),
            toRoomID: UUID(),
            kind: .door,
            isConfirmed: false
        )
        job.roomAdjacencies = [adj]

        let issues = builder.validate(job: job)

        XCTAssertTrue(issues.contains(where: {
            $0.severity == .warning && $0.message.contains("confirmed")
        }))
    }

    func test_validate_confirmedAdjacency_noTentativeWarning() {
        var job = ScanJob(propertyAddress: "14 Test Street")
        job.rooms = [makeReviewedRoom(jobID: job.id)]
        let adj = RoomAdjacency(
            fromRoomID: UUID(),
            toRoomID: UUID(),
            kind: .door,
            isConfirmed: true
        )
        job.roomAdjacencies = [adj]

        let issues = builder.validate(job: job)

        XCTAssertFalse(issues.contains(where: {
            $0.severity == .warning && $0.message.contains("confirmed")
        }))
    }

    func test_validate_noEvidence_isWarning() {
        var job = ScanJob(propertyAddress: "14 Test Street")
        job.rooms = [makeReviewedRoom(jobID: job.id)]

        let issues = builder.validate(job: job)

        XCTAssertTrue(issues.contains(where: {
            $0.severity == .warning && $0.message.lowercased().contains("evidence")
        }))
    }

    func test_validate_withEvidence_noEvidenceWarning() {
        var job = ScanJob(propertyAddress: "14 Test Street")
        var room = makeReviewedRoom(jobID: job.id)
        room.addPhoto(TaggedPhoto(filename: "test.jpg", roomID: room.id))
        job.rooms = [room]

        let issues = builder.validate(job: job)

        XCTAssertFalse(issues.contains(where: {
            $0.severity == .warning && $0.message.lowercased().contains("evidence")
        }))
    }

    func test_validate_lowConfidenceObject_isWarning() {
        var job = ScanJob(propertyAddress: "14 Test Street")
        var room = makeReviewedRoom(jobID: job.id)
        var obj = TaggedObject(roomID: room.id, category: .radiator)
        obj.confidence = .low
        room.taggedObjects = [obj]
        job.rooms = [room]

        let issues = builder.validate(job: job)

        XCTAssertTrue(issues.contains(where: {
            $0.severity == .warning && $0.message.contains("confidence")
        }))
    }

    // MARK: - Export package generation

    func test_buildPackage_createsExpectedFiles() throws {
        let job = makeValidJob()
        let bundle = builder.buildBundle(from: job)
        let json = String(decoding: try builder.encode(bundle: bundle), as: UTF8.self)

        let pkg = try packageBuilder.buildPackage(from: job, bundleJSON: json)
        defer { pkg.cleanup() }

        XCTAssertTrue(FileManager.default.fileExists(atPath: pkg.bundleFile.path),
                      "scan_bundle.json must exist")
        XCTAssertTrue(FileManager.default.fileExists(atPath: pkg.manifestFile.path),
                      "manifest.json must exist")
        XCTAssertTrue(pkg.evidenceFiles.isEmpty,
                      "No evidence files when includeEvidence = false")
    }

    func test_buildPackage_manifestIsValidJSON() throws {
        let job = makeValidJob()
        let bundle = builder.buildBundle(from: job)
        let json = String(decoding: try builder.encode(bundle: bundle), as: UTF8.self)

        let pkg = try packageBuilder.buildPackage(from: job, bundleJSON: json)
        defer { pkg.cleanup() }

        let manifestData = try Data(contentsOf: pkg.manifestFile)
        let manifest = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: manifestData) as? [String: Any]
        )
        XCTAssertEqual(manifest["format"] as? String, "AtlasScanPackageV1")
        XCTAssertEqual(manifest["room_count"] as? Int, job.rooms.count)
    }

    func test_buildPackage_bundleJSONMatchesInput() throws {
        let job = makeValidJob()
        let bundle = builder.buildBundle(from: job)
        let json = String(decoding: try builder.encode(bundle: bundle), as: UTF8.self)

        let pkg = try packageBuilder.buildPackage(from: job, bundleJSON: json)
        defer { pkg.cleanup() }

        let written = try String(contentsOf: pkg.bundleFile, encoding: .utf8)
        XCTAssertEqual(written, json)
    }

    func test_buildPackage_cleanup_removesTempDirectory() throws {
        let job = makeValidJob()
        let bundle = builder.buildBundle(from: job)
        let json = String(decoding: try builder.encode(bundle: bundle), as: UTF8.self)

        let pkg = try packageBuilder.buildPackage(from: job, bundleJSON: json)
        let dirPath = pkg.directory.path

        XCTAssertTrue(FileManager.default.fileExists(atPath: dirPath))
        pkg.cleanup()
        XCTAssertFalse(FileManager.default.fileExists(atPath: dirPath),
                       "cleanup() should remove the temp directory")
    }

    // MARK: - Failure on blocking export conditions

    func test_blockingIssues_preventBundleEmission() {
        // A job with no rooms has a blocking issue; the bundle should not be
        // used for export.  The ExportBuilder still builds a (trivially empty)
        // bundle — the caller is responsible for checking validate() first.
        let job = ScanJob(propertyAddress: "")

        let issues = builder.validate(job: job)
        let hasBlockers = issues.contains(where: { $0.severity == .blocking })

        XCTAssertTrue(hasBlockers, "Empty address + no rooms must produce blocking issues")
    }

    func test_contractValidation_failsOnCorruptJSON() {
        let badData = Data("{\"version\":\"1.0\",\"bundleId\":\"x\"}".utf8)
        let result = builder.validateBundle(data: badData)

        XCTAssertFalse(result.isSuccess)
        XCTAssertFalse(result.errors.isEmpty)
    }

    func test_contractValidation_passesForValidBundle() throws {
        let job = makeValidJob()
        let bundle = builder.buildBundle(from: job)
        let data = try builder.encode(bundle: bundle)

        let result = builder.validateBundle(data: data)
        XCTAssertTrue(result.isSuccess, "Contract validation failed: \(result.errors)")
    }

    // MARK: - Helpers

    private func makeReviewedRoom(jobID: UUID) -> ScannedRoom {
        var room = ScannedRoom(jobID: jobID, name: "Test Room")
        room.isReviewed = true
        return room
    }

    private func makeValidJob() -> ScanJob {
        var job = ScanJob(propertyAddress: "14 Test Street, Anytown")
        job.rooms = [makeReviewedRoom(jobID: job.id)]
        return job
    }
}
