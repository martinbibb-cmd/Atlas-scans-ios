/// RoomCaptureV2 — Represents one room captured during the spatial walkthrough.
///
/// Each room has:
/// - A UUID (parent for all evidence in that space)
/// - An actual polygon (vertices, not a bounding box)
/// - Fabric classification per wall segment
/// - Pinned engineering objects
/// - A reference to the USDZ mesh asset for Van Mode review

import Foundation

// MARK: - Room capture

public struct RoomCaptureV2: Codable, Identifiable, Sendable {
    public let id: UUID          // == roomId used elsewhere
    public var displayName: String

    // ── Geometry ─────────────────────────────────────────────────────────────
    /// Ordered polygon vertices in the horizontal (X, Z) plane.
    /// Coordinate space: right-handed Y-up, metric metres.
    public var polygonVertices: [Vertex2D]

    /// Floor-level Y coordinate (metres above reference datum).
    public var floorLevelY: Double

    /// Ceiling height above floor (metres).
    public var ceilingHeightM: Double
    /// Raw ceiling-height sample from capture before normalization/QA handling.
    public var rawCapturedCeilingHeightM: Double?

    // ── Fabric ───────────────────────────────────────────────────────────────
    public var fabricCapture: FloorPlanFabricCaptureV1?

    // ── Pinned objects ───────────────────────────────────────────────────────
    public var pinnedObjects: [SpatialPinV1]

    // ── Van-mode asset ───────────────────────────────────────────────────────
    /// Relative path under `Documents/captures/{visitId}/` to the .usdz mesh.
    public var usdzAssetPath: String?

    // ── Timestamps ───────────────────────────────────────────────────────────
    public let capturedAt: Date

    public init(
        id: UUID = UUID(),
        displayName: String,
        polygonVertices: [Vertex2D] = [],
        floorLevelY: Double = 0.0,
        ceilingHeightM: Double = 2.4,
        rawCapturedCeilingHeightM: Double? = nil,
        capturedAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.polygonVertices = polygonVertices
        self.floorLevelY = floorLevelY
        self.ceilingHeightM = ceilingHeightM
        self.rawCapturedCeilingHeightM = rawCapturedCeilingHeightM
        self.fabricCapture = nil
        self.pinnedObjects = []
        self.usdzAssetPath = nil
        self.capturedAt = capturedAt
    }

    // MARK: Helpers

    /// Returns the area of the polygon using the shoelace formula (m²).
    public var floorAreaM2: Double {
        RoomPolygon(vertices: polygonVertices).area
    }

    /// True when the room has a valid closed floor outline polygon.
    public var hasClosedFloorPolygon: Bool {
        polygonVertices.count >= 3 && floorAreaM2 > 0.0001
    }

    /// Wall segments derived from the polygon vertices (for fabric tagging).
    public var wallSegments: [WallSegmentV1] {
        guard polygonVertices.count >= 2 else { return [] }
        return polygonVertices.indices.map { i in
            let next = (i + 1) % polygonVertices.count
            return WallSegmentV1(
                roomId: id,
                startVertex: polygonVertices[i],
                endVertex: polygonVertices[next],
                fabric: fabricCapture?.segments[safe: i]?.fabric ?? .externalWall
            )
        }
    }
}

// MARK: - Spatial pin (boiler, cylinder, flue terminal, etc.)

public struct SpatialPinV1: Codable, Identifiable, Sendable {
    public let id: UUID
    public let roomId: UUID

    /// 3-D world-space position (Y-up, metric metres).
    public let positionX: Double
    public let positionY: Double
    public let positionZ: Double

    /// Screen-space fallback position normalised to 0...1 when a stable
    /// world-space anchor is not yet available.
    public var screenPositionX: Double?
    public var screenPositionY: Double?

    public var objectType: PinnedObjectType
    public var label: String?

    /// Confidence of the underlying placement anchor.
    public var anchorConfidence: SpatialPinAnchorConfidence

    /// Hardware spec linked to this pin (e.g. the boiler model).
    public var hardwareSpecId: UUID?

    /// Optional durable appliance model key from `ApplianceDefinitionV1`.
    public var modelId: String?

    /// True when the world-space position is not at origin.
    public var hasNonZeroWorldPosition: Bool {
        abs(positionX) > 0.0001 || abs(positionY) > 0.0001 || abs(positionZ) > 0.0001
    }

    /// True when the pin has a usable world-space anchor.
    public var hasResolvedWorldAnchor: Bool {
        switch anchorConfidence {
        case .screenOnly:
            return false
        case .raycastEstimated, .high, .medium, .low, .estimated:
            return hasNonZeroWorldPosition
        }
    }

    public init(
        id: UUID = UUID(),
        roomId: UUID,
        positionX: Double,
        positionY: Double,
        positionZ: Double,
        screenPositionX: Double? = nil,
        screenPositionY: Double? = nil,
        objectType: PinnedObjectType,
        label: String? = nil,
        anchorConfidence: SpatialPinAnchorConfidence = .estimated,
        hardwareSpecId: UUID? = nil,
        modelId: String? = nil
    ) {
        self.id = id
        self.roomId = roomId
        self.positionX = positionX
        self.positionY = positionY
        self.positionZ = positionZ
        self.screenPositionX = screenPositionX
        self.screenPositionY = screenPositionY
        self.objectType = objectType
        self.label = label
        self.anchorConfidence = anchorConfidence
        self.hardwareSpecId = hardwareSpecId
        self.modelId = modelId
    }
}

public enum SpatialPinAnchorConfidence: String, Codable, CaseIterable, Sendable {
    case high
    case medium
    case low
    case estimated
    case raycastEstimated = "raycast_estimated"
    case screenOnly = "screen_only"
}

public enum PinnedObjectType: String, Codable, CaseIterable, Sendable {
    case boiler
    case heatPump
    case hotWaterCylinder
    case flueTerminal
    case nearbyOpening    // window / door near flue
    case electricalPanel
    case gasmeter
    case other
}

// MARK: - Safe subscript helper

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
