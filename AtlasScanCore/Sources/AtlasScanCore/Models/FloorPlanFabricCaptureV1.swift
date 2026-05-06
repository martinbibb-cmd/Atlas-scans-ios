/// FloorPlanFabricCaptureV1 — Wall-segment fabric classification.
///
/// For each wall segment in the room polygon, the engineer classifies it as:
/// - `external_wall`  — outside-facing thermal envelope
/// - `internal_wall`  — separates two rooms within the same property
/// - `party_wall`     — separates this property from an adjoining property

import Foundation

// MARK: - Wall fabric enum

public enum WallFabric: String, Codable, CaseIterable, Sendable {
    case externalWall = "external_wall"
    case internalWall = "internal_wall"
    case partyWall    = "party_wall"

    /// Human-readable label for UI display.
    public var displayName: String {
        switch self {
        case .externalWall: return "External Wall"
        case .internalWall: return "Internal Wall"
        case .partyWall:    return "Party Wall"
        }
    }

    /// SF Symbol name for use in fabric-picker UI.
    public var symbolName: String {
        switch self {
        case .externalWall: return "house.fill"
        case .internalWall: return "rectangle.split.2x1"
        case .partyWall:    return "building.2.fill"
        }
    }
}

// MARK: - 2D vertex (X, Z horizontal plane — Y-up coordinate space)

/// A point in the horizontal (X, Z) plane.  Y is always the vertical axis.
public struct Vertex2D: Codable, Hashable, Sendable {
    public let x: Double
    public let z: Double

    public init(x: Double, z: Double) {
        self.x = x
        self.z = z
    }
}

// MARK: - Wall segment

public struct WallSegmentV1: Codable, Identifiable, Sendable {
    public let id: UUID
    public let roomId: UUID
    public let startVertex: Vertex2D
    public let endVertex: Vertex2D

    /// Engineer-assigned fabric classification.
    public var fabric: WallFabric

    /// Segment length in metres.
    public var lengthM: Double {
        let dx = endVertex.x - startVertex.x
        let dz = endVertex.z - startVertex.z
        return (dx * dx + dz * dz).squareRoot()
    }

    public init(
        id: UUID = UUID(),
        roomId: UUID,
        startVertex: Vertex2D,
        endVertex: Vertex2D,
        fabric: WallFabric = .internalWall
    ) {
        self.id = id
        self.roomId = roomId
        self.startVertex = startVertex
        self.endVertex = endVertex
        self.fabric = fabric
    }
}

// MARK: - Floor-plan fabric capture (full room)

public struct FloorPlanFabricCaptureV1: Codable, Identifiable, Sendable {
    public let id: UUID
    public let roomId: UUID

    /// Ordered wall segments forming the closed polygon.
    public var segments: [WallSegmentV1]

    public init(
        id: UUID = UUID(),
        roomId: UUID,
        segments: [WallSegmentV1] = []
    ) {
        self.id = id
        self.roomId = roomId
        self.segments = segments
    }

    /// Returns `true` when every segment has been assigned a fabric.
    public var isFullyClassified: Bool {
        !segments.isEmpty
    }

    /// Total perimeter length in metres.
    public var perimeterM: Double {
        segments.reduce(0) { $0 + $1.lengthM }
    }
}
