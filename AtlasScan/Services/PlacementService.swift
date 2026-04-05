import Foundation
import CoreGraphics

// MARK: - PlacementService
//
// Geometry helpers for room-layout-aware service object placement.
// All geometry is computed in 2-D normalized room coordinates (0…1 × 0…1).
// No RoomPlan or UIKit types are used here — testable on any platform.

enum PlacementService {

    // MARK: - Layout polygon

    /// Returns a normalized (0…1) 2-D polygon tracing the room perimeter,
    /// computed from wall bearing and length data.
    ///
    /// If fewer than 3 walls are present or none have bearing data, a unit
    /// square is returned as a sensible fallback.
    ///
    /// Coordinate convention: x = 0 is left, x = 1 is right,
    /// y = 0 is top (north), y = 1 is bottom (south) — screen-space Y.
    static func layoutPolygon(for room: ScannedRoom) -> [CGPoint] {
        let hasGeometry = room.walls.count >= 3
            && room.walls.contains { $0.bearingDegrees != nil }
        if hasGeometry {
            return normalizedWallPolygon(from: room.walls)
        }
        return unitSquare
    }

    // MARK: - Wall selection

    /// Returns the index of the wall whose edge is closest to the given
    /// normalized point, using the provided polygon.
    ///
    /// Falls back to 0 when the polygon is empty.
    static func nearestWallIndex(to point: CGPoint, in polygon: [CGPoint]) -> Int {
        guard polygon.count >= 2 else { return 0 }
        var nearest = 0
        var minDist = Double.infinity
        for i in 0..<polygon.count {
            let a = polygon[i]
            let b = polygon[(i + 1) % polygon.count]
            let dist = distanceFromPoint(point, toSegment: a, end: b)
            if dist < minDist {
                minDist = dist
                nearest = i
            }
        }
        return nearest
    }

    /// Convenience overload that builds the polygon from room walls.
    /// Returns `nil` when the room has no walls.
    static func nearestWall(to point: NormalizedPoint2D, in room: ScannedRoom) -> (wall: ScannedWall, index: Int)? {
        guard !room.walls.isEmpty else { return nil }
        let polygon = layoutPolygon(for: room)
        let cgPoint = CGPoint(x: point.x, y: point.y)
        let idx = nearestWallIndex(to: cgPoint, in: polygon)
        guard idx < room.walls.count else { return nil }
        return (room.walls[idx], idx)
    }

    // MARK: - Snap to wall

    /// Projects `point` onto wall segment `wallIndex` in the polygon and returns
    /// a `NormalizedPoint2D` slightly offset inward from the wall surface.
    ///
    /// The inward offset (default 3 % of room) prevents the icon from sitting
    /// exactly on the perimeter and makes wall-mounted objects visually legible.
    static func snapToWall(
        point: CGPoint,
        wallIndex: Int,
        in polygon: [CGPoint],
        inwardOffset: Double = 0.03
    ) -> NormalizedPoint2D {
        guard polygon.count >= 2 else {
            return NormalizedPoint2D(x: point.x, y: point.y)
        }
        let i = wallIndex % polygon.count
        let a = polygon[i]
        let b = polygon[(i + 1) % polygon.count]
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSq = dx * dx + dy * dy
        guard lengthSq > 1e-9 else {
            return NormalizedPoint2D(x: a.x, y: a.y)
        }

        // Project along segment, keeping 5 % margins from corners
        let t = max(0.05, min(0.95,
            ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSq))
        let wallPt = CGPoint(x: a.x + t * dx, y: a.y + t * dy)

        // Perpendicular (unit normal, one of the two orientations)
        let wallLen = lengthSq.squareRoot()
        let nx = -dy / wallLen
        let ny =  dx / wallLen

        // Pick the inward-facing normal by checking which side the centroid is on
        let centroid = polygonCentroid(polygon)
        let toCentX = centroid.x - wallPt.x
        let toCentY = centroid.y - wallPt.y
        let dot = toCentX * nx + toCentY * ny
        let inX = dot >= 0 ? nx : -nx
        let inY = dot >= 0 ? ny : -ny

        return NormalizedPoint2D(
            x: wallPt.x + inX * inwardOffset,
            y: wallPt.y + inY * inwardOffset
        )
    }

    // MARK: - Apply placement to a TaggedObject

    /// Mutates `object` to record a tap at `normalizedPoint` within `room`.
    ///
    /// For wall-mounted categories the position is snapped to the nearest wall
    /// and `wallIndex` / `attachedWallID` are set.
    /// For floor-placed categories the position is used directly.
    static func place(
        object: inout TaggedObject,
        at normalizedPoint: NormalizedPoint2D,
        in room: ScannedRoom
    ) {
        let polygon = layoutPolygon(for: room)
        let cgPoint = CGPoint(x: normalizedPoint.x, y: normalizedPoint.y)

        switch object.placementMode {
        case .wallMounted:
            let wallIdx = nearestWallIndex(to: cgPoint, in: polygon)
            let snapped = snapToWall(point: cgPoint, wallIndex: wallIdx, in: polygon)
            object.normalizedPosition = snapped
            object.wallIndex = wallIdx < room.walls.count ? room.walls[wallIdx].index : wallIdx
            object.attachedWallID = wallIdx < room.walls.count ? room.walls[wallIdx].id : nil

        case .floorPlaced, .unplaced:
            object.normalizedPosition = normalizedPoint
            object.wallIndex = nil
            object.attachedWallID = nil
        }

        object.touch()
    }

    // MARK: - Private geometry helpers

    private static var unitSquare: [CGPoint] {
        [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 1, y: 0),
            CGPoint(x: 1, y: 1),
            CGPoint(x: 0, y: 1),
        ]
    }

    /// Builds a normalized polygon from wall bearing + length data.
    /// Uses screen-space Y convention (y increases downward).
    static func normalizedWallPolygon(from walls: [ScannedWall]) -> [CGPoint] {
        var rawPoints: [CGPoint] = []
        var x = 0.0, y = 0.0
        let defaultLen = 3.0

        for wall in walls {
            rawPoints.append(CGPoint(x: x, y: y))
            let length = wall.lengthMetres ?? defaultLen
            let bearing = (wall.bearingDegrees ?? 0.0) * .pi / 180.0
            x += length * sin(bearing)
            y -= length * cos(bearing)    // flip Z→Y for screen space
        }

        return normalizePoints(rawPoints)
    }

    /// Normalizes a list of CGPoints so that x and y each span 0…1.
    static func normalizePoints(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count >= 2 else { return unitSquare }
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? 1
        let minY = ys.min() ?? 0
        let maxY = ys.max() ?? 1
        let rangeX = max(maxX - minX, 1e-3)
        let rangeY = max(maxY - minY, 1e-3)
        return points.map {
            CGPoint(x: ($0.x - minX) / rangeX, y: ($0.y - minY) / rangeY)
        }
    }

    /// Minimum perpendicular distance from `p` to the line segment [a, b].
    static func distanceFromPoint(_ p: CGPoint, toSegment a: CGPoint, end b: CGPoint) -> Double {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSq = dx * dx + dy * dy
        if lengthSq < 1e-9 {
            return hypot(p.x - a.x, p.y - a.y)
        }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSq))
        let nearest = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
        return hypot(p.x - nearest.x, p.y - nearest.y)
    }

    /// Centroid (mean of vertices) of a polygon.
    static func polygonCentroid(_ polygon: [CGPoint]) -> CGPoint {
        guard !polygon.isEmpty else { return CGPoint(x: 0.5, y: 0.5) }
        let sumX = polygon.reduce(0.0) { $0 + $1.x }
        let sumY = polygon.reduce(0.0) { $0 + $1.y }
        return CGPoint(x: sumX / Double(polygon.count), y: sumY / Double(polygon.count))
    }
}
