import XCTest
import AtlasContracts
@testable import AtlasScan

// MARK: - WorkspaceExporterTests
//
// Tests for WorkspaceExporter — the workspace package assembler.
//
// Covers:
//   - Package directory is created in the temp directory
//   - session_capture_v2.json is written and contains the expected JSON
//   - workspace.json scaffold is written with correct fields
//   - photos/ directory is created when photos are present
//   - floorplans/ directory is created when floor plan snapshots are present
//   - Missing source files are skipped without error
//   - A draft with neither photos nor floor plans produces no extra subdirectories

final class WorkspaceExporterTests: XCTestCase {

    // MARK: - Helpers

    private func makeDraft(visitReference: String = "JOB-WS-TEST") -> CaptureSessionDraft {
        CaptureSessionStore.newSession(visitReference: visitReference)
    }

    private func draftWithRoomScan(visitReference: String = "JOB-WS-TEST") -> CaptureSessionDraft {
        var draft = makeDraft(visitReference: visitReference)
        var scan = CapturedRoomScanDraft()
        scan.roomLabel = "Kitchen"
        draft.roomScans.append(scan)
        return draft
    }

    private func exportPackage(
        _ draft: CaptureSessionDraft,
        photosDir: URL = FileManager.default.temporaryDirectory,
        floorplansDir: URL = FileManager.default.temporaryDirectory
    ) throws -> WorkspacePackageResult {
        let result = try CaptureSessionExporter.export(draft)
        return try WorkspaceExporter.exportPackage(
            draft,
            jsonData: result.jsonData,
            photosDirectory: photosDir,
            floorplansDirectory: floorplansDir
        )
    }

    // MARK: - Package directory

    func test_exportPackage_createsDirectory() throws {
        let draft = draftWithRoomScan()
        let result = try exportPackage(draft)
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: result.packageURL.path, isDirectory: &isDir)
        XCTAssertTrue(exists, "Package directory must exist")
        XCTAssertTrue(isDir.boolValue, "Package URL must point to a directory")
    }

    func test_exportPackage_directoryNameContainsVisitReference() throws {
        let draft = draftWithRoomScan(visitReference: "JOB-2025-0001")
        let result = try exportPackage(draft)
        XCTAssertTrue(result.packageURL.lastPathComponent.contains("JOB-2025-0001"))
    }

    func test_exportPackage_directoryNameHasWorkspaceSuffix() throws {
        let draft = draftWithRoomScan()
        let result = try exportPackage(draft)
        XCTAssertTrue(result.packageURL.lastPathComponent.hasSuffix("_workspace"))
    }

    func test_exportPackage_overwritesExistingPackage() throws {
        let draft = draftWithRoomScan()
        let first = try exportPackage(draft)
        // Write a sentinel file inside the first package.
        let sentinel = first.packageURL.appendingPathComponent("sentinel.txt")
        try "sentinel".write(to: sentinel, atomically: true, encoding: .utf8)
        // Export again — the old directory should be replaced.
        let second = try exportPackage(draft)
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.packageURL
            .appendingPathComponent("sentinel.txt").path),
                       "Re-export must clear the previous package")
    }

    // MARK: - session_capture_v2.json

    func test_exportPackage_writesSessionCaptureJSON() throws {
        let draft = draftWithRoomScan()
        let result = try exportPackage(draft)
        let jsonURL = result.packageURL.appendingPathComponent("session_capture_v2.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: jsonURL.path))
    }

    func test_exportPackage_sessionCaptureJSONIsValid() throws {
        let draft = draftWithRoomScan(visitReference: "JOB-JSON-VALID")
        let result = try exportPackage(draft)
        let jsonURL = result.packageURL.appendingPathComponent("session_capture_v2.json")
        let data = try Data(contentsOf: jsonURL)
        let decoded = try JSONDecoder().decode(SessionCaptureV2.self, from: data)
        XCTAssertEqual(decoded.visitReference, "JOB-JSON-VALID")
        XCTAssertEqual(decoded.schemaVersion, currentSessionCaptureVersion)
    }

    // MARK: - workspace.json scaffold

    func test_exportPackage_writesWorkspaceScaffold() throws {
        let draft = draftWithRoomScan()
        let result = try exportPackage(draft)
        let scaffoldURL = result.packageURL.appendingPathComponent("workspace.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: scaffoldURL.path))
    }

    func test_exportPackage_scaffoldContainsVisitReference() throws {
        let draft = draftWithRoomScan(visitReference: "JOB-SCAFFOLD-CHECK")
        let result = try exportPackage(draft)
        let scaffoldURL = result.packageURL.appendingPathComponent("workspace.json")
        let data = try Data(contentsOf: scaffoldURL)
        let scaffold = try JSONDecoder().decode(WorkspaceScaffold.self, from: data)
        XCTAssertEqual(scaffold.visitReference, "JOB-SCAFFOLD-CHECK")
    }

    func test_exportPackage_scaffoldTypeIsAtlasVisitWorkspace() throws {
        let draft = draftWithRoomScan()
        let result = try exportPackage(draft)
        let scaffoldURL = result.packageURL.appendingPathComponent("workspace.json")
        let data = try Data(contentsOf: scaffoldURL)
        let scaffold = try JSONDecoder().decode(WorkspaceScaffold.self, from: data)
        XCTAssertEqual(scaffold.type, "atlas.visit.workspace")
    }

    func test_exportPackage_scaffoldSessionCaptureRefIsCorrect() throws {
        let draft = draftWithRoomScan()
        let result = try exportPackage(draft)
        let scaffoldURL = result.packageURL.appendingPathComponent("workspace.json")
        let data = try Data(contentsOf: scaffoldURL)
        let scaffold = try JSONDecoder().decode(WorkspaceScaffold.self, from: data)
        XCTAssertEqual(scaffold.sessionCaptureRef, "session_capture_v2.json")
    }

    func test_exportPackage_scaffoldSchemaVersionIsSet() throws {
        let draft = draftWithRoomScan()
        let result = try exportPackage(draft)
        let scaffoldURL = result.packageURL.appendingPathComponent("workspace.json")
        let data = try Data(contentsOf: scaffoldURL)
        let scaffold = try JSONDecoder().decode(WorkspaceScaffold.self, from: data)
        XCTAssertFalse(scaffold.schemaVersion.isEmpty)
    }

    // MARK: - photos/ directory

    func test_exportPackage_noPhotos_noPhotosDirectory() throws {
        var draft = draftWithRoomScan()
        draft.photos = []
        let result = try exportPackage(draft)
        let photosDir = result.packageURL.appendingPathComponent("photos")
        XCTAssertFalse(FileManager.default.fileExists(atPath: photosDir.path),
                       "photos/ directory must not be created when there are no photos")
    }

    func test_exportPackage_withPhotos_createsPhotosDirectory() throws {
        var draft = makeDraft()
        draft.photos.append(CapturedPhotoDraft(localFilename: "photo1.jpg"))

        // Write a dummy photo file in a temp source directory.
        let sourceDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ws_test_photos_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let sourceFile = sourceDir.appendingPathComponent("photo1.jpg")
        try Data([0xFF, 0xD8, 0xFF]).write(to: sourceFile) // minimal JPEG header

        let exportResult = try CaptureSessionExporter.export(draft)
        let result = try WorkspaceExporter.exportPackage(
            draft,
            jsonData: exportResult.jsonData,
            photosDirectory: sourceDir,
            floorplansDirectory: sourceDir
        )

        let photosDir = result.packageURL.appendingPathComponent("photos")
        XCTAssertTrue(FileManager.default.fileExists(atPath: photosDir.path))

        let copiedFile = photosDir.appendingPathComponent("photo1.jpg")
        XCTAssertTrue(FileManager.default.fileExists(atPath: copiedFile.path))

        // Clean up.
        try? FileManager.default.removeItem(at: sourceDir)
    }

    func test_exportPackage_missingPhotoFile_skippedGracefully() throws {
        var draft = makeDraft()
        draft.photos.append(CapturedPhotoDraft(localFilename: "missing_photo.jpg"))

        let emptyDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ws_test_empty_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: emptyDir, withIntermediateDirectories: true)

        let exportResult = try CaptureSessionExporter.export(draft)
        XCTAssertNoThrow(
            try WorkspaceExporter.exportPackage(
                draft,
                jsonData: exportResult.jsonData,
                photosDirectory: emptyDir,
                floorplansDirectory: emptyDir
            ),
            "Missing source photo must not cause the export to throw"
        )

        // Clean up.
        try? FileManager.default.removeItem(at: emptyDir)
    }

    // MARK: - floorplans/ directory

    func test_exportPackage_noFloorplanSnapshots_noFloorplansDirectory() throws {
        var draft = draftWithRoomScan()
        draft.floorPlanSnapshots = []
        let result = try exportPackage(draft)
        let floorplansDir = result.packageURL.appendingPathComponent("floorplans")
        XCTAssertFalse(FileManager.default.fileExists(atPath: floorplansDir.path),
                       "floorplans/ directory must not be created when there are no snapshots")
    }

    func test_exportPackage_withFloorplanSnapshots_createsFloorplansDirectory() throws {
        var draft = makeDraft()
        let snapshot = CapturedFloorPlanSnapshotDraft(imageRef: "fp_kitchen.jpg")
        draft.floorPlanSnapshots.append(snapshot)

        // Write a dummy snapshot file in a temp source directory.
        let sourceDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ws_test_fps_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let sourceFile = sourceDir.appendingPathComponent("fp_kitchen.jpg")
        try Data([0xFF, 0xD8, 0xFF]).write(to: sourceFile)

        let exportResult = try CaptureSessionExporter.export(draft)
        let result = try WorkspaceExporter.exportPackage(
            draft,
            jsonData: exportResult.jsonData,
            photosDirectory: sourceDir,
            floorplansDirectory: sourceDir
        )

        let floorplansDir = result.packageURL.appendingPathComponent("floorplans")
        XCTAssertTrue(FileManager.default.fileExists(atPath: floorplansDir.path))

        let copiedFile = floorplansDir.appendingPathComponent("fp_kitchen.jpg")
        XCTAssertTrue(FileManager.default.fileExists(atPath: copiedFile.path))

        // Clean up.
        try? FileManager.default.removeItem(at: sourceDir)
    }

    // MARK: - Visit reference sanitisation

    func test_exportPackage_visitReferenceWithSpecialChars_packageCreated() throws {
        let draft = draftWithRoomScan(visitReference: "JOB/2025:TEST")
        XCTAssertNoThrow(try exportPackage(draft),
                         "Special characters in visit reference must not prevent package creation")
    }
}
