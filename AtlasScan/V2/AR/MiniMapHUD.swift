/// MiniMapHUD — Overhead 2-D floor-plan overlay shown during live scanning.

import SwiftUI
import AtlasScanCore

struct MiniMapHUD: View {
    var rooms: [RoomCaptureV2]
    var activeRoomId: UUID?

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            Canvas { context, _ in
                for room in rooms {
                    let path = polygonPath(for: room.polygonVertices, in: size)
                    let isActive = room.id == activeRoomId
                    context.fill(path, with: .color(isActive ? .cyan.opacity(0.3) : .white.opacity(0.15)))
                    context.stroke(path, with: .color(isActive ? .cyan : .white), lineWidth: isActive ? 2 : 1)
                }
            }
            .frame(width: size, height: size)
        }
        .frame(width: 140, height: 140)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
        )
    }

    private func polygonPath(for vertices: [Vertex2D], in size: Double) -> Path {
        guard vertices.count >= 2 else { return Path() }
        let allX = vertices.map(\.x)
        let allZ = vertices.map(\.z)
        let minX = allX.min() ?? 0, maxX = allX.max() ?? 1
        let minZ = allZ.min() ?? 0, maxZ = allZ.max() ?? 1
        let rangeX = max(maxX - minX, 0.001)
        let rangeZ = max(maxZ - minZ, 0.001)
        let padding = size * 0.1
        let drawSize = size - padding * 2
        func toCanvas(_ v: Vertex2D) -> CGPoint {
            CGPoint(
                x: padding + (v.x - minX) / rangeX * drawSize,
                y: padding + (1 - (v.z - minZ) / rangeZ) * drawSize
            )
        }
        var path = Path()
        path.move(to: toCanvas(vertices[0]))
        for v in vertices.dropFirst() { path.addLine(to: toCanvas(v)) }
        path.closeSubpath()
        return path
    }
}
