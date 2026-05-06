import SwiftUI

// MARK: - CustomRoomShapeRenderer
//
// A SwiftUI Shape that draws the true room outline as a closed polygon.
//
// This renderer replaces the legacy bounding-box rectangle approach (V1)
// with a polygon-accurate representation that correctly shows L-shapes,
// T-shapes, alcoves, and any other non-rectangular room geometry captured
// by the Anti-Square geometry engine.
//
// Usage:
//   CustomRoomShapeRenderer(vertices: scan.floorPlan?.outlinePoints ?? [])
//       .fill(Color.accentColor.opacity(0.1))
//       .overlay(
//           CustomRoomShapeRenderer(vertices: ...)
//               .stroke(Color.accentColor, lineWidth: 1.5)
//       )
//
// Coordinates: normalised (0…1) relative to the bounding rect passed to
// `path(in:)`, so the shape scales correctly at any display size.

struct CustomRoomShapeRenderer: Shape {

    /// The polygon vertices in normalised (0…1) coordinates.
    /// Must have at least 3 points to produce a visible shape.
    let vertices: [NormalisedPoint]

    func path(in rect: CGRect) -> Path {
        guard vertices.count >= 3 else { return Path() }

        var path = Path()
        let first = CGPoint(
            x: rect.minX + CGFloat(vertices[0].x) * rect.width,
            y: rect.minY + CGFloat(vertices[0].y) * rect.height
        )
        path.move(to: first)
        for vertex in vertices.dropFirst() {
            path.addLine(to: CGPoint(
                x: rect.minX + CGFloat(vertex.x) * rect.width,
                y: rect.minY + CGFloat(vertex.y) * rect.height
            ))
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - RoomPolygonThumbnail
//
// A compact, styled thumbnail view that uses CustomRoomShapeRenderer to show
// the actual room outline.  Falls back to a simple icon when no polygon data
// is available (e.g. manually entered rooms).
//
// Used in PropertyNavigatorView room cards and RoomLoopView headers.

struct RoomPolygonThumbnail: View {

    let outlinePoints: [NormalisedPoint]
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            if outlinePoints.count >= 3 {
                polygonView
            } else {
                fallbackIcon
            }
        }
        .frame(width: size, height: size)
    }

    private var polygonView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22)
                .fill(Color.accentColor.opacity(0.12))

            CustomRoomShapeRenderer(vertices: outlinePoints)
                .fill(Color.accentColor.opacity(0.18))
                .overlay(
                    CustomRoomShapeRenderer(vertices: outlinePoints)
                        .stroke(Color.accentColor, lineWidth: 1.5)
                )
                .padding(size * 0.14)
        }
    }

    private var fallbackIcon: some View {
        RoundedRectangle(cornerRadius: size * 0.22)
            .fill(Color.accentColor.opacity(0.12))
            .overlay(
                Image(systemName: "square.dashed")
                    .font(.system(size: size * 0.42))
                    .foregroundStyle(Color.accentColor.opacity(0.7))
            )
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Polygon room (L-shape)") {
    let lShape: [NormalisedPoint] = [
        NormalisedPoint(x: 0.05, y: 0.05),
        NormalisedPoint(x: 0.95, y: 0.05),
        NormalisedPoint(x: 0.95, y: 0.50),
        NormalisedPoint(x: 0.55, y: 0.50),
        NormalisedPoint(x: 0.55, y: 0.95),
        NormalisedPoint(x: 0.05, y: 0.95),
    ]
    return VStack(spacing: 24) {
        RoomPolygonThumbnail(outlinePoints: lShape, size: 80)
        RoomPolygonThumbnail(outlinePoints: lShape, size: 44)
        RoomPolygonThumbnail(outlinePoints: [], size: 44)
        CustomRoomShapeRenderer(vertices: lShape)
            .fill(Color.accentColor.opacity(0.15))
            .overlay(
                CustomRoomShapeRenderer(vertices: lShape)
                    .stroke(Color.accentColor, lineWidth: 2)
            )
            .frame(width: 200, height: 200)
            .background(Color(.systemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    .padding()
}
#endif
