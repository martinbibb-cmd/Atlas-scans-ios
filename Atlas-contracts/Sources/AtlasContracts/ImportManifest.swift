import Foundation

// MARK: - ScanImportManifest

/// The typed representation of `manifest.json` in an Atlas Scan export package.
///
/// Written by Atlas Scan (iOS) when building an export package and read by Atlas
/// (recommendation) when importing a scan package.  Both sides share this type
/// via the AtlasContracts package so that the manifest format is contract-controlled.
///
/// Encoded to / decoded from JSON using the snake_case key convention
/// (e.g. ``importSummary`` ↔ `"import_summary"`).
public struct ScanImportManifest: Codable, Sendable {

    // MARK: Package identity

    /// Always `"AtlasScanPackageV1"` — lets the receiving side verify the package type
    /// before attempting a full decode.
    public let format: String

    /// Engineer-assigned job reference string (e.g. `"JB-2024-0042"`).
    public let jobReference: String

    /// Property address as entered by the engineer on site.
    public let propertyAddress: String

    /// ISO-8601 timestamp of when this package was generated on the capture device.
    public let generatedAt: String

    // MARK: Import summary

    /// Statistics and provenance flags for the Atlas import UI.
    ///
    /// Atlas surfaces these before hydrating the floor-plan draft so the user
    /// can review what is being imported, see any warnings, and decide whether
    /// to proceed.
    public let importSummary: ImportSummary

    // MARK: Evidence

    /// `true` when photo evidence files are included under `evidence/` in the package.
    public let evidenceIncluded: Bool

    /// Number of evidence photo files packaged; `0` when ``evidenceIncluded`` is `false`.
    public let evidenceFileCount: Int

    // MARK: Contents

    /// Relative file paths of every item in the package, including this manifest.
    public let contents: [String]

    // MARK: Init

    public init(
        format: String,
        jobReference: String,
        propertyAddress: String,
        generatedAt: String,
        importSummary: ImportSummary,
        evidenceIncluded: Bool,
        evidenceFileCount: Int,
        contents: [String]
    ) {
        self.format = format
        self.jobReference = jobReference
        self.propertyAddress = propertyAddress
        self.generatedAt = generatedAt
        self.importSummary = importSummary
        self.evidenceIncluded = evidenceIncluded
        self.evidenceFileCount = evidenceFileCount
        self.contents = contents
    }
}

// MARK: - ImportSummary

extension ScanImportManifest {

    /// Statistics and provenance flags surfaced in the Atlas import UI.
    ///
    /// Enables Atlas to present a pre-import summary —
    /// *"2 rooms · 5 objects · 3 photos · 1 warning"* — before hydrating the
    /// floor-plan draft, and to mark every imported item as scanned/manual and
    /// reviewed/unreviewed as appropriate.
    public struct ImportSummary: Codable, Sendable {

        /// Total number of rooms in the scan bundle.
        public let roomCount: Int

        /// Rooms that the engineer marked as reviewed before export.
        ///
        /// When `reviewedRoomCount` < ``roomCount``, the difference represents rooms
        /// that were not reviewed.  Atlas should mark those unreviewed rooms as pending
        /// review so the survey can continue from the imported draft.
        public let reviewedRoomCount: Int

        /// Rooms where geometry was captured by the LiDAR scanner.
        ///
        /// The remaining rooms (`roomCount - scannedRoomCount`) were manually
        /// sketched and should be flagged as inferred in Atlas.
        public let scannedRoomCount: Int

        /// Total tagged service objects across all rooms.
        public let totalObjects: Int

        /// Total evidence photos (job-level site photos + room-level photos combined).
        public let totalPhotos: Int

        /// `true` when the pre-export validation found at least one blocking issue.
        ///
        /// A package with blocking issues should not normally be imported; Atlas
        /// should surface a warning to the user before proceeding.
        public let hasBlockingIssues: Bool

        /// Human-readable warning messages raised during pre-export validation.
        ///
        /// Empty when the export passed without warnings.  Atlas shows these in the
        /// import review screen so the user can accept or discard the import with
        /// full knowledge of any data-quality concerns.
        public let validationWarnings: [String]

        public init(
            roomCount: Int,
            reviewedRoomCount: Int,
            scannedRoomCount: Int,
            totalObjects: Int,
            totalPhotos: Int,
            hasBlockingIssues: Bool,
            validationWarnings: [String]
        ) {
            self.roomCount = roomCount
            self.reviewedRoomCount = reviewedRoomCount
            self.scannedRoomCount = scannedRoomCount
            self.totalObjects = totalObjects
            self.totalPhotos = totalPhotos
            self.hasBlockingIssues = hasBlockingIssues
            self.validationWarnings = validationWarnings
        }
    }
}

// MARK: - Decode helper

/// Decodes raw `manifest.json` data from an Atlas Scan export package.
///
/// Used by the receiving Atlas side to parse the manifest before ingesting the
/// full scan bundle.
///
/// - Parameter data: Raw UTF-8 JSON read from `manifest.json`.
/// - Returns: The decoded ``ScanImportManifest``, or `nil` if decoding fails.
public func decodeImportManifest(_ data: Data) -> ScanImportManifest? {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try? decoder.decode(ScanImportManifest.self, from: data)
}
