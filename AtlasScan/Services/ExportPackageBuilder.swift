import Foundation
import AtlasContracts

// MARK: - ExportPackage
//
// A temporary on-disk export package produced by ExportPackageBuilder.
// The caller is responsible for calling cleanup() once the package is no
// longer needed (e.g. after a share sheet or save-to-files action is dismissed).

struct ExportPackage {
    /// Root directory of the package; contains all packaged files.
    let directory: URL
    /// The ScanBundleV1 JSON file (always present).
    let bundleFile: URL
    /// The manifest JSON file describing the package contents.
    let manifestFile: URL
    /// Evidence photo files copied into the package (empty when not requested).
    let evidenceFiles: [URL]

    /// Removes the temporary package directory and all its contents from disk.
    /// Safe to call multiple times.
    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }
}

// MARK: - ExportPackageBuilder
//
// Builds a temporary export package from a ScanJob and its pre-encoded
// ScanBundleV1 JSON.  Keeps JSON contract and evidence packaging clearly
// separated: the bundle file is always scan_bundle.json; photos (if requested)
// go into an evidence/ subdirectory.
//
// Temp layout:
//   AtlasScanExports/<job_ref>_<timestamp>/
//     scan_bundle.json       ← contract-valid ScanBundleV1 JSON
//     manifest.json          ← package metadata / content listing
//     evidence/              ← photo files (only when includeEvidence = true)
//       <filename>.jpg
//       …

final class ExportPackageBuilder {

    // MARK: - Package generation

    /// Builds a temporary export package for the given job.
    ///
    /// - Parameters:
    ///   - job:              The scan job whose data is being exported.
    ///   - bundleJSON:       Pre-encoded, contract-valid ScanBundleV1 JSON string.
    ///   - includeEvidence:  When true, copies linked photo files into the package.
    ///   - validationIssues: Issues from `ExportBuilder.validate(job:)`.  Warnings
    ///                       are surfaced in the manifest import summary so Atlas can
    ///                       show them before hydrating the floor-plan draft.
    /// - Returns: An `ExportPackage` wrapping the temporary directory on disk.
    /// - Throws:  If temp directory creation or any file write fails.
    func buildPackage(
        from job: ScanJob,
        bundleJSON: String,
        includeEvidence: Bool = false,
        validationIssues: [ValidationIssue] = []
    ) throws -> ExportPackage {
        let packageDir = try makePackageDirectory(for: job)

        // 1. Write the ScanBundleV1 JSON.
        let bundleFile = packageDir.appendingPathComponent("scan_bundle.json")
        try bundleJSON.write(to: bundleFile, atomically: true, encoding: .utf8)

        // 2. Copy evidence files (optional).
        var copiedEvidence: [URL] = []
        if includeEvidence {
            let evidenceDir = packageDir.appendingPathComponent("evidence")
            try FileManager.default.createDirectory(
                at: evidenceDir,
                withIntermediateDirectories: true
            )
            copiedEvidence = copyEvidenceFiles(for: job, into: evidenceDir)
        }

        // 3. Write the manifest.
        let manifestFile = packageDir.appendingPathComponent("manifest.json")
        let manifest = buildManifest(for: job, evidenceFiles: copiedEvidence, validationIssues: validationIssues)
        let manifestEncoder = JSONEncoder()
        manifestEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        manifestEncoder.keyEncodingStrategy = .convertToSnakeCase
        let manifestData = try manifestEncoder.encode(manifest)
        try manifestData.write(to: manifestFile)

        return ExportPackage(
            directory: packageDir,
            bundleFile: bundleFile,
            manifestFile: manifestFile,
            evidenceFiles: copiedEvidence
        )
    }

    // MARK: - Temp file cleanup

    /// Removes all packages created by this builder under the shared temp root.
    /// Call on app launch or when storage pressure requires it.
    static func cleanupAllTempPackages() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AtlasScanExports")
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Private helpers

    private func makePackageDirectory(for job: ScanJob) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AtlasScanExports")
        let timestamp = Int(Date().timeIntervalSince1970)
        let dir = root.appendingPathComponent("\(job.safeFileNameReference)_\(timestamp)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Copies all photo files (job-level + room-level) from the app's Documents
    /// Photos directory into `dir`.  Silently skips any file that cannot be read.
    private func copyEvidenceFiles(for job: ScanJob, into dir: URL) -> [URL] {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let photosRoot = docs.appendingPathComponent("Photos")
        let allPhotos = job.photos + job.rooms.flatMap(\.photos)
        var copied: [URL] = []
        for photo in allPhotos {
            let src = photosRoot.appendingPathComponent(photo.filename)
            let dst = dir.appendingPathComponent(photo.filename)
            if (try? FileManager.default.copyItem(at: src, to: dst)) != nil {
                copied.append(dst)
            }
        }
        return copied
    }

    private static let iso8601: ISO8601DateFormatter = ISO8601DateFormatter()

    /// Builds a typed ``ScanImportManifest`` describing the package contents.
    ///
    /// The manifest is the first file the receiving Atlas side reads; it carries
    /// the import summary (room counts, review state, validation warnings) so
    /// Atlas can show a pre-import review screen before hydrating the floor-plan draft.
    private func buildManifest(
        for job: ScanJob,
        evidenceFiles: [URL],
        validationIssues: [ValidationIssue]
    ) -> ScanExportManifest {
        let allPhotos = job.photos + job.rooms.flatMap(\.photos)
        var contents: [String] = ["scan_bundle.json", "manifest.json"]
        contents += evidenceFiles.map { "evidence/\($0.lastPathComponent)" }

        let warnings = validationIssues.compactMap { $0.severity == .warning ? $0.message : nil }
        let hasBlockers = validationIssues.contains { $0.severity == .blocking }

        let summary = ScanExportManifest.ImportSummary(
            roomCount: job.rooms.count,
            reviewedRoomCount: job.rooms.filter(\.isReviewed).count,
            scannedRoomCount: job.rooms.filter(\.geometryCaptured).count,
            totalObjects: job.totalTaggedObjects,
            totalPhotos: allPhotos.count,
            hasBlockingIssues: hasBlockers,
            validationWarnings: warnings
        )

        return ScanExportManifest(
            format: "AtlasScanPackageV1",
            jobReference: job.jobReference,
            propertyAddress: job.propertyAddress,
            generatedAt: Self.iso8601.string(from: Date()),
            importSummary: summary,
            evidenceIncluded: !evidenceFiles.isEmpty,
            evidenceFileCount: evidenceFiles.count,
            contents: contents
        )
    }
}

