import Foundation

// MARK: - FloorPlanFabricCaptureV1
//
// Fabric capture contract — carries engineer-recorded boundary and opening
// evidence per room.  Produced by Atlas Scan and consumed by Atlas Mind.
//
// Design:
//   • One FloorPlanFabricCaptureV1 = all fabric evidence for one session.
//   • Each RoomFabricCaptureV1 record corresponds to one captured room.
//   • Boundaries and openings are raw observations only — no U-values,
//     no heat-loss calculation, no derived outputs.
//   • Atlas Mind owns all thermal / fabric interpretation downstream.

// MARK: - Top-level envelope

/// All floor-plan fabric evidence captured during a single visit session.
///
/// Carried as an optional field in ``SessionCaptureV2`` so that existing
/// sessions without fabric data remain valid.
public struct FloorPlanFabricCaptureV1: Codable, Sendable {

    /// Schema version for this block.
    public let schemaVersion: String

    /// Per-room fabric records captured during the visit.
    public let rooms: [RoomFabricCaptureV1]

    public init(
        schemaVersion: String = "1.0",
        rooms: [RoomFabricCaptureV1]
    ) {
        self.schemaVersion = schemaVersion
        self.rooms = rooms
    }
}

// MARK: - RoomFabricCaptureV1

/// Fabric evidence for a single captured room.
public struct RoomFabricCaptureV1: Codable, Sendable {

    /// Stable UUID matching the corresponding ``CapturedRoomScanV2/id``.
    /// Nil when fabric data was recorded without a linked room scan.
    public let roomId: String?

    /// Optional room label (carried through for display purposes).
    public let roomLabel: String?

    /// Measured or known perimeter in metres; nil if not recorded.
    public let perimeterM: Double?

    /// Measured or known floor area in m²; nil if not recorded.
    public let areaM2: Double?

    /// Measured or known ceiling height in metres; nil if not recorded.
    public let heightM: Double?

    /// Boundary observations (walls, party walls, etc.) recorded for this room.
    public let boundaries: [BoundaryCaptureV1]

    /// Opening observations (doors, windows, etc.) recorded for this room.
    public let openings: [OpeningCaptureV1]

    public init(
        roomId: String?,
        roomLabel: String?,
        perimeterM: Double?,
        areaM2: Double?,
        heightM: Double?,
        boundaries: [BoundaryCaptureV1],
        openings: [OpeningCaptureV1]
    ) {
        self.roomId = roomId
        self.roomLabel = roomLabel
        self.perimeterM = perimeterM
        self.areaM2 = areaM2
        self.heightM = heightM
        self.boundaries = boundaries
        self.openings = openings
    }
}

// MARK: - BoundaryCaptureV1

/// A single boundary (wall segment) observed by the engineer.
///
/// Raw observation only — no U-value, no thermal resistance,
/// no heat-loss contribution.  Atlas Mind derives those downstream.
public struct BoundaryCaptureV1: Codable, Sendable {

    /// Stable UUID for this boundary record.
    public let id: String

    /// Boundary classification raw value.
    ///
    /// Valid values: "external" | "internal" | "party" | "unknown"
    public let boundaryType: String

    /// Measured length of this boundary in metres; nil if not recorded.
    public let lengthM: Double?

    /// Measured height of this boundary in metres; nil if not recorded.
    public let heightM: Double?

    /// Free-text material description (e.g. "solid brick", "cavity wall",
    /// "timber frame").  Nil when unknown.
    public let material: String?

    /// Engineer review status raw value: "confirmed" | "pending" | "rejected".
    public let reviewStatus: String

    public init(
        id: String,
        boundaryType: String,
        lengthM: Double?,
        heightM: Double?,
        material: String?,
        reviewStatus: String
    ) {
        self.id = id
        self.boundaryType = boundaryType
        self.lengthM = lengthM
        self.heightM = heightM
        self.material = material
        self.reviewStatus = reviewStatus
    }
}

// MARK: - OpeningCaptureV1

/// A single opening (door, window, etc.) observed by the engineer.
///
/// Raw observation only — no U-value, no infiltration estimate.
public struct OpeningCaptureV1: Codable, Sendable {

    /// Stable UUID for this opening record.
    public let id: String

    /// Opening classification raw value.
    ///
    /// Valid values: "door" | "window" | "patio" | "rooflight" | "open_arch"
    public let openingType: String

    /// Measured or estimated width in metres; nil if not recorded.
    public let widthM: Double?

    /// Measured or estimated height in metres; nil if not recorded.
    public let heightM: Double?

    /// Free-text material / glazing description (e.g. "double glazed uPVC").
    /// Nil when unknown.
    public let material: String?

    /// UUID of the boundary this opening is located in; nil when not linked.
    public let linkedBoundaryId: String?

    /// Engineer review status raw value: "confirmed" | "pending" | "rejected".
    public let reviewStatus: String

    public init(
        id: String,
        openingType: String,
        widthM: Double?,
        heightM: Double?,
        material: String?,
        linkedBoundaryId: String?,
        reviewStatus: String
    ) {
        self.id = id
        self.openingType = openingType
        self.widthM = widthM
        self.heightM = heightM
        self.material = material
        self.linkedBoundaryId = linkedBoundaryId
        self.reviewStatus = reviewStatus
    }
}
