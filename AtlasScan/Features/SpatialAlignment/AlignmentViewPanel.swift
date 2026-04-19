import SwiftUI
import AtlasContracts

// MARK: - AlignmentViewPanel
//
// 2-D "Structure View" for the Spatial Alignment feature.
//
// Displays a split-screen with:
//   • Side View (left / top on compact width) — vertical stack of anchors
//   • Top View  (right / bottom on compact width) — plan-view positions
//
// Visual rules (matching the Glass Box architecture):
//   • Solid marker / line  = confirmed position
//   • Dashed marker / line = inferred position
//   • Faded (0.4 opacity)  = low confidence or inferred route
//
// This view is purely presentational — it does not mutate any model state.

struct AlignmentViewPanel: View {

    let model: AtlasSpatialModelV1

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            if geo.size.width > geo.size.height {
                // Landscape / iPad — side by side
                HStack(spacing: 1) {
                    SideView(model: model)
                        .frame(maxWidth: .infinity)
                    Divider()
                    TopView(model: model)
                        .frame(maxWidth: .infinity)
                }
            } else {
                // Portrait — stacked
                VStack(spacing: 1) {
                    SideView(model: model)
                        .frame(maxHeight: .infinity)
                    Divider()
                    TopView(model: model)
                        .frame(maxHeight: .infinity)
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .overlay(alignment: .bottom) {
            legendBar
                .padding(.bottom, 8)
        }
    }

    // MARK: - Legend

    private var legendBar: some View {
        HStack(spacing: 16) {
            legendItem(style: .solid,  label: "Confirmed")
            legendItem(style: .dashed, label: "Inferred")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .padding(.horizontal, 16)
    }

    private enum MarkerStyle { case solid, dashed }

    private func legendItem(style: MarkerStyle, label: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .strokeBorder(
                    style: style == .dashed
                        ? StrokeStyle(lineWidth: 1.5, dash: [3, 2])
                        : StrokeStyle(lineWidth: 1.5),
                    antialiased: true
                )
                .frame(width: 14, height: 14)
                .foregroundStyle(style == .dashed ? Color.secondary : Color.primary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - SideView

/// Vertical cross-section showing anchor heights on the Y axis.
private struct SideView: View {

    let model: AtlasSpatialModelV1

    private var sortedAnchors: [AtlasAnchorV1] {
        model.anchors.sorted { $0.worldPosition.y > $1.worldPosition.y }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Side View")

            if model.anchors.isEmpty {
                emptyState("No anchors captured yet")
            } else {
                GeometryReader { geo in
                    SideViewCanvas(anchors: sortedAnchors, size: geo.size)
                }
                .padding(16)
            }
        }
    }
}

// MARK: - SideViewCanvas

private struct SideViewCanvas: View {

    let anchors: [AtlasAnchorV1]
    let size: CGSize

    private var minY: Double { anchors.map(\.worldPosition.y).min() ?? 0 }
    private var maxY: Double { anchors.map(\.worldPosition.y).max() ?? 1 }
    private var yRange: Double { max(maxY - minY, 0.5) }

    var body: some View {
        Canvas { ctx, size in
            for anchor in anchors {
                let normY = 1.0 - (anchor.worldPosition.y - minY) / yRange
                let cy = normY * size.height
                let cx = size.width / 2.0

                // Vertical connector line from anchor to bottom
                let isInferred = anchor.worldPosition.confidence == .inferred
                var linePath = Path()
                linePath.move(to: CGPoint(x: cx, y: cy))
                linePath.addLine(to: CGPoint(x: cx, y: size.height))
                ctx.stroke(
                    linePath,
                    with: .color(.secondary.opacity(isInferred ? 0.3 : 0.5)),
                    style: StrokeStyle(
                        lineWidth: 1,
                        dash: isInferred ? [4, 3] : []
                    )
                )

                // Anchor marker
                let r: CGFloat = 7
                let markerRect = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
                let markerPath = Path(ellipseIn: markerRect)
                ctx.fill(
                    markerPath,
                    with: .color(isInferred ? .secondary.opacity(0.4) : .primary)
                )
            }
        }
        .overlay(
            // Label overlay
            ZStack {
                ForEach(anchors) { anchor in
                    let normY = 1.0 - (anchor.worldPosition.y - minY) / yRange
                    let y = normY * size.height
                    AnchorLabel(
                        anchor: anchor,
                        heightM: anchor.worldPosition.y
                    )
                    .position(x: size.width / 2.0 + 30, y: y)
                }
            }
        )
    }
}

// MARK: - TopView

/// Plan (top-down) view showing anchor positions on the X/Z plane.
private struct TopView: View {

    let model: AtlasSpatialModelV1

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Top View")

            if model.anchors.isEmpty {
                emptyState("No anchors captured yet")
            } else {
                GeometryReader { geo in
                    TopViewCanvas(
                        anchors: model.anchors,
                        routes: model.inferredRoutes,
                        size: geo.size
                    )
                }
                .padding(16)
            }
        }
    }
}

// MARK: - TopViewCanvas

private struct TopViewCanvas: View {

    let anchors: [AtlasAnchorV1]
    let routes: [AtlasInferredRouteV1]
    let size: CGSize

    private var minX: Double { anchors.map(\.worldPosition.x).min() ?? 0 }
    private var maxX: Double { anchors.map(\.worldPosition.x).max() ?? 1 }
    private var minZ: Double { anchors.map(\.worldPosition.z).min() ?? 0 }
    private var maxZ: Double { anchors.map(\.worldPosition.z).max() ?? 1 }
    private var xRange: Double { max(maxX - minX, 0.5) }
    private var zRange: Double { max(maxZ - minZ, 0.5) }

    private func screenPoint(_ pos: AtlasWorldPositionV1, in size: CGSize) -> CGPoint {
        let nx = (pos.x - minX) / xRange
        let nz = (pos.z - minZ) / zRange
        return CGPoint(x: nx * size.width, y: nz * size.height)
    }

    var body: some View {
        Canvas { ctx, size in
            // Draw inferred routes first (behind anchors)
            for route in routes {
                guard route.path.count >= 2 else { continue }
                var routePath = Path()
                let first = screenPoint(route.path[0], in: size)
                routePath.move(to: first)
                for wp in route.path.dropFirst() {
                    routePath.addLine(to: screenPoint(wp, in: size))
                }
                ctx.stroke(
                    routePath,
                    with: .color(.secondary.opacity(0.4)),
                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                )
            }

            // Draw anchor markers
            for anchor in anchors {
                let pt = screenPoint(anchor.worldPosition, in: size)
                let isInferred = anchor.worldPosition.confidence == .inferred
                let r: CGFloat = 6
                let markerRect = CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)
                let markerPath = Path(ellipseIn: markerRect)
                ctx.fill(markerPath, with: .color(isInferred ? .secondary.opacity(0.4) : .primary))
            }
        }
        .overlay(
            ZStack {
                ForEach(anchors) { anchor in
                    let pt = screenPoint(anchor.worldPosition, in: size)
                    Text(anchor.label.capitalized)
                        .font(.caption2)
                        .foregroundStyle(anchor.worldPosition.confidence == .inferred
                            ? Color.secondary
                            : Color.primary)
                        .position(x: pt.x, y: pt.y - 14)
                }
            }
        )
    }
}

// MARK: - AnchorLabel

private struct AnchorLabel: View {
    let anchor: AtlasAnchorV1
    let heightM: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(anchor.label.capitalized)
                .font(.caption2.bold())
            Text(String(format: "%.1f m", heightM))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .opacity(anchor.worldPosition.confidence == .inferred ? 0.55 : 1.0)
    }
}

// MARK: - Shared helpers

private func sectionHeader(_ title: String) -> some View {
    Text(title)
        .font(.caption.bold())
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
}

private func emptyState(_ message: String) -> some View {
    Text(message)
        .font(.caption)
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding()
}

// MARK: - Previews

#if DEBUG
#Preview("With anchors") {
    let model = AtlasSpatialModelV1(
        anchors: [
            AtlasAnchorV1(
                id: "a1",
                label: "Boiler",
                worldPosition: AtlasWorldPositionV1(
                    x: 2.0, y: 0.8, z: 1.5,
                    confidence: .confirmed, source: .lidar
                ),
                roomId: "kitchen"
            ),
            AtlasAnchorV1(
                id: "a2",
                label: "Cylinder",
                worldPosition: AtlasWorldPositionV1(
                    x: 2.1, y: 3.2, z: 1.4,
                    confidence: .confirmed, source: .manual
                ),
                roomId: "airing_cupboard"
            ),
            AtlasAnchorV1(
                id: "a3",
                label: "Pump",
                worldPosition: AtlasWorldPositionV1(
                    x: 1.8, y: 3.0, z: 2.0,
                    confidence: .inferred, source: .derived
                )
            )
        ],
        verticalRelations: [
            AtlasVerticalRelationV1(
                fromAnchorId: "a1",
                toAnchorId: "a2",
                verticalDistanceM: 2.4,
                relation: .above
            )
        ],
        inferredRoutes: [
            AtlasInferredRouteV1(
                id: "r1",
                type: .pipe,
                path: [
                    AtlasWorldPositionV1(x: 2.0, y: 0.8, z: 1.5, confidence: .inferred, source: .derived),
                    AtlasWorldPositionV1(x: 2.0, y: 3.2, z: 1.5, confidence: .inferred, source: .derived)
                ],
                reason: "Vertical rise from boiler to cylinder — standard primary circuit routing"
            )
        ]
    )
    return NavigationStack {
        AlignmentViewPanel(model: model)
            .navigationTitle("Alignment View")
            .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Empty model") {
    AlignmentViewPanel(model: AtlasSpatialModelV1())
}
#endif
