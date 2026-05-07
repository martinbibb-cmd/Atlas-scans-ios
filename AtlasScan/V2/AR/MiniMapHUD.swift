/// MiniMapHUD — Overhead 2-D floor-plan overlay shown during live scanning.

import SwiftUI
import AtlasScanCore

struct MiniMapHUD: View {
    var rooms: [RoomCaptureV2]
    var livePolygonVertices: [Vertex2D] = []
    var activeRoomId: UUID?
    var pins: [SpatialPinV1] = []

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let projection = MiniMapProjection(rooms: rooms, liveVertices: livePolygonVertices, pins: minimapPins, size: size)

            ZStack {
                Canvas { context, _ in
                    for room in rooms {
                        let path = projection.path(for: room.polygonVertices)
                        let isActive = room.id == activeRoomId
                        context.fill(path, with: .color(isActive ? .cyan.opacity(0.22) : .white.opacity(0.08)))
                        context.stroke(path, with: .color(isActive ? .cyan : .white.opacity(0.45)), lineWidth: isActive ? 2.2 : 1.1)
                    }

                    if !livePolygonVertices.isEmpty {
                        let livePath = projection.path(for: livePolygonVertices)
                        context.fill(livePath, with: .color(.cyan.opacity(0.16)))
                        context.stroke(livePath, with: .color(.cyan), lineWidth: 2.4)
                    }
                }

                ForEach(minimapPins) { pin in
                    let point = projection.point(for: pin)
                    Circle()
                        .fill(color(for: pin.objectType))
                        .frame(width: 8, height: 8)
                        .overlay {
                            Circle().stroke(.black.opacity(0.35), lineWidth: 1)
                        }
                        .position(point)
                }
            }
            .frame(width: size, height: size)
        }
        .frame(width: 140, height: 140)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.white.opacity(0.14), lineWidth: 0.8)
        )
        .allowsHitTesting(false)
    }

    private var minimapPins: [SpatialPinV1] {
        pins.filter {
            switch $0.objectType {
            case .boiler, .heatPump, .hotWaterCylinder, .flueTerminal, .gasmeter:
                return true
            default:
                return false
            }
        }
    }

    private func color(for type: PinnedObjectType) -> Color {
        switch type {
        case .boiler, .heatPump: return .orange
        case .hotWaterCylinder: return .blue
        case .flueTerminal: return .red
        case .gasmeter: return .purple
        case .electricalPanel: return .yellow
        case .nearbyOpening: return .green
        case .other: return .white
        }
    }
}

private struct MiniMapProjection {
    let minX: Double
    let maxX: Double
    let minZ: Double
    let maxZ: Double
    let size: Double
    let padding: Double

    init(rooms: [RoomCaptureV2], liveVertices: [Vertex2D], pins: [SpatialPinV1], size: Double) {
        let allVertices = rooms.flatMap(\.polygonVertices) + liveVertices
        let allX = allVertices.map(\.x) + pins.map(\.positionX)
        let allZ = allVertices.map(\.z) + pins.map(\.positionZ)
        self.minX = allX.min() ?? -1
        self.maxX = allX.max() ?? 1
        self.minZ = allZ.min() ?? -1
        self.maxZ = allZ.max() ?? 1
        self.size = size
        self.padding = size * 0.12
    }

    func path(for vertices: [Vertex2D]) -> Path {
        guard vertices.count >= 2 else { return Path() }
        var path = Path()
        path.move(to: point(for: vertices[0]))
        for vertex in vertices.dropFirst() {
            path.addLine(to: point(for: vertex))
        }
        path.closeSubpath()
        return path
    }

    func point(for vertex: Vertex2D) -> CGPoint {
        let rangeX = max(maxX - minX, 0.001)
        let rangeZ = max(maxZ - minZ, 0.001)
        let drawSize = size - padding * 2
        return CGPoint(
            x: padding + (vertex.x - minX) / rangeX * drawSize,
            y: padding + (1 - (vertex.z - minZ) / rangeZ) * drawSize
        )
    }

    func point(for pin: SpatialPinV1) -> CGPoint {
        point(for: Vertex2D(x: pin.positionX, z: pin.positionZ))
    }
}
