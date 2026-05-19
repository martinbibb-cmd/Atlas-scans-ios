/// RoomGeometryTypes — Rich wall-segment and floor-plan geometry types.
///
/// These types represent the full coordinate-system model for a captured room:
///   - `RoomPlanPoint2D` is a point in the horizontal X/Z plane (aliased to Vertex2D)
///   - `RoomWallSegment2D` stores each wall's physical position derived from
///     `CapturedRoom.Surface.transform` — not guessed wall lengths
///   - `GeometryConfidence` classifies how trustworthy the floor-plan polygon is
///   - `WallSegmentConfidence` classifies individual wall quality

import Foundation

// MARK: - RoomPlanPoint2D

/// A point in the horizontal (X, Z) plane — alias for Vertex2D.
public typealias RoomPlanPoint2D = Vertex2D

// MARK: - WallSegmentConfidence

/// Quality rating for an individual wall segment.
public enum WallSegmentConfidence: String, Codable, CaseIterable, Sendable {
    /// Wall was captured with high-quality plane data.
    case high
    /// Wall was captured but with limited plane extent or tracking noise.
    case medium
    /// Wall was inferred from sparse data and may be imprecise.
    case low
}

// MARK: - RoomWallSegment2D

/// A single wall captured by RoomPlan, projected into the horizontal (X, Z) plane.
///
/// Derived from `CapturedRoom.Surface.transform` and `.dimensions`:
/// - `start` and `end` are the wall's two endpoint corners in room-local metres
/// - `lengthM` is the physical wall length from `dimensions.x / 2 * 2`
/// - `bearingDeg` is the wall direction angle from +X axis, degrees (−180…180)
/// - `confidence` reflects the quality of the underlying RoomPlan surface data
public struct RoomWallSegment2D: Codable, Identifiable, Sendable {
    public let id: UUID

    /// Zero-based index matching `CapturedRoom.walls[wallIndex]`.
    public let wallIndex: Int

    /// Wall start endpoint in room-local X/Z metres.
    public let start: Vertex2D

    /// Wall end endpoint in room-local X/Z metres.
    public let end: Vertex2D

    /// Physical wall length in metres (‖end − start‖).
    public let lengthM: Double

    /// Bearing: angle of the wall direction vector from +X axis, degrees (−180…180).
    public let bearingDeg: Double

    /// Quality of the underlying RoomPlan plane data.
    public let confidence: WallSegmentConfidence

    public init(
        id: UUID = UUID(),
        wallIndex: Int,
        start: Vertex2D,
        end: Vertex2D,
        confidence: WallSegmentConfidence = .medium
    ) {
        self.id = id
        self.wallIndex = wallIndex
        self.start = start
        self.end = end
        let dx = end.x - start.x
        let dz = end.z - start.z
        self.lengthM = (dx * dx + dz * dz).squareRoot()
        self.bearingDeg = atan2(dz, dx) * 180 / .pi
        self.confidence = confidence
    }
}

// MARK: - GeometryConfidence

/// Classifies how trustworthy the floor-plan polygon stored in `RoomCaptureV2` is.
///
/// The review screen and any downstream handoff MUST check this value before
/// treating the polygon as confirmed room evidence.  Never treat `.estimated`
/// or `.failed` geometry as confirmed room shape.
public enum GeometryConfidence: String, Codable, CaseIterable, Sendable {

    /// All wall segments form a connected loop that closes within snap tolerance.
    /// The polygon is trustworthy for display, area measurement, and export.
    case closedPolygon = "closed_polygon"

    /// Wall segments exist and are partially connected, but the loop does not
    /// close.  Draw wall lines only — do not fill or export the polygon as a
    /// confirmed room outline.
    case wallSegmentsOnly = "wall_segments_only"

    /// Geometry was derived from limited data (e.g. very few connected segments).
    /// Show a "needs review" state; do not treat the outline as confirmed.
    case estimated = "estimated"

    /// No usable geometry could be derived from the capture.
    case failed = "failed"

    /// True when the geometry is not fully reliable and must be shown in a
    /// review state before being used for engineering decisions.
    public var requiresReview: Bool {
        switch self {
        case .closedPolygon:    return false
        case .wallSegmentsOnly, .estimated, .failed: return true
        }
    }

    /// Human-readable label for the review UI.
    public var displayLabel: String {
        switch self {
        case .closedPolygon:    return "Closed polygon"
        case .wallSegmentsOnly: return "Wall segments only"
        case .estimated:        return "Estimated — needs review"
        case .failed:           return "Failed — no geometry"
        }
    }
}
