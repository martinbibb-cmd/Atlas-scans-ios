/// RoomGeometryBuilder — Builds an ordered floor-plan polygon from raw wall segments.
///
/// This is a **pure function** — no AR framework types, no `simd`, no iOS-only
/// dependencies.  It can be called from the app target during LiDAR capture and
/// tested on any platform (including the Linux CI runner).
///
/// Algorithm:
///  1. Accept `[RoomWallSegment2D]` extracted from `CapturedRoom.Surface.transform`.
///  2. Snap nearby endpoints within `snapToleranceM` and greedily chain segments.
///  3. Classify the result as `closedPolygon`, `wallSegmentsOnly`, `estimated`, or
///     `failed` — **never fabricate** a rectangle or triangle from bounding-box data.
///  4. Return ordered polygon vertices, the ordered segment list, confidence, and
///     human-readable warnings.

import Foundation

// MARK: - RoomGeometryBuilder

public enum RoomGeometryBuilder {

    // MARK: - Output

    public struct FloorPlanResult: Sendable {
        /// Ordered polygon vertices in the X/Z plane.
        ///
        /// For `.closedPolygon`: a closed, counter-clockwise wound loop.
        /// For `.wallSegmentsOnly`: an open polyline (not a closed polygon).
        /// For `.estimated` and `.failed`: empty.
        public let vertices: [Vertex2D]

        /// Wall segments in best-effort connection order.
        ///
        /// Non-empty for `.closedPolygon` and `.wallSegmentsOnly`.
        /// Empty for `.estimated` and `.failed`.
        public let orderedSegments: [RoomWallSegment2D]

        /// How trustworthy the resulting polygon is.
        public let confidence: GeometryConfidence

        /// Human-readable warnings the engineer should review.
        public let warnings: [String]

        public init(
            vertices: [Vertex2D],
            orderedSegments: [RoomWallSegment2D],
            confidence: GeometryConfidence,
            warnings: [String]
        ) {
            self.vertices = vertices
            self.orderedSegments = orderedSegments
            self.confidence = confidence
            self.warnings = warnings
        }
    }

    // MARK: - Main entry point

    /// Builds a floor-plan polygon from raw wall segments.
    ///
    /// - Parameters:
    ///   - segments: Wall segments extracted from RoomPlan surface transforms.
    ///   - snapToleranceM: Maximum gap (metres) between endpoints to consider
    ///     them connected.  Defaults to 0.15 m; auto-scales to 10% of the
    ///     room bounding box up to a cap of 0.30 m.
    /// - Returns: A `FloorPlanResult` with vertices, ordered segments,
    ///   confidence classification, and engineering warnings.
    public static func buildFloorPlan(
        from segments: [RoomWallSegment2D],
        snapToleranceM: Double = 0.15
    ) -> FloorPlanResult {
        guard !segments.isEmpty else {
            return FloorPlanResult(
                vertices: [],
                orderedSegments: [],
                confidence: .failed,
                warnings: ["No wall segments were captured."]
            )
        }

        // ── Compute bounding box and auto-scale tolerance ──────────────────────
        let allX = segments.flatMap { [$0.start.x, $0.end.x] }
        let allZ = segments.flatMap { [$0.start.z, $0.end.z] }
        let rangeX = (allX.max() ?? 0) - (allX.min() ?? 0)
        let rangeZ = (allZ.max() ?? 0) - (allZ.min() ?? 0)
        let autoScaled = min(min(rangeX, rangeZ) * 0.10, 0.30)
        let tolerance = max(snapToleranceM, autoScaled)

        // ── Greedy chain ───────────────────────────────────────────────────────
        // Start with the first segment's two endpoints and try to attach
        // remaining segments by their nearest endpoint.
        var orderedPts: [Vertex2D] = [segments[0].start, segments[0].end]
        var orderedSegs: [RoomWallSegment2D] = [segments[0]]
        var remaining = Array(segments.dropFirst())

        while !remaining.isEmpty {
            let last = orderedPts[orderedPts.count - 1]
            var bestIdx = -1
            var bestDist = Double.greatestFiniteMagnitude
            var useStart = true

            for (i, seg) in remaining.enumerated() {
                let dStart = distance(last, seg.start)
                let dEnd   = distance(last, seg.end)
                if dStart < bestDist { bestDist = dStart; bestIdx = i; useStart = true }
                if dEnd   < bestDist { bestDist = dEnd;   bestIdx = i; useStart = false }
            }

            guard bestIdx >= 0, bestDist < tolerance else { break }
            let seg = remaining.remove(at: bestIdx)
            orderedSegs.append(seg)
            orderedPts.append(useStart ? seg.end : seg.start)
        }

        // ── Build warnings ────────────────────────────────────────────────────
        var warnings: [String] = []
        if !remaining.isEmpty {
            warnings.append(
                "\(remaining.count) wall segment(s) could not be connected to the main chain — scan may be incomplete."
            )
        }

        // ── Guard: need at least 2 connected segments to be meaningful ────────
        guard orderedSegs.count >= 2 else {
            warnings.append("Only one wall segment was placed — cannot form a room outline.")
            return FloorPlanResult(
                vertices: [],
                orderedSegments: orderedSegs,
                confidence: .estimated,
                warnings: warnings
            )
        }

        // ── Check whether the chain closes ────────────────────────────────────
        let firstPt = orderedPts[0]
        let lastPt  = orderedPts[orderedPts.count - 1]
        let closingGap = distance(firstPt, lastPt)

        if closingGap < tolerance {
            // Loop closes: drop the duplicate last point.
            var vertices = Array(orderedPts.dropLast())
            guard vertices.count >= 3 else {
                warnings.append("Polygon degenerated to fewer than 3 vertices after closing — treating as wall segments only.")
                return FloorPlanResult(
                    vertices: orderedPts,
                    orderedSegments: orderedSegs,
                    confidence: .wallSegmentsOnly,
                    warnings: warnings
                )
            }
            // Enforce counter-clockwise winding so filled rendering is correct.
            let polygon = RoomPolygon(vertices: vertices)
            vertices = polygon.normalised.vertices
            return FloorPlanResult(
                vertices: vertices,
                orderedSegments: orderedSegs,
                confidence: .closedPolygon,
                warnings: warnings
            )
        } else {
            // Loop does not close — return the open polyline for wall-line drawing.
            warnings.append(
                String(
                    format: "Room outline gap: %.2f m between first and last wall endpoint — scan may be incomplete.",
                    closingGap
                )
            )
            return FloorPlanResult(
                vertices: orderedPts,
                orderedSegments: orderedSegs,
                confidence: .wallSegmentsOnly,
                warnings: warnings
            )
        }
    }

    // MARK: - Private helpers

    private static func distance(_ a: Vertex2D, _ b: Vertex2D) -> Double {
        let dx = a.x - b.x
        let dz = a.z - b.z
        return (dx * dx + dz * dz).squareRoot()
    }
}
