import Foundation
import AtlasContracts

// MARK: - SpatialAlignmentSelectors
//
// Pure query helpers for AtlasSpatialModelV1.
//
// Design rules:
//   • All selectors are read-only — they never mutate the model.
//   • Selectors that return inferred data must be clearly named and documented.
//   • No geometry is fabricated; missing data returns nil or empty results.

enum SpatialAlignmentSelectors {

    // MARK: - Anchor queries

    /// Returns the anchor with the given `id`, or `nil` when not found.
    static func anchor(id: String, in model: AtlasSpatialModelV1) -> AtlasAnchorV1? {
        model.anchors.first { $0.id == id }
    }

    /// Returns all anchors assigned to `roomId`.
    static func anchors(inRoom roomId: String, model: AtlasSpatialModelV1) -> [AtlasAnchorV1] {
        model.anchors.filter { $0.roomId == roomId }
    }

    /// Returns all anchors whose `label` matches `label` (case-insensitive).
    static func anchors(
        labelledAs label: String,
        in model: AtlasSpatialModelV1
    ) -> [AtlasAnchorV1] {
        let target = label.lowercased()
        return model.anchors.filter { $0.label.lowercased() == target }
    }

    /// Returns all confirmed anchors (position confidence = `.confirmed`).
    static func confirmedAnchors(in model: AtlasSpatialModelV1) -> [AtlasAnchorV1] {
        model.anchors.filter { $0.worldPosition.confidence == .confirmed }
    }

    /// Returns all inferred anchors (position confidence = `.inferred`).
    static func inferredAnchors(in model: AtlasSpatialModelV1) -> [AtlasAnchorV1] {
        model.anchors.filter { $0.worldPosition.confidence == .inferred }
    }

    // MARK: - Vertical relation queries

    /// Returns all vertical relations that involve `anchorId` as either endpoint.
    static func verticalRelations(
        involving anchorId: String,
        in model: AtlasSpatialModelV1
    ) -> [AtlasVerticalRelationV1] {
        model.verticalRelations.filter {
            $0.fromAnchorId == anchorId || $0.toAnchorId == anchorId
        }
    }

    /// Returns the vertical relation between `anchorId` and `otherAnchorId`,
    /// or `nil` when no such relation exists.
    static func verticalRelation(
        between anchorId: String,
        and otherAnchorId: String,
        in model: AtlasSpatialModelV1
    ) -> AtlasVerticalRelationV1? {
        model.verticalRelations.first {
            ($0.fromAnchorId == anchorId && $0.toAnchorId == otherAnchorId)
            || ($0.fromAnchorId == otherAnchorId && $0.toAnchorId == anchorId)
        }
    }

    /// Returns all anchors that are above `anchorId` according to the
    /// stored vertical relations.
    static func anchorsAbove(
        anchorId: String,
        in model: AtlasSpatialModelV1
    ) -> [AtlasAnchorV1] {
        let anchorMap = Dictionary(uniqueKeysWithValues: model.anchors.map { ($0.id, $0) })
        return model.verticalRelations
            .filter { rel in
                (rel.fromAnchorId == anchorId && rel.relation == .above)
                || (rel.toAnchorId == anchorId && rel.relation == .below)
            }
            .compactMap { rel -> AtlasAnchorV1? in
                let otherId = rel.fromAnchorId == anchorId ? rel.toAnchorId : rel.fromAnchorId
                return anchorMap[otherId]
            }
    }

    /// Returns all anchors that are below `anchorId` according to the
    /// stored vertical relations.
    static func anchorsBelow(
        anchorId: String,
        in model: AtlasSpatialModelV1
    ) -> [AtlasAnchorV1] {
        let anchorMap = Dictionary(uniqueKeysWithValues: model.anchors.map { ($0.id, $0) })
        return model.verticalRelations
            .filter { rel in
                (rel.fromAnchorId == anchorId && rel.relation == .below)
                || (rel.toAnchorId == anchorId && rel.relation == .above)
            }
            .compactMap { rel -> AtlasAnchorV1? in
                let otherId = rel.fromAnchorId == anchorId ? rel.toAnchorId : rel.fromAnchorId
                return anchorMap[otherId]
            }
    }

    // MARK: - Inferred route queries

    /// Returns all inferred routes whose `type` matches `routeType`.
    static func inferredRoutes(
        ofType routeType: AtlasInferredRouteV1.RouteType,
        in model: AtlasSpatialModelV1
    ) -> [AtlasInferredRouteV1] {
        model.inferredRoutes.filter { $0.type == routeType }
    }

    /// Returns the total inferred pipe length across all pipe routes in the model,
    /// in metres.  Returns 0 when no pipe routes are present.
    static func totalInferredPipeLengthM(in model: AtlasSpatialModelV1) -> Double {
        inferredRoutes(ofType: .pipe, in: model)
            .map { SpatialAlignmentEngine.inferredRouteLength($0) }
            .reduce(0, +)
    }

    // MARK: - Model summary

    /// Returns a brief human-readable summary of the spatial model's contents.
    ///
    /// Example: "3 anchors (2 confirmed, 1 inferred), 1 vertical relation, 2 routes"
    static func modelSummary(_ model: AtlasSpatialModelV1) -> String {
        let total     = model.anchors.count
        let confirmed = confirmedAnchors(in: model).count
        let inferred  = inferredAnchors(in: model).count
        let relations = model.verticalRelations.count
        let routes    = model.inferredRoutes.count

        var parts: [String] = []
        parts.append("\(total) anchor\(total == 1 ? "" : "s") (\(confirmed) confirmed, \(inferred) inferred)")
        if relations > 0 {
            parts.append("\(relations) vertical relation\(relations == 1 ? "" : "s")")
        }
        if routes > 0 {
            parts.append("\(routes) inferred route\(routes == 1 ? "" : "s")")
        }
        return parts.joined(separator: ", ")
    }
}
