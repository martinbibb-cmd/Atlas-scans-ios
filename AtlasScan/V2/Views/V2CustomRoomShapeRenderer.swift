/// V2CustomRoomShapeRenderer — Renders a room's polygon outline as a SwiftUI shape.

import SwiftUI
import AtlasScanCore

struct V2CustomRoomShapeRenderer: Shape {
    var vertices: [Vertex2D]

    func path(in rect: CGRect) -> Path {
        guard vertices.count >= 2 else { return Path() }
        let xs = vertices.map(\.x)
        let zs = vertices.map(\.z)
        let minX = xs.min() ?? 0, maxX = xs.max() ?? 1
        let minZ = zs.min() ?? 0, maxZ = zs.max() ?? 1
        let rangeX = max(maxX - minX, 0.001)
        let rangeZ = max(maxZ - minZ, 0.001)
        func toPoint(_ v: Vertex2D) -> CGPoint {
            CGPoint(
                x: rect.minX + CGFloat((v.x - minX) / rangeX) * rect.width,
                y: rect.minY + CGFloat(1 - (v.z - minZ) / rangeZ) * rect.height
            )
        }
        var path = Path()
        path.move(to: toPoint(vertices[0]))
        for v in vertices.dropFirst() { path.addLine(to: toPoint(v)) }
        path.closeSubpath()
        return path
    }
}
