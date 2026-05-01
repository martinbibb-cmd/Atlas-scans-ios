import Foundation
import AtlasContracts

// MARK: - WorkspaceExporter
//
// Assembles a Visit Workspace package from a CaptureSessionDraft and zips it
// as a <visitRef>.atlasvisit file for sharing to Atlas Mind.
//
// Package layout (inside the zip):
//   <visitRef>_workspace/
//     session_capture_v2.json   – full SessionCaptureV2 payload
//     workspace.json            – scaffold for Atlas Mind to identify the package
//     review_decisions.json     – empty decisions scaffold for Atlas Mind
//     photos/                   – evidence photo files (copied from PhotoStore)
//     floorplans/               – floor plan snapshot images
//
// Rules:
//   • No cloud logic — the package is assembled locally only.
//   • JSON-only export via CaptureSessionExporter remains unaffected.
//   • Source files that are missing on disk are skipped without error.
//   • Raw audio is never included.
//   • The package is written to the system temporary directory.

// MARK: - Workspace package result

/// The assembled Visit Workspace package, ready to share or save.
struct WorkspacePackageResult {
    /// Root folder of the assembled workspace package (intermediate build artefact).
    let packageURL: URL
    /// The final `.atlasvisit` zip archive ready to share to Atlas Mind.
    let atlasVisitURL: URL
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

        // 5. Write review_decisions.json scaffold
        let decisionsScaffold = ReviewDecisionsScaffold(
            visitReference: draft.visitReference,
            createdAt: iso8601.string(from: Date())
        )
        let decisionsData = try encodeDecisions(decisionsScaffold)
        let decisionsURL = packageURL.appendingPathComponent("review_decisions.json")
        try decisionsData.write(to: decisionsURL, options: .atomic)

        // 6. Zip the folder into a .atlasvisit archive
        let atlasVisitURL = fileManager.temporaryDirectory
            .appendingPathComponent("\(safeRef).atlasvisit")
        try? fileManager.removeItem(at: atlasVisitURL)
        try createZipArchive(from: packageURL, to: atlasVisitURL, keepParent: true)

        return WorkspacePackageResult(packageURL: packageURL, atlasVisitURL: atlasVisitURL)
    }

    // MARK: - Private helpers

    private static func encodeScaffold(_ scaffold: WorkspaceScaffold) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(scaffold)
    }

    private static func encodeDecisions(_ scaffold: ReviewDecisionsScaffold) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(scaffold)
    }

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // MARK: - ZIP archive writer
    //
    // Produces a spec-compliant ZIP archive (PKWARE App Note §V) using the
    // STORED (uncompressed) method — no third-party dependency required.
    // CRC-32 is computed with a pure-Swift reflected-polynomial implementation.
    //
    // Limitations: standard ZIP format (no ZIP64), so entry count must be
    // ≤ 65,535 and each file must be < 4 GB — both safe for on-device packages.

    // External file attribute bit indicating an MS-DOS directory entry.
    private static let msDosDirectoryAttribute: UInt32 = 0x0010_0000

    private static func createZipArchive(
        from sourceDirectory: URL,
        to destinationURL: URL,
        keepParent: Bool
    ) throws {
        let fm = FileManager.default
        // Normalise to avoid trailing-slash ambiguity in path prefix stripping.
        let basePath = (keepParent
            ? sourceDirectory.deletingLastPathComponent().path
            : sourceDirectory.path)
            .appending("/")

        guard let enumerator = fm.enumerator(
            at: sourceDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw CocoaError(.fileReadUnknown)
        }

        var entries: [(url: URL, isDirectory: Bool)] = []
        if keepParent {
            entries.append((url: sourceDirectory, isDirectory: true))
        }
        for case let item as URL in enumerator {
            let rv = try item.resourceValues(forKeys: [.isDirectoryKey])
            entries.append((url: item, isDirectory: rv.isDirectory ?? false))
        }

        guard entries.count <= Int(UInt16.max) else {
            throw CocoaError(.fileWriteUnknown)  // ZIP format limit: max 65,535 entries
        }

        var archive = Data()
        var centralDirectory = Data()

        for entry in entries {
            // Strip the base prefix to obtain the archive-relative path.
            let fullPath = entry.url.path
            let relativePath = fullPath.hasPrefix(basePath)
                ? String(fullPath.dropFirst(basePath.count))
                : entry.url.lastPathComponent
            let entryName = entry.isDirectory ? relativePath + "/" : relativePath
            let nameData = entryName.data(using: .utf8) ?? Data()

            let fileData: Data = entry.isDirectory ? Data() : (try Data(contentsOf: entry.url))
            guard fileData.count <= Int(UInt32.max) else {
                throw CocoaError(.fileWriteUnknown) // ZIP format limit: max ~4 GB per file
            }
            let crc: UInt32 = fileData.isEmpty ? 0 : computeCRC32(fileData)
            let localOffset = UInt32(archive.count)

            var lh = Data()
            lh.appendLE32(0x04034B50)                    // local file header sig
            lh.appendLE16(20)                             // version needed
            lh.appendLE16(0)                              // flags
            lh.appendLE16(0)                              // compression: STORED
            lh.appendLE16(0)                              // mod time
            lh.appendLE16(0)                              // mod date
            lh.appendLE32(crc)
            lh.appendLE32(UInt32(fileData.count))         // compressed size
            lh.appendLE32(UInt32(fileData.count))         // uncompressed size
            lh.appendLE16(UInt16(nameData.count))
            lh.appendLE16(0)                              // extra field length
            lh.append(nameData)
            archive.append(lh)
            archive.append(fileData)

            var cd = Data()
            cd.appendLE32(0x02014B50)                    // central dir file header sig
            cd.appendLE16(20)                             // version made by
            cd.appendLE16(20)                             // version needed
            cd.appendLE16(0)                              // flags
            cd.appendLE16(0)                              // compression: STORED
            cd.appendLE16(0)                              // mod time
            cd.appendLE16(0)                              // mod date
            cd.appendLE32(crc)
            cd.appendLE32(UInt32(fileData.count))         // compressed size
            cd.appendLE32(UInt32(fileData.count))         // uncompressed size
            cd.appendLE16(UInt16(nameData.count))
            cd.appendLE16(0)                              // extra field length
            cd.appendLE16(0)                              // file comment length
            cd.appendLE16(0)                              // disk number start
            cd.appendLE16(0)                              // internal file attributes
            cd.appendLE32(entry.isDirectory ? msDosDirectoryAttribute : 0)
            cd.appendLE32(localOffset)
            cd.append(nameData)
            centralDirectory.append(cd)
        }

        let cdOffset = UInt32(archive.count)
        archive.append(centralDirectory)

        var eocd = Data()
        eocd.appendLE32(0x06054B50)                      // end of central dir sig
        eocd.appendLE16(0)                                // disk number
        eocd.appendLE16(0)                                // disk with start of CD
        eocd.appendLE16(UInt16(entries.count))            // entries on disk
        eocd.appendLE16(UInt16(entries.count))            // total entries
        eocd.appendLE32(UInt32(centralDirectory.count))   // size of CD
        eocd.appendLE32(cdOffset)                         // offset of CD start
        eocd.appendLE16(0)                                // comment length
        archive.append(eocd)

        try archive.write(to: destinationURL, options: .atomic)
    }

    /// Standard CRC-32 checksum (ISO 3309 / PKZIP reflected polynomial 0xEDB88320).
    private static func computeCRC32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            var c = (crc ^ UInt32(byte)) & 0xFF
            for _ in 0..<8 {
                c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1
            }
            crc = c ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}

// MARK: - Data little-endian helpers

private extension Data {
    mutating func appendLE16(_ value: UInt16) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }
    mutating func appendLE32(_ value: UInt32) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }
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

// MARK: - ReviewDecisionsScaffold

/// Scaffold `review_decisions.json` written into every `.atlasvisit` package.
///
/// Atlas Mind reads this file to track per-artefact review decisions made after
/// import. The Scan app always writes an empty decisions array; Mind populates
/// it during the review workflow.
struct ReviewDecisionsScaffold: Codable {

    /// Schema version of this manifest format.
    let schemaVersion: String

    /// Engineer-assigned visit / job reference matching the parent workspace.
    let visitReference: String

    /// ISO-8601 timestamp of when the package was assembled.
    let createdAt: String

    /// Per-artefact review decisions. Empty on initial export from Scan.
    let decisions: [String]

    init(visitReference: String, createdAt: String) {
        self.schemaVersion = "1.0"
        self.visitReference = visitReference
        self.createdAt = createdAt
        self.decisions = []
    }
}
