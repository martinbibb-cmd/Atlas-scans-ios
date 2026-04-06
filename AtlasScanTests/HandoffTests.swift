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
        let importSummary = try XCTUnwrap(manifest["import_summary"] as? [String: Any])
        XCTAssertEqual(importSummary["room_count"] as? Int, job.rooms.count)
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

    // MARK: - Import summary in manifest

    func test_buildPackage_manifest_decodesAsScanImportManifest() throws {
        let job = makeValidJob()
        let bundle = builder.buildBundle(from: job)
        let json = String(decoding: try builder.encode(bundle: bundle), as: UTF8.self)

        let pkg = try packageBuilder.buildPackage(from: job, bundleJSON: json)
        defer { pkg.cleanup() }

        let manifestData = try Data(contentsOf: pkg.manifestFile)
        let decoded = decodeImportManifest(manifestData)
        XCTAssertNotNil(decoded, "manifest.json must decode as ScanImportManifest")
        XCTAssertEqual(decoded?.format, "AtlasScanPackageV1")
        XCTAssertEqual(decoded?.propertyAddress, job.propertyAddress)
    }

    func test_buildPackage_manifest_importSummaryRoomCount() throws {
        let job = makeValidJob()
        let bundle = builder.buildBundle(from: job)
        let json = String(decoding: try builder.encode(bundle: bundle), as: UTF8.self)

        let pkg = try packageBuilder.buildPackage(from: job, bundleJSON: json)
        defer { pkg.cleanup() }

        let manifestData = try Data(contentsOf: pkg.manifestFile)
        let decoded = try XCTUnwrap(decodeImportManifest(manifestData))
        XCTAssertEqual(decoded.importSummary.roomCount, job.rooms.count)
    }

    func test_buildPackage_manifest_reviewStateIsAccurate() throws {
        var job = ScanJob(propertyAddress: "14 Test Street, Anytown")
        var room1 = makeReviewedRoom(jobID: job.id)
        room1.isReviewed = true
        var room2 = ScannedRoom(jobID: job.id, name: "Bedroom")
        room2.isReviewed = false
        job.rooms = [room1, room2]

        let bundle = builder.buildBundle(from: job)
        let json = String(decoding: try builder.encode(bundle: bundle), as: UTF8.self)

        let pkg = try packageBuilder.buildPackage(from: job, bundleJSON: json)
        defer { pkg.cleanup() }

        let manifestData = try Data(contentsOf: pkg.manifestFile)
        let decoded = try XCTUnwrap(decodeImportManifest(manifestData))
        XCTAssertEqual(decoded.importSummary.roomCount, 2)
        XCTAssertEqual(decoded.importSummary.reviewedRoomCount, 1)
    }

    func test_buildPackage_manifest_scannedRoomCountIsAccurate() throws {
        var job = ScanJob(propertyAddress: "14 Test Street, Anytown")
        var scanned = makeReviewedRoom(jobID: job.id)
        scanned.geometryCaptured = true
        var manual = ScannedRoom(jobID: job.id, name: "Manual Room")
        manual.isReviewed = true
        manual.geometryCaptured = false
        job.rooms = [scanned, manual]

        let bundle = builder.buildBundle(from: job)
        let json = String(decoding: try builder.encode(bundle: bundle), as: UTF8.self)

        let pkg = try packageBuilder.buildPackage(from: job, bundleJSON: json)
        defer { pkg.cleanup() }

        let manifestData = try Data(contentsOf: pkg.manifestFile)
        let decoded = try XCTUnwrap(decodeImportManifest(manifestData))
        XCTAssertEqual(decoded.importSummary.scannedRoomCount, 1,
                       "Only rooms with geometryCaptured = true count as scanned")
    }

    func test_buildPackage_manifest_validationWarningsIncluded() throws {
        var job = ScanJob(propertyAddress: "14 Test Street, Anytown")
        let unreviewedRoom = ScannedRoom(jobID: job.id, name: "Kitchen", isReviewed: false)
        job.rooms = [unreviewedRoom]
        let issues = builder.validate(job: job)

        let bundle = builder.buildBundle(from: job)
        let json = String(decoding: try builder.encode(bundle: bundle), as: UTF8.self)

        let pkg = try packageBuilder.buildPackage(from: job, bundleJSON: json, validationIssues: issues)
        defer { pkg.cleanup() }

        let manifestData = try Data(contentsOf: pkg.manifestFile)
        let decoded = try XCTUnwrap(decodeImportManifest(manifestData))
        XCTAssertFalse(decoded.importSummary.validationWarnings.isEmpty,
                       "Warnings from validate() must be surfaced in the manifest import summary")
        XCTAssertTrue(decoded.importSummary.validationWarnings.contains(where: { $0.contains("reviewed") }))
    }

    func test_buildPackage_manifest_noWarnings_whenJobIsClean() throws {
        var job = ScanJob(propertyAddress: "14 Test Street, Anytown")
        var room = makeReviewedRoom(jobID: job.id)
        room.addPhoto(TaggedPhoto(filename: "site.jpg", roomID: room.id))
        job.rooms = [room]
        let issues = builder.validate(job: job)

        let bundle = builder.buildBundle(from: job)
        let json = String(decoding: try builder.encode(bundle: bundle), as: UTF8.self)

        let pkg = try packageBuilder.buildPackage(from: job, bundleJSON: json, validationIssues: issues)
        defer { pkg.cleanup() }

        let manifestData = try Data(contentsOf: pkg.manifestFile)
        let decoded = try XCTUnwrap(decodeImportManifest(manifestData))
        XCTAssertTrue(decoded.importSummary.validationWarnings.isEmpty,
                      "A clean job must produce no validation warnings in the manifest")
        XCTAssertFalse(decoded.importSummary.hasBlockingIssues)
    }

    func test_buildPackage_manifest_hasBlockingIssues_whenAddressEmpty() throws {
        let job = ScanJob(propertyAddress: "")
        let issues = builder.validate(job: job)

        // Building a bundle from a job with no rooms still produces valid JSON
        // (the caller is responsible for checking validate() before sharing).
        let bundle = builder.buildBundle(from: job)
        let json = String(decoding: try builder.encode(bundle: bundle), as: UTF8.self)

        let pkg = try packageBuilder.buildPackage(from: job, bundleJSON: json, validationIssues: issues)
        defer { pkg.cleanup() }

        let manifestData = try Data(contentsOf: pkg.manifestFile)
        let decoded = try XCTUnwrap(decodeImportManifest(manifestData))
        XCTAssertTrue(decoded.importSummary.hasBlockingIssues,
                      "Blocking issues from validate() must be reflected in the manifest")
    }

    func test_buildPackage_manifest_jobReferencePreserved() throws {
        var job = ScanJob(propertyAddress: "14 Test Street, Anytown")
        job.jobReference = "JB-2024-0042"
        job.rooms = [makeReviewedRoom(jobID: job.id)]

        let bundle = builder.buildBundle(from: job)
        let json = String(decoding: try builder.encode(bundle: bundle), as: UTF8.self)

        let pkg = try packageBuilder.buildPackage(from: job, bundleJSON: json)
        defer { pkg.cleanup() }

        let manifestData = try Data(contentsOf: pkg.manifestFile)
        let decoded = try XCTUnwrap(decodeImportManifest(manifestData))
        XCTAssertEqual(decoded.jobReference, "JB-2024-0042",
                       "Job reference must be preserved in the manifest")
    }

    func test_buildPackage_manifest_totalObjectsIsAccurate() throws {
        var job = ScanJob(propertyAddress: "14 Test Street, Anytown")
        var room = makeReviewedRoom(jobID: job.id)
        room.taggedObjects = [
            TaggedObject(roomID: room.id, category: .boiler),
            TaggedObject(roomID: room.id, category: .radiator),
        ]
        job.rooms = [room]

        let bundle = builder.buildBundle(from: job)
        let json = String(decoding: try builder.encode(bundle: bundle), as: UTF8.self)

        let pkg = try packageBuilder.buildPackage(from: job, bundleJSON: json)
        defer { pkg.cleanup() }

        let manifestData = try Data(contentsOf: pkg.manifestFile)
        let decoded = try XCTUnwrap(decodeImportManifest(manifestData))
        XCTAssertEqual(decoded.importSummary.totalObjects, 2,
                       "totalObjects must match the tagged object count in the job")
    }

    func test_buildPackage_manifest_totalPhotosIsAccurate() throws {
        var job = ScanJob(propertyAddress: "14 Test Street, Anytown")
        var room = makeReviewedRoom(jobID: job.id)
        room.addPhoto(TaggedPhoto(filename: "room1.jpg", roomID: room.id))
        room.addPhoto(TaggedPhoto(filename: "room2.jpg", roomID: room.id))
        job.rooms = [room]
        job.photos = [TaggedPhoto(filename: "site.jpg")]

        let bundle = builder.buildBundle(from: job)
        let json = String(decoding: try builder.encode(bundle: bundle), as: UTF8.self)

        let pkg = try packageBuilder.buildPackage(from: job, bundleJSON: json)
        defer { pkg.cleanup() }

        let manifestData = try Data(contentsOf: pkg.manifestFile)
        let decoded = try XCTUnwrap(decodeImportManifest(manifestData))
        XCTAssertEqual(decoded.importSummary.totalPhotos, 3,
                       "totalPhotos must include both room-level and job-level photos")
    }

    func test_buildPackage_manifest_evidenceFieldsWhenNotIncluded() throws {
        let job = makeValidJob()
        let bundle = builder.buildBundle(from: job)
        let json = String(decoding: try builder.encode(bundle: bundle), as: UTF8.self)

        let pkg = try packageBuilder.buildPackage(from: job, bundleJSON: json, includeEvidence: false)
        defer { pkg.cleanup() }

        let manifestData = try Data(contentsOf: pkg.manifestFile)
        let decoded = try XCTUnwrap(decodeImportManifest(manifestData))
        XCTAssertFalse(decoded.evidenceIncluded,
                       "evidenceIncluded must be false when no evidence is packaged")
        XCTAssertEqual(decoded.evidenceFileCount, 0,
                       "evidenceFileCount must be 0 when no evidence is packaged")
    }

    func test_buildPackage_manifest_contentsIncludesBundleAndManifest() throws {
        let job = makeValidJob()
        let bundle = builder.buildBundle(from: job)
        let json = String(decoding: try builder.encode(bundle: bundle), as: UTF8.self)

        let pkg = try packageBuilder.buildPackage(from: job, bundleJSON: json)
        defer { pkg.cleanup() }

        let manifestData = try Data(contentsOf: pkg.manifestFile)
        let decoded = try XCTUnwrap(decodeImportManifest(manifestData))
        XCTAssertTrue(decoded.contents.contains("scan_bundle.json"),
                      "contents must include scan_bundle.json")
        XCTAssertTrue(decoded.contents.contains("manifest.json"),
                      "contents must include manifest.json")
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
