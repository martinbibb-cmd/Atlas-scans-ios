import Foundation

// MARK: - VisitHandoffPackV1
//
// Shared handoff contract used to pass visit context between Atlas Scan
// and Atlas Mind in either direction.
//
// Usage:
//   • Scan → Mind: sourceApp = .scan; capturePackageRef = <filename>.atlasvisit
//   • Mind → Scan: sourceApp = .mind; visitId = <remote visit id>
//
// Wire format: JSON, camelCase keys.
// Shared by atlas-scans-ios (Swift) and atlas-recommendation (TypeScript/Next.js).

// MARK: - VisitHandoffPackV1

/// The handoff envelope passed between Atlas Scan and Atlas Mind.
///
/// The receiving app should validate `schemaVersion` before consuming the
/// payload.  Both apps share this type via AtlasContracts so that the wire
/// format is contract-controlled.
public struct VisitHandoffPackV1: Codable, Sendable {

    // MARK: Schema identity

    /// Always `"1.0"` for this version of the contract.
    public let schemaVersion: String

    // MARK: Visit identity

    /// Cross-system visit identifier.
    ///
    /// When produced by Atlas Scan this equals the engineer-assigned
    /// `visitReference` (e.g. `"JOB-2025-0042"`).  When produced by Atlas Mind
    /// this is the remote visit UUID assigned by the Recommendations backend.
    public let visitId: String

    /// The app that created this handoff pack.
    public let sourceApp: HandoffSourceApp

    // MARK: Visit metadata

    /// Engineer-assigned visit / job reference (e.g. `"JOB-2025-0042"`).
    public let visitReference: String

    /// Optional property address for the visit.
    public let propertyAddress: String?

    /// Optional customer name for the visit.
    public let customerName: String?

    // MARK: Capture package

    /// Relative or absolute reference to the `.atlasvisit` package file.
    ///
    /// When the handoff travels via a URL query parameter this is the filename
    /// of the package that the receiving app should import (e.g. after the
    /// user shares the file via AirDrop or saves it to iCloud Drive).
    /// Nil when no package is attached to the handoff.
    public let capturePackageRef: String?

    /// UUID of the `SessionCaptureV2` session embedded in the capture package.
    /// Nil when no session has been captured yet.
    public let sessionId: String?

    // MARK: Review status

    /// Where the visit currently sits in the review workflow.
    public let reviewStatus: VisitHandoffReviewStatus

    // MARK: Hardware patches

    /// Optional hardware definition overrides from Atlas Mind.
    ///
    /// When Mind sends a visit handoff to Atlas Scan it may include custom or
    /// legacy appliance definitions not present in the bundled static registry.
    /// The iOS app merges these into its runtime hardware registry, preferring
    /// patch definitions over static ones when `modelId` keys collide.
    /// `nil` when no overrides are needed (the common case).
    public let hardwarePatches: HardwarePatchV1?

    // MARK: Timestamps

    /// ISO-8601 timestamp of when this handoff pack was generated.
    public let exportedAt: String

    // MARK: Init

    public init(
        visitId: String,
        sourceApp: HandoffSourceApp,
        visitReference: String,
        propertyAddress: String? = nil,
        customerName: String? = nil,
        capturePackageRef: String? = nil,
        sessionId: String? = nil,
        reviewStatus: VisitHandoffReviewStatus = .pendingReview,
        hardwarePatches: HardwarePatchV1? = nil,
        exportedAt: String
    ) {
        self.schemaVersion = "1.0"
        self.visitId = visitId
        self.sourceApp = sourceApp
        self.visitReference = visitReference
        self.propertyAddress = propertyAddress
        self.customerName = customerName
        self.capturePackageRef = capturePackageRef
        self.sessionId = sessionId
        self.reviewStatus = reviewStatus
        self.hardwarePatches = hardwarePatches
        self.exportedAt = exportedAt
    }
}

// MARK: - HandoffSourceApp

/// The app that originated a visit handoff pack.
public enum HandoffSourceApp: String, Codable, Sendable {
    /// Handoff originated from Atlas Scan (iOS capture app).
    case scan = "scan"
    /// Handoff originated from Atlas Mind (web recommendations app).
    case mind = "mind"
}

// MARK: - VisitHandoffReviewStatus

/// Where the visit sits in the review workflow at the time of handoff.
public enum VisitHandoffReviewStatus: String, Codable, Sendable {
    /// Capture has not yet started.
    case pendingCapture = "pending_capture"
    /// Capture is complete; awaiting review in Atlas Mind.
    case pendingReview = "pending_review"
    /// Review is in progress inside Atlas Mind.
    case inReview = "in_review"
    /// Review is complete; a recommendation has been generated.
    case reviewComplete = "review_complete"
}

// MARK: - Encode / decode helpers

/// Encodes a ``VisitHandoffPackV1`` to a compact JSON string suitable for
/// embedding in a URL query parameter (base-64 encoded).
///
/// - Returns: Base-64 encoded UTF-8 JSON, or `nil` on encoding failure.
public func encodeHandoffPack(_ pack: VisitHandoffPackV1) -> String? {
    guard let data = try? JSONEncoder().encode(pack) else { return nil }
    return data.base64EncodedString()
}

/// Decodes a ``VisitHandoffPackV1`` from a base-64 encoded JSON string.
///
/// - Parameter encoded: Base-64 encoded UTF-8 JSON produced by ``encodeHandoffPack(_:)``.
/// - Returns: The decoded pack, or `nil` when decoding fails or the schema version is unsupported.
public func decodeHandoffPack(_ encoded: String) -> VisitHandoffPackV1? {
    guard
        let data = Data(base64Encoded: encoded),
        let pack = try? JSONDecoder().decode(VisitHandoffPackV1.self, from: data),
        pack.schemaVersion == "1.0"
    else { return nil }
    return pack
}
