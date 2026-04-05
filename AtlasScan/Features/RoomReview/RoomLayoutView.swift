import SwiftUI

// MARK: - RoomLayoutView
//
// Plan-view canvas for a single ScannedRoom.
//
// Shows:
//   • room perimeter polygon (derived from wall bearing + length)
//   • opening markers along wall edges
//   • placed service objects as icon pins
//   • selected-object highlight
//
// Interactions:
//   • tap an empty spot  → calls onTapRoom(_:) with the normalized coordinate
//   • tap an object pin  → calls onTapObject(_:)
//   • drag an object pin → calls onMoveObject(_:_:)

struct RoomLayoutView: View {

    let room: ScannedRoom
    var selectedObjectID: UUID?

    /// Called when the engineer taps an empty spot on the layout.
    /// Receives the normalized (0…1, 0…1) room coordinate.
    var onTapRoom: ((NormalizedPoint2D) -> Void)?

    /// Called when the engineer taps an existing object pin.
    var onTapObject: ((UUID) -> Void)?

    /// Called when the engineer finishes dragging an object to a new position.
    var onMoveObject: ((UUID, NormalizedPoint2D) -> Void)?

    // MARK: - Private layout geometry

    private let polygon: [CGPoint]
    private let openingSegments: [(wallIndex: Int, fraction: Double, width: Double)]

    init(
        room: ScannedRoom,
        selectedObjectID: UUID? = nil,
        onTapRoom: ((NormalizedPoint2D) -> Void)? = nil,
        onTapObject: ((UUID) -> Void)? = nil,
        onMoveObject: ((UUID, NormalizedPoint2D) -> Void)? = nil
    ) {
        self.room = room
        self.selectedObjectID = selectedObjectID
        self.onTapRoom = onTapRoom
        self.onTapObject = onTapObject
        self.onMoveObject = onMoveObject
        self.polygon = PlacementService.layoutPolygon(for: room)
        self.openingSegments = RoomLayoutView.buildOpeningSegments(room: room)
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                roomCanvas(size: geo.size)
                objectPins(size: geo.size)
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                let norm = toNormalized(location, size: geo.size)
                onTapRoom?(norm)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .padding(8)
    }

    // MARK: - Room canvas

    private func roomCanvas(size: CGSize) -> some View {
        Canvas { ctx, _ in
            guard polygon.count >= 3 else { return }
            let pts = polygon.map { toScreen($0, size: size) }

            // Filled room polygon
            var path = Path()
            path.move(to: pts[0])
            pts.dropFirst().forEach { path.addLine(to: $0) }
            path.closeSubpath()
            ctx.fill(path, with: .color(.secondary.opacity(0.08)))
            ctx.stroke(path, with: .color(.secondary.opacity(0.5)), lineWidth: 2)

            // Wall-edge labels ("W1", "W2", …)
            for i in 0..<polygon.count {
                let a = toScreen(polygon[i], size: size)
                let b = toScreen(polygon[(i + 1) % polygon.count], size: size)
                let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                let wallNum = i < room.walls.count ? room.walls[i].index + 1 : i + 1
                let label = "W\(wallNum)"
                ctx.draw(
                    Text(label)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary),
                    at: mid
                )
            }

            // Opening markers
            for seg in openingSegments {
                guard seg.wallIndex < polygon.count else { continue }
                let ai = polygon[seg.wallIndex]
                let bi = polygon[(seg.wallIndex + 1) % polygon.count]
                let screenA = toScreen(ai, size: size)
                let screenB = toScreen(bi, size: size)
                let fx = Double(seg.fraction)
                let cx = screenA.x + fx * (screenB.x - screenA.x)
                let cy = screenA.y + fx * (screenB.y - screenA.y)
                var openPath = Path()
                openPath.move(to: CGPoint(x: cx - 4, y: cy - 4))
                openPath.addLine(to: CGPoint(x: cx + 4, y: cy + 4))
                ctx.stroke(openPath, with: .color(.blue.opacity(0.7)), lineWidth: 2)
            }
        }
    }

    // MARK: - Object pins

    private func objectPins(size: CGSize) -> some View {
        ForEach(room.taggedObjects) { obj in
            if let pos = obj.normalizedPosition {
                let screenPt = toScreen(CGPoint(x: pos.x, y: pos.y), size: size)
                ObjectPin(
                    object: obj,
                    isSelected: obj.id == selectedObjectID
                )
                .position(screenPt)
                .onTapGesture {
                    onTapObject?(obj.id)
                }
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .onEnded { value in
                            let newNorm = toNormalized(value.location, size: size)
                            onMoveObject?(obj.id, newNorm)
                        }
                )
            }
        }
    }

    // MARK: - Coordinate helpers

    private func toScreen(_ norm: CGPoint, size: CGSize) -> CGPoint {
        CGPoint(
            x: norm.x * size.width,
            y: norm.y * size.height
        )
    }

    private func toNormalized(_ screen: CGPoint, size: CGSize) -> NormalizedPoint2D {
        NormalizedPoint2D(
            x: size.width  > 0 ? screen.x / size.width  : 0.5,
            y: size.height > 0 ? screen.y / size.height : 0.5
        )
    }

    // MARK: - Opening segment computation

    /// Default fraction along the wall where an opening is rendered (midpoint).
    private static let openingDefaultFraction: Double = 0.5

    /// Fallback opening width in metres when none is provided.
    private static let openingDefaultWidthMetres: Double = 0.9

    private static func buildOpeningSegments(
        room: ScannedRoom
    ) -> [(wallIndex: Int, fraction: Double, width: Double)] {
        room.openings.map { opening in
            // Place the opening at the midpoint of its wall.
            // Future work: use real offset data when available from RoomPlan.
            (
                wallIndex: opening.wallIndex,
                fraction: openingDefaultFraction,
                width: opening.widthMetres ?? openingDefaultWidthMetres
            )
        }
    }
}

// MARK: - ObjectPin

/// A small icon view representing a placed service object on the layout.
struct ObjectPin: View {
    let object: TaggedObject
    let isSelected: Bool

    private let size: CGFloat = 28

    var body: some View {
        ZStack {
            Circle()
                .fill(pinColor)
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)

            Image(systemName: object.category.symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
        }
        .overlay(
            Circle()
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2.5)
        )
        .scaleEffect(isSelected ? 1.2 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    private var pinColor: Color {
        switch object.category.groupName {
        case "Heat Source / Plant":  return .orange
        case "Emitters":             return .red
        case "Services / Utilities": return .blue
        case "Controls":             return .purple
        case "Structural / Siting":  return .gray
        default:                     return Color(.systemGray3)
        }
    }
}

// MARK: - RoomLayoutPlacementView
//
// Wraps RoomLayoutView and adds a "placement mode" banner + placement affordance.
// Used from AddObjectSheet to let the engineer place a new object.

struct RoomLayoutPlacementView: View {

    let room: ScannedRoom
    let category: ServiceObjectCategory

    /// Called with the chosen normalized position when the engineer taps.
    let onPlace: (NormalizedPoint2D, Int?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            placementBanner
            Divider()
            RoomLayoutView(room: room, onTapRoom: { point in
                // For wall-mounted categories, compute nearest wall index
                if category.defaultPlacementMode == .wallMounted {
                    let polygon = PlacementService.layoutPolygon(for: room)
                    let cgPt = CGPoint(x: point.x, y: point.y)
                    let wallIdx = PlacementService.nearestWallIndex(to: cgPt, in: polygon)
                    let snapped = PlacementService.snapToWall(point: cgPt, wallIndex: wallIdx, in: polygon)
                    let wallIndex = wallIdx < room.walls.count ? room.walls[wallIdx].index : wallIdx
                    onPlace(snapped, wallIndex)
                } else {
                    onPlace(point, nil)
                }
            })
        }
    }

    private var placementBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.tap")
                .font(.caption)
            Text(bannerText)
                .font(.caption)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.quaternary)
    }

    private var bannerText: String {
        switch category.defaultPlacementMode {
        case .wallMounted:
            return "Tap near a wall to place the \(category.displayName)"
        case .floorPlaced:
            return "Tap to place the \(category.displayName) in the room"
        case .unplaced:
            return "Tap to set a rough position, or skip"
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Layout — living room") {
    RoomLayoutView(
        room: MockData.livingRoom,
        selectedObjectID: MockData.livingRoom.taggedObjects.first?.id
    )
    .padding()
}

#Preview("Placement mode") {
    RoomLayoutPlacementView(
        room: MockData.livingRoom,
        category: .radiator
    ) { pos, wallIdx in
        print("Placed at \(pos), wallIdx \(String(describing: wallIdx))")
    }
    .padding()
}
#endif
