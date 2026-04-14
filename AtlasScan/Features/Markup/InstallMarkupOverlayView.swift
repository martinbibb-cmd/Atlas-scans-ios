import SwiftUI

// MARK: - InstallMarkupOverlayView
//
// A SwiftUI canvas overlay that renders committed install markup and handles
// engineer drawing gestures for route and object placement.
//
// Designed to layer on top of RoomLayoutView (or any fixed-aspect canvas):
//
//   ZStack {
//       RoomLayoutView(…)
//       InstallMarkupOverlayView(
//           markupObjects: session.installMarkupObjects,
//           markupRoutes:  session.installMarkupRoutes,
//           viewModel:     markupVM
//       )
//   }
//
// Interactions:
//   • Tap canvas → handleTap (place object or add route waypoint)
//   • "Finish" button → finishRoute()
//   • "Undo" button → undoLastWaypoint()
//   • "Cancel" button → cancelRoute() / selectIdle()

struct InstallMarkupOverlayView: View {

    let markupObjects: [InstallMarkupObject]
    let markupRoutes: [InstallMarkupRoute]

    @ObservedObject var viewModel: InstallMarkupViewModel

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // Transparent tap surface
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { point in
                        let norm = normalize(point, size: geo.size)
                        viewModel.handleTap(at: norm)
                    }

                // Committed routes
                Canvas { context, size in
                    drawRoutes(context: context, size: size)
                }
                .allowsHitTesting(false)

                // In-progress route preview
                Canvas { context, size in
                    drawInProgressRoute(context: context, size: size)
                }
                .allowsHitTesting(false)

                // Committed object pins
                ForEach(markupObjects) { obj in
                    if let pos = pinPoint(for: obj.position, in: geo.size) {
                        objectPin(for: obj)
                            .position(pos)
                    }
                }

                // In-progress route waypoint dots
                ForEach(viewModel.currentRoutePath.indices, id: \.self) { idx in
                    if let pt = pinPoint(for: viewModel.currentRoutePath[idx], in: geo.size) {
                        Circle()
                            .fill(routeColor(for: drawingRouteKind).opacity(0.9))
                            .frame(width: 10, height: 10)
                            .position(pt)
                    }
                }

                // Toast
                if let msg = viewModel.confirmationMessage {
                    Text(msg)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 56)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.2), value: viewModel.confirmationMessage)
                }

                // Drawing toolbar
                drawingToolbar
            }
        }
    }

    // MARK: - Canvas drawing

    private func drawRoutes(context: GraphicsContext, size: CGSize) {
        for route in markupRoutes {
            drawRoute(route.path, color: routeColor(for: route.kind), layer: route.layer, context: context, size: size)
        }
    }

    private func drawInProgressRoute(context: GraphicsContext, size: CGSize) {
        guard case .drawingRoute(let kind) = viewModel.drawingMode,
              viewModel.currentRoutePath.count >= 2
        else { return }
        drawRoute(viewModel.currentRoutePath, color: routeColor(for: kind).opacity(0.6), layer: viewModel.activeLayer, context: context, size: size, dashed: true)
    }

    private func drawRoute(
        _ path: [NormalizedPoint2D],
        color: Color,
        layer: MarkupLayer,
        context: GraphicsContext,
        size: CGSize,
        dashed: Bool = false
    ) {
        guard path.count >= 2 else { return }
        var routePath = Path()
        let points = path.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
        routePath.move(to: points[0])
        for pt in points.dropFirst() {
            routePath.addLine(to: pt)
        }
        let lineWidth: CGFloat = layer == .existing ? 2.5 : 3
        let stroke = GraphicsContext.Shading.color(color)
        if dashed {
            context.stroke(routePath, with: stroke, style: StrokeStyle(lineWidth: lineWidth, dash: [6, 4]))
        } else {
            let style: StrokeStyle = layer == .existing
                ? StrokeStyle(lineWidth: lineWidth, dash: [8, 4])
                : StrokeStyle(lineWidth: lineWidth)
            context.stroke(routePath, with: stroke, style: style)
        }
    }

    // MARK: - Object pin

    @ViewBuilder
    private func objectPin(for obj: InstallMarkupObject) -> some View {
        let tint: Color = obj.layer == .existing ? .gray : .blue
        let symbol = ServiceObjectCategory(rawValue: obj.categoryRawValue)?.symbolName ?? "questionmark.circle"
        VStack(spacing: 2) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(tint, in: Circle())
                .shadow(radius: 2)
            Text(obj.displayLabel)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 4)
                .background(.ultraThinMaterial, in: Capsule())
        }
    }

    // MARK: - Drawing toolbar

    private var drawingToolbar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                // Cancel / back to idle
                Button {
                    if viewModel.drawingMode == .idle {
                        // nothing
                    } else {
                        viewModel.selectIdle()
                    }
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.title3)
                }
                .foregroundStyle(viewModel.drawingMode == .idle ? Color.secondary : Color.primary)
                .disabled(viewModel.drawingMode == .idle)

                Spacer()

                // Route undo
                if case .drawingRoute = viewModel.drawingMode {
                    Button {
                        viewModel.undoLastWaypoint()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.title3)
                    }
                    .disabled(viewModel.currentRoutePath.isEmpty)
                }

                // Route finish
                if case .drawingRoute = viewModel.drawingMode {
                    Button {
                        viewModel.finishRoute()
                    } label: {
                        Label("Finish Route", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.currentRoutePath.count < 2)
                }

                Spacer()

                // Layer toggle
                Picker("Layer", selection: Binding(
                    get: { viewModel.activeLayer },
                    set: { viewModel.activeLayer = $0 }
                )) {
                    ForEach(MarkupLayer.allCases, id: \.self) { layer in
                        Text(layer.rawValue.capitalized).tag(layer)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 140)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    // MARK: - Helpers

    private func normalize(_ point: CGPoint, size: CGSize) -> NormalizedPoint2D {
        NormalizedPoint2D(
            x: point.x / size.width,
            y: point.y / size.height
        )
    }

    private func pinPoint(for norm: NormalizedPoint2D, in size: CGSize) -> CGPoint? {
        guard size.width > 0, size.height > 0 else { return nil }
        return CGPoint(x: norm.x * size.width, y: norm.y * size.height)
    }

    private var drawingRouteKind: MarkupRouteKind {
        if case .drawingRoute(let kind) = viewModel.drawingMode { return kind }
        return .flow
    }

    private func routeColor(for kind: MarkupRouteKind) -> Color {
        switch kind {
        case .flow:       return .red
        case .return:     return .blue
        case .gas:        return .yellow
        case .coldWater:  return .cyan
        case .hotWater:   return .orange
        case .condensate: return .purple
        case .flue:       return .brown
        case .electrical: return .mint
        case .other:      return .gray
        }
    }
}

// MARK: - InstallMarkupSheet

/// Full-screen sheet wrapping the markup overlay on a room's layout canvas.
///
/// Provides the mode-picker palette above the room canvas and the drawing
/// toolbar at the bottom.  Committed markup is passed back via `onCommit`.
struct InstallMarkupSheet: View {

    let room: ScannedRoom
    let existingObjects: [InstallMarkupObject]
    let existingRoutes: [InstallMarkupRoute]

    var onCommit: (InstallMarkupObject?, InstallMarkupRoute?) -> Void
    var onDismiss: () -> Void

    @StateObject private var viewModel: InstallMarkupViewModel

    init(
        room: ScannedRoom,
        existingObjects: [InstallMarkupObject],
        existingRoutes: [InstallMarkupRoute],
        onCommit: @escaping (InstallMarkupObject?, InstallMarkupRoute?) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.room = room
        self.existingObjects = existingObjects
        self.existingRoutes = existingRoutes
        self.onCommit = onCommit
        self.onDismiss = onDismiss
        _viewModel = StateObject(wrappedValue: InstallMarkupViewModel(
            roomID: room.id,
            onAddObject: { obj in onCommit(obj, nil) },
            onAddRoute:  { route in onCommit(nil, route) }
        ))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Mode palette
                modePalette

                Divider()

                // Canvas: room layout + markup overlay
                ZStack {
                    RoomLayoutView(room: room)
                    InstallMarkupOverlayView(
                        markupObjects: existingObjects,
                        markupRoutes: existingRoutes,
                        viewModel: viewModel
                    )
                }
                .aspectRatio(1, contentMode: .fit)
                .padding(8)

                Spacer()
            }
            .navigationTitle("Install Markup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDismiss() }
                }
            }
        }
    }

    // MARK: - Mode palette

    private var modePalette: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Idle / inspect
                paletteButton(
                    label: "Select",
                    symbol: "hand.tap",
                    isActive: viewModel.drawingMode == .idle
                ) {
                    viewModel.selectIdle()
                }

                Divider().frame(height: 32)

                // Quick-place objects (most common heat-system types)
                ForEach(palettePlacementCategories, id: \.self) { rawValue in
                    let cat = ServiceObjectCategory(rawValue: rawValue)
                    paletteButton(
                        label: cat?.displayName ?? rawValue,
                        symbol: cat?.symbolName ?? "questionmark.circle",
                        isActive: viewModel.drawingMode == .placingObject(categoryRawValue: rawValue)
                    ) {
                        viewModel.selectObjectPlacement(categoryRawValue: rawValue)
                    }
                }

                Divider().frame(height: 32)

                // Route drawing kinds
                ForEach(MarkupRouteKind.allCases, id: \.self) { kind in
                    paletteButton(
                        label: kind.displayName,
                        symbol: kind.symbolName,
                        isActive: viewModel.drawingMode == .drawingRoute(kind: kind)
                    ) {
                        viewModel.selectRouteDrawing(kind: kind)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    @ViewBuilder
    private func paletteButton(
        label: String,
        symbol: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 18))
                Text(label)
                    .font(.system(size: 9))
                    .lineLimit(1)
            }
            .frame(width: 56, height: 48)
            .background(isActive ? Color.accentColor.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Data

    private let palettePlacementCategories: [String] = [
        ServiceObjectCategory.boiler.rawValue,
        ServiceObjectCategory.cylinder.rawValue,
        ServiceObjectCategory.heatPump.rawValue,
        ServiceObjectCategory.radiator.rawValue,
        ServiceObjectCategory.pump.rawValue,
    ]
}
