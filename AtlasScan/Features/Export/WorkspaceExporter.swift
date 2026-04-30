import Foundation
import AtlasContracts

// MARK: - WorkspaceExporter
//
// Assembles a Visit Workspace package folder from a CaptureSessionDraft.
//
// Package layout:
//   <visitRef>_workspace/
//     session_capture_v2.json   – full SessionCaptureV2 payload
//     workspace.json            – scaffold for Atlas Mind to identify the package
//     photos/                   – evidence photo files (copied from PhotoStore)
//     floorplans/               – floor plan snapshot images
//
// Rules:
//   • No cloud logic — the package is assembled locally only.
//   • JSON-only export via CaptureSessionExporter remains unaffected.
//   • Source files that are missing on disk are skipped without error.
//   • The package is written to the system temporary directory.

// MARK: - Workspace package result

/// The assembled Visit Workspace package, ready to share or save.
struct WorkspacePackageResult {
    /// Root folder of the assembled workspace package.
    let packageURL: URL
}

// MARK: - WorkspaceExporter

enum WorkspaceExporter {

    // MARK: - Export

    /// Assembles a workspace package folder from a capture session draft.
    ///
    /// - Parameters:
    ///   - draft: The capture session to package.
    ///   - jsonData: Pre-encoded `session_capture_v2.json` bytes produced by
    ///     `CaptureSessionExporter.export(_:)`.
    ///   - photosDirectory: Source directory for evidence photos.
    ///     Defaults to `PhotoStore.shared.photosDirectory`.
    ///   - floorplansDirectory: Source directory for floor plan snapshot images.
    ///     Defaults to `PhotoStore.shared.photosDirectory` (snapshots are
    ///     stored alongside photos in the same folder).
    /// - Returns: A `WorkspacePackageResult` pointing to the assembled folder.
    /// - Throws: `FileManager` or JSON encoding errors encountered during assembly.
    static func exportPackage(
        _ draft: CaptureSessionDraft,
        jsonData: Data,
        photosDirectory: URL = PhotoStore.shared.photosDirectory,
        floorplansDirectory: URL = PhotoStore.shared.photosDirectory
    ) throws -> WorkspacePackageResult {
        let fileManager = FileManager.default

        // Sanitise the visit reference for use as a directory name.
        let safeRef = draft.visitReference
            .components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|"))
            .joined(separator: "_")
        let packageName = "\(safeRef)_workspace"
        let packageURL = fileManager.temporaryDirectory
            .appendingPathComponent(packageName, isDirectory: true)

        // Remove any pre-existing package with the same name before assembling.
        try? fileManager.removeItem(at: packageURL)
        try fileManager.createDirectory(at: packageURL, withIntermediateDirectories: true)

        // 1. Write session_capture_v2.json
        let jsonURL = packageURL.appendingPathComponent("session_capture_v2.json")
        try jsonData.write(to: jsonURL, options: .atomic)

        // 2. Write workspace.json scaffold
        let scaffold = WorkspaceScaffold(
            visitReference: draft.visitReference,
            sessionCaptureRef: "session_capture_v2.json",
            createdAt: iso8601.string(from: Date())
        )
        let scaffoldData = try encodeScaffold(scaffold)
        let scaffoldURL = packageURL.appendingPathComponent("workspace.json")
        try scaffoldData.write(to: scaffoldURL, options: .atomic)

        // 3. Copy evidence photos
        if !draft.photos.isEmpty {
            let photosDestDir = packageURL.appendingPathComponent("photos", isDirectory: true)
            try fileManager.createDirectory(at: photosDestDir, withIntermediateDirectories: true)
            for photo in draft.photos {
                let source = photosDirectory.appendingPathComponent(photo.localFilename)
                let dest = photosDestDir.appendingPathComponent(photo.localFilename)
                if fileManager.fileExists(atPath: source.path) {
                    try? fileManager.copyItem(at: source, to: dest)
                }
            }
        }

        // 4. Copy floor plan snapshot images
        if !draft.floorPlanSnapshots.isEmpty {
            let floorplansDestDir = packageURL.appendingPathComponent("floorplans", isDirectory: true)
            try fileManager.createDirectory(at: floorplansDestDir, withIntermediateDirectories: true)
            for snapshot in draft.floorPlanSnapshots {
                let source = floorplansDirectory.appendingPathComponent(snapshot.imageRef)
                let dest = floorplansDestDir.appendingPathComponent(snapshot.imageRef)
                if fileManager.fileExists(atPath: source.path) {
                    try? fileManager.copyItem(at: source, to: dest)
                }
            }
        }

        return WorkspacePackageResult(packageURL: packageURL)
    }

    // MARK: - Private helpers

    private static func encodeScaffold(_ scaffold: WorkspaceScaffold) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(scaffold)
    }

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

// MARK: - WorkspaceScaffold

/// Minimal `workspace.json` manifest that Atlas Mind uses to identify and
/// open the folder as a Visit Workspace.
struct WorkspaceScaffold: Codable {

    /// Schema version of this manifest format.
    let schemaVersion: String

    /// Type discriminator recognised by Atlas Mind.
    let type: String

    /// Engineer-assigned visit / job reference (e.g. "JOB-2025-001").
    let visitReference: String

    /// Relative path to the `SessionCaptureV2` JSON file within the package.
    let sessionCaptureRef: String

    /// ISO-8601 timestamp of when the workspace package was assembled.
    let createdAt: String

    init(visitReference: String, sessionCaptureRef: String, createdAt: String) {
        self.schemaVersion = "1.0"
        self.type = "atlas.visit.workspace"
        self.visitReference = visitReference
        self.sessionCaptureRef = sessionCaptureRef
        self.createdAt = createdAt
    }
}
