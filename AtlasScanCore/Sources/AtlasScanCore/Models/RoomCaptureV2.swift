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
        capturedAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.polygonVertices = polygonVertices
        self.floorLevelY = floorLevelY
        self.ceilingHeightM = ceilingHeightM
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

    /// Wall segments derived from the polygon vertices (for fabric tagging).
    public var wallSegments: [WallSegmentV1] {
        guard polygonVertices.count >= 2 else { return [] }
        return polygonVertices.indices.map { i in
            let next = (i + 1) % polygonVertices.count
            return WallSegmentV1(
                roomId: id,
                startVertex: polygonVertices[i],
                endVertex: polygonVertices[next],
                fabric: fabricCapture?.segments[safe: i]?.fabric ?? .internalWall
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

    public var objectType: PinnedObjectType
    public var label: String?

    /// Hardware spec linked to this pin (e.g. the boiler model).
    public var hardwareSpecId: UUID?

    public init(
        id: UUID = UUID(),
        roomId: UUID,
        positionX: Double,
        positionY: Double,
        positionZ: Double,
        objectType: PinnedObjectType,
        label: String? = nil,
        hardwareSpecId: UUID? = nil
    ) {
        self.id = id
        self.roomId = roomId
        self.positionX = positionX
        self.positionY = positionY
        self.positionZ = positionZ
        self.objectType = objectType
        self.label = label
        self.hardwareSpecId = hardwareSpecId
    }
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
