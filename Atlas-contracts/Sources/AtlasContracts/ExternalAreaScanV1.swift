import Foundation

// MARK: - ExternalAreaScanV1
//
// Exterior evidence capture for a single external area around a property.
//
// Design rules:
//   • One ExternalAreaScanDraft per exterior area surveyed (e.g. rear flue exit).
//   • Carries evidence-only artefacts: object pins, measurement lines, photos.
//   • No clearance pass/fail — Atlas Mind owns all clearance rule evaluation.
//   • Maps into SessionCaptureV2.externalAreaScans at export time.
//   • pointCloudAssetId is a path reference only; raw scan geometry is not inlined.

// MARK: - ExternalAreaScanV1

/// Exterior-area evidence captured by the engineer during a site visit.
///
/// Typically used to record the location and context of the boiler flue terminal,
/// nearby openings, and potential obstructions — without performing any
/// clearance calculation.  Atlas Mind evaluates clearance downstream.
public struct ExternalAreaScanV1: Codable, Sendable {

    // MARK: Identity

    /// Stable UUID for this external area scan record.
    public let id: String

    /// UUID of the parent visit.
    public let visitId: String

    /// Engineer-assigned label (e.g. "Rear elevation – flue exit").
    public let label: String?

    /// ISO-8601 timestamp of when the scan was captured.
    public let capturedAt: String

    // MARK: Review

    /// Engineer review status for this area scan.
    public let reviewStatus: String

    // MARK: Artefacts

    /// Evidence photos captured for this area.
    public let photos: [String]

    /// Typed object pins placed in this area.
    public let objectPins: [ExternalObjectPinV1]

    /// Measurement lines drawn between two points in this area.
    public let measurements: [ExternalMeasurementLineV1]

    /// Optional path reference to a point-cloud or 3D scan asset.
    public let pointCloudAssetId: String?

    // MARK: Init

    public init(
        id: String,
        visitId: String,
        label: String?,
        capturedAt: String,
        reviewStatus: String,
        photos: [String],
        objectPins: [ExternalObjectPinV1],
        measurements: [ExternalMeasurementLineV1],
        pointCloudAssetId: String? = nil
    ) {
        self.id = id
        self.visitId = visitId
        self.label = label
        self.capturedAt = capturedAt
        self.reviewStatus = reviewStatus
        self.photos = photos
        self.objectPins = objectPins
        self.measurements = measurements
        self.pointCloudAssetId = pointCloudAssetId
    }
}

// MARK: - ExternalObjectPinV1

/// A typed object pin placed in an external area.
///
/// Carries "what is here" only — no clearance calculations,
/// no engineering outputs.
public struct ExternalObjectPinV1: Codable, Sendable {

    // MARK: Identity

    /// Stable UUID for this pin record.
    public let id: String

    /// Object type raw value (e.g. `"flue_terminal"`, `"window_opening"`).
    public let type: String

    /// Optional free-text label set by the engineer.
    public let label: String?

    // MARK: Evidence links

    /// UUIDs of evidence photos linked to this pin.
    public let linkedPhotoIds: [String]

    // MARK: Position

    /// Approximate 3-D position if captured from a placement interaction.
    public let approximatePositionRef: ScanPoint3D?

    // MARK: Init

    public init(
        id: String,
        type: String,
        label: String?,
        linkedPhotoIds: [String],
        approximatePositionRef: ScanPoint3D? = nil
    ) {
        self.id = id
        self.type = type
        self.label = label
        self.linkedPhotoIds = linkedPhotoIds
        self.approximatePositionRef = approximatePositionRef
    }
}

// MARK: - ExternalMeasurementLineV1

/// A measurement line drawn between two reference points in an external area.
///
/// Used to record distances between the flue terminal and openings/boundaries.
/// No clearance pass/fail is computed here — Atlas Mind evaluates clearance rules.
public struct ExternalMeasurementLineV1: Codable, Sendable {

    /// Stable UUID for this measurement line record.
    public let id: String

    /// Optional label (e.g. "Flue → window").
    public let label: String?

    /// UUID of the object pin at the start of this line; nil when free-placed.
    public let startPinId: String?

    /// UUID of the object pin at the end of this line; nil when free-placed.
    public let endPinId: String?

    /// Engineer-entered distance in metres; nil when not yet measured.
    public let lengthM: Double?

    public init(
        id: String,
        label: String?,
        startPinId: String?,
        endPinId: String?,
        lengthM: Double? = nil
    ) {
        self.id = id
        self.label = label
        self.startPinId = startPinId
        self.endPinId = endPinId
        self.lengthM = lengthM
    }
}
