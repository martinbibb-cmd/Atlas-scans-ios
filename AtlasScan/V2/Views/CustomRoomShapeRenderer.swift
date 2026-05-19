/// V2CustomRoomShapeRenderer — Renders a room's polygon outline as a SwiftUI shape.

import SwiftUI
import AtlasScanCore

struct V2CustomRoomShapeRenderer: Shape {
    var vertices: [Vertex2D]

    func path(in rect: CGRect) -> Path {
        guard vertices.count >= 3 else { return Path() }
        guard RoomPolygon(vertices: vertices).area > 0.0001 else { return Path() }
        let xs = vertices.map(\.x)
        let zs = vertices.map(\.z)
        let minX = xs.min() ?? 0, maxX = xs.max() ?? 1
        let minZ = zs.min() ?? 0, maxZ = zs.max() ?? 1
        let rangeX = max(maxX - minX, 0.001)
        let rangeZ = max(maxZ - minZ, 0.001)
        let scale = min(rect.width / CGFloat(rangeX), rect.height / CGFloat(rangeZ))
        let contentWidth = CGFloat(rangeX) * scale
        let contentHeight = CGFloat(rangeZ) * scale
        let offsetX = rect.minX + (rect.width - contentWidth) / 2
        let offsetY = rect.minY + (rect.height - contentHeight) / 2
        func toPoint(_ v: Vertex2D) -> CGPoint {
            CGPoint(
                x: offsetX + CGFloat(v.x - minX) * scale,
                y: offsetY + contentHeight - CGFloat(v.z - minZ) * scale
            )
        }
        var path = Path()
        path.move(to: toPoint(vertices[0]))
        for v in vertices.dropFirst() { path.addLine(to: toPoint(v)) }
        path.closeSubpath()
        return path
    }
}

// MARK: - V2WallSegmentsShape

/// Renders individual wall segments as line strokes in the X/Z plane.
///
/// Used when `geometryConfidence == .wallSegmentsOnly` to draw the actual
/// captured wall lines without implying a filled room shape.
struct V2WallSegmentsShape: Shape {
    var segments: [RoomWallSegment2D]

    func path(in rect: CGRect) -> Path {
        guard !segments.isEmpty else { return Path() }

        // Compute bounding box across all endpoints.
        let allX = segments.flatMap { [$0.start.x, $0.end.x] }
        let allZ = segments.flatMap { [$0.start.z, $0.end.z] }
        let minX = allX.min() ?? 0, maxX = allX.max() ?? 1
        let minZ = allZ.min() ?? 0, maxZ = allZ.max() ?? 1
        let rangeX = max(maxX - minX, 0.001)
        let rangeZ = max(maxZ - minZ, 0.001)
        let scale = min(rect.width / CGFloat(rangeX), rect.height / CGFloat(rangeZ))
        let contentWidth  = CGFloat(rangeX) * scale
        let contentHeight = CGFloat(rangeZ) * scale
        let offsetX = rect.minX + (rect.width  - contentWidth)  / 2
        let offsetY = rect.minY + (rect.height - contentHeight) / 2

        func toPoint(_ v: Vertex2D) -> CGPoint {
            CGPoint(
                x: offsetX + CGFloat(v.x - minX) * scale,
                y: offsetY + contentHeight - CGFloat(v.z - minZ) * scale
            )
        }

        var path = Path()
        for seg in segments {
            path.move(to: toPoint(seg.start))
            path.addLine(to: toPoint(seg.end))
        }
        return path
    }
}

