import Foundation
import CoreGraphics
import simd
import AtlasContracts

// MARK: - SpatialAlignmentEngine
//
// Converts an AtlasSpatialModelV1 into relative positions, screen projections,
// and structured alignment insights for display in the Alignment View.
//
// Design rules:
//   • All outputs carry a confidence level that mirrors the input anchor confidence.
//   • Inferred routes must NOT be presented as confirmed facts.
//   • No geometry is fabricated — if anchor positions are nil/missing the engine
//     returns nil rather than a best-guess.
//   • This engine is a pure-function module: no state, no side effects.

// MARK: - RelativePosition

/// The position of a spatial anchor relative to a user's current world position.
struct RelativePosition {

    /// Straight-line horizontal distance from the user to the anchor in metres.
    let distanceM: Double

    /// Bearing from the user to the anchor in degrees (0 = north / +z axis,
    /// clockwise positive when viewed from above).
    let bearingDeg: Double

    /// Signed vertical offset from the user to the anchor in metres.
    /// Positive = anchor is above the user; negative = anchor is below.
    let verticalOffsetM: Double

    /// Confidence inherited from the anchor's `worldPosition.confidence`.
    let confidence: AtlasWorldPositionV1.PositionConfidence
}

// MARK: - ScreenPosition

/// A 2-D projected position of a world-space point onto the view plane.
struct ScreenPosition {

    /// Normalised horizontal position (0 = left edge, 1 = right edge).
    let x: Double

    /// Normalised vertical position (0 = top edge, 1 = bottom edge).
    let y: Double

    /// `true` when the world point is in front of the camera (visible).
    let isVisible: Bool
}

// MARK: - AlignmentInsight

/// A human-readable spatial relationship insight derived from the spatial model.
///
/// Used to populate the Alignment View panel with structured, provenance-tagged
/// information about object positions and routing.
struct AlignmentInsight {

    /// Display label for the anchor (e.g. "Cylinder").
    let label: String

    /// Verbal relationship description (e.g. "above", "below", "same_level").
    let relation: String

    /// Vertical distance involved in the relationship, in metres.
    let verticalDistanceM: Double

    /// Horizontal distance or offset, in metres.
    let horizontalOffsetM: Double

    /// Confidence inherited from the source anchor.
    let confidence: AtlasWorldPositionV1.PositionConfidence

    /// Non-empty only for inferred items — explains the inference rationale.
    let inferenceReason: String?
}

// MARK: - ProjectionCameraPose

/// Minimal camera pose required for view-plane projection.
///
/// All values are in the same world-space coordinate system as
/// `AtlasWorldPositionV1` (metres, ARKit right-handed Y-up).
struct ProjectionCameraPose {

    /// Camera world-space position.
    let position: SIMD3<Double>

    /// Camera forward direction (normalised unit vector).
    let forward: SIMD3<Double>

    /// Camera up direction (normalised unit vector).
    let up: SIMD3<Double>

    /// Camera right direction (normalised unit vector).
    let right: SIMD3<Double>

    /// Horizontal field-of-view in radians.
    let fovHorizontalRad: Double

    /// Vertical field-of-view in radians.
    let fovVerticalRad: Double
}

// MARK: - SpatialAlignmentEngine

enum SpatialAlignmentEngine {

    // MARK: - Relative position

    /// Computes the position of `target` relative to `userPosition`.
    ///
    /// Returns `nil` if either position contains non-finite values.
    ///
    /// - Parameters:
    ///   - userPosition: The engineer's current world-space position.
    ///   - target: The anchor whose position is being queried.
    /// - Returns: A `RelativePosition` describing distance, bearing, and vertical offset,
    ///   or `nil` when the input values are not usable.
    static func getRelativePosition(
        userPosition: AtlasWorldPositionV1,
        target: AtlasAnchorV1
    ) -> RelativePosition? {
        let tp = target.worldPosition
        let dx = tp.x - userPosition.x
        let dz = tp.z - userPosition.z
        let dy = tp.y - userPosition.y

        guard dx.isFinite, dz.isFinite, dy.isFinite else { return nil }

        let horizontalDistance = (dx * dx + dz * dz).squareRoot()

        // Bearing: measured clockwise from +z axis (north) when viewed from above.
        // atan2(dx, dz) gives angle from +z axis, rotating towards +x.
        let bearingRad = atan2(dx, dz)
        let bearingDeg = bearingRad * (180.0 / Double.pi)
        let normalizedBearing = (bearingDeg + 360.0).truncatingRemainder(dividingBy: 360.0)

        return RelativePosition(
            distanceM: horizontalDistance,
            bearingDeg: normalizedBearing,
            verticalOffsetM: dy,
            confidence: tp.confidence
        )
    }

    // MARK: - View-plane projection

    /// Projects a world-space position onto the 2-D view plane described by `cameraPose`.
    ///
    /// Uses a standard perspective projection.  Returns `nil` when the point is behind
    /// the camera or the projection cannot be computed.
    ///
    /// - Parameters:
    ///   - cameraPose: Current camera position and orientation.
    ///   - worldPosition: The world-space point to project.
    /// - Returns: A `ScreenPosition` in normalised [0,1]×[0,1] coordinates, or `nil`
    ///   when the point is not in front of the camera.
    static func projectToViewPlane(
        cameraPose: ProjectionCameraPose,
        worldPosition: AtlasWorldPositionV1
    ) -> ScreenPosition? {
        let camPos  = cameraPose.position
        let forward = cameraPose.forward
        let right   = cameraPose.right
        let up      = cameraPose.up

        let worldVec = SIMD3<Double>(worldPosition.x, worldPosition.y, worldPosition.z)
        let toPoint = worldVec - camPos

        let depth = simd_dot(toPoint, forward)
        guard depth > 0 else { return nil }

        let rightProj = simd_dot(toPoint, right)
        let upProj    = simd_dot(toPoint, up)

        let halfFovH = cameraPose.fovHorizontalRad / 2.0
        let halfFovV = cameraPose.fovVerticalRad / 2.0

        let normalizedX = rightProj / (depth * tan(halfFovH))
        let normalizedY = upProj   / (depth * tan(halfFovV))

        // Convert from [-1,1] NDC to [0,1] screen space (y flipped: up = smaller y).
        let screenX = (normalizedX + 1.0) / 2.0
        let screenY = (1.0 - normalizedY) / 2.0

        let isVisible = screenX >= 0 && screenX <= 1 && screenY >= 0 && screenY <= 1

        return ScreenPosition(x: screenX, y: screenY, isVisible: isVisible)
    }

    // MARK: - Alignment insights

    /// Derives a list of `AlignmentInsight` records from the spatial model.
    ///
    /// Each insight describes a vertical relationship between two anchors, annotated
    /// with confidence and, for inferred data, a rationale string.
    ///
    /// - Parameter model: The spatial model to analyse.
    /// - Returns: An array of insights sorted by vertical distance (largest first).
    static func buildAlignmentInsights(model: AtlasSpatialModelV1) -> [AlignmentInsight] {
        let anchorMap = Dictionary(uniqueKeysWithValues: model.anchors.map { ($0.id, $0) })

        var insights: [AlignmentInsight] = []

        for relation in model.verticalRelations {
            guard
                let fromAnchor = anchorMap[relation.fromAnchorId],
                let toAnchor   = anchorMap[relation.toAnchorId]
            else { continue }

            let horizontalOffset = horizontalDistance(from: fromAnchor, to: toAnchor)

            // Take the lower of the two anchor confidences.
            let confidence = lowerConfidence(fromAnchor.worldPosition.confidence,
                                             toAnchor.worldPosition.confidence)

            insights.append(AlignmentInsight(
                label: toAnchor.label,
                relation: relation.relation.rawValue,
                verticalDistanceM: relation.verticalDistanceM,
                horizontalOffsetM: horizontalOffset,
                confidence: confidence,
                inferenceReason: confidence == .inferred ? "Derived from anchor positions" : nil
            ))
        }

        // Add route-based insights for inferred routes.
        for route in model.inferredRoutes {
            let lengthM = inferredRouteLength(route)
            insights.append(AlignmentInsight(
                label: "\(route.type.rawValue.capitalized) route",
                relation: "route",
                verticalDistanceM: 0,
                horizontalOffsetM: lengthM,
                confidence: .inferred,
                inferenceReason: route.reason
            ))
        }

        return insights.sorted { $0.verticalDistanceM > $1.verticalDistanceM }
    }

    // MARK: - Route length

    /// Computes the total path length of an inferred route in metres.
    ///
    /// - Parameter route: The inferred route whose path should be measured.
    /// - Returns: Sum of Euclidean distances between consecutive waypoints, in metres.
    static func inferredRouteLength(_ route: AtlasInferredRouteV1) -> Double {
        guard route.path.count >= 2 else { return 0 }
        var total = 0.0
        for i in 1..<route.path.count {
            let a = route.path[i - 1]
            let b = route.path[i]
            let dx = b.x - a.x
            let dy = b.y - a.y
            let dz = b.z - a.z
            total += (dx * dx + dy * dy + dz * dz).squareRoot()
        }
        return total
    }

    // MARK: - Vertical relation builder

    /// Derives `AtlasVerticalRelationV1` values for all anchor pairs in the model
    /// whose height difference exceeds `thresholdM`.
    ///
    /// This is a convenience factory for populating `spatialModel.verticalRelations`
    /// during the capture phase.
    ///
    /// - Parameters:
    ///   - anchors: The set of anchors to analyse.
    ///   - thresholdM: Minimum vertical distance (metres) to generate a relation.
    ///                 Pairs closer than this threshold are treated as `sameLevel`.
    /// - Returns: Array of derived vertical relations.
    static func buildVerticalRelations(
        for anchors: [AtlasAnchorV1],
        sameLevelThresholdM: Double = 0.1
    ) -> [AtlasVerticalRelationV1] {
        var relations: [AtlasVerticalRelationV1] = []
        for i in 0..<anchors.count {
            for j in (i + 1)..<anchors.count {
                let a = anchors[i]
                let b = anchors[j]
                let dy = b.worldPosition.y - a.worldPosition.y
                let absDy = abs(dy)
                let relation: AtlasVerticalRelationV1.VerticalRelation
                if absDy <= sameLevelThresholdM {
                    relation = .sameLevel
                } else if dy > 0 {
                    relation = .above
                } else {
                    relation = .below
                }
                relations.append(AtlasVerticalRelationV1(
                    fromAnchorId: a.id,
                    toAnchorId: b.id,
                    verticalDistanceM: absDy,
                    relation: relation
                ))
            }
        }
        return relations
    }

    // MARK: - Private helpers

    private static func horizontalDistance(from a: AtlasAnchorV1, to b: AtlasAnchorV1) -> Double {
        let dx = b.worldPosition.x - a.worldPosition.x
        let dz = b.worldPosition.z - a.worldPosition.z
        return (dx * dx + dz * dz).squareRoot()
    }

    private static func lowerConfidence(
        _ lhs: AtlasWorldPositionV1.PositionConfidence,
        _ rhs: AtlasWorldPositionV1.PositionConfidence
    ) -> AtlasWorldPositionV1.PositionConfidence {
        if lhs == .inferred || rhs == .inferred { return .inferred }
        return .confirmed
    }
}
