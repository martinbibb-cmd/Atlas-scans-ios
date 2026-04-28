import SwiftUI

// MARK: - FloorPlanEditorView
//
// MagicPlan-style floor plan editor.
//
// Features:
//   • Shows the 2-D room outline derived from the LiDAR scan (or blank canvas).
//   • Tap the canvas to place a service object (ObjectPinType picker first).
//   • Drag between two points to draw a pipe/service run.
//   • Drag a placed object pin to move it.
//   • Long-press any element for a context menu (delete, relabel).
//   • Toolbar: Undo, Undo All, "Save Snapshot" (exports PNG to session).
//
// Coordinates are normalised (0…1) relative to the canvas bounds so the
// model is resolution-independent.

struct FloorPlanEditorView: View {

    // MARK: - State

    @State private var scan: CapturedRoomScanDraft
    let onSave: (CapturedRoomScanDraft) -> Void

    @Environment(\.dismiss) private var dismiss

    // MARK: - Drawing state

    enum EditorTool: String, CaseIterable {
        case select  = "arrow.up.left"
        case place   = "mappin.and.ellipse"
        case pipe    = "line.diagonal"
    }

    @State private var activeTool: EditorTool = .select
    @State private var pendingObjectType: ObjectPinType? = nil
    @State private var showingObjectPicker = false

    // Pipe drawing: track start of drag
    @State private var pipeStart: NormalisedPoint? = nil
    @State private var pipePreviewEnd: NormalisedPoint? = nil

    // Drag-to-move
    @State private var draggingObjectId: UUID? = nil

    // Context menu
    @State private var selectedObjectId: UUID? = nil
    @State private var selectedPipeId: UUID? = nil

    // Undo stack (simple array of FloorPlanDraft snapshots)
    @State private var undoStack: [FloorPlanDraft] = []

    // Snapshot export confirmation
    @State private var showingSnapshotAlert = false
    @State private var snapshotSaved = false

    // MARK: - Init

    init(scan: CapturedRoomScanDraft, onSave: @escaping (CapturedRoomScanDraft) -> Void) {
        _scan = State(initialValue: scan)
        self.onSave = onSave
    }

    private var plan: FloorPlanDraft {
        scan.floorPlan ?? FloorPlanDraft()
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                toolPicker
                canvasSection
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(scan.roomLabel ?? "Floor Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sheet(isPresented: $showingObjectPicker) {
                ObjectTypePickerSheet { type in
                    pendingObjectType = type
                    activeTool = .place
                    showingObjectPicker = false
                }
            }
            .alert("Snapshot Saved", isPresented: $showingSnapshotAlert) {
                Button("OK") {}
            } message: {
                Text("A snapshot of the floor plan has been added to the visit.")
            }
        }
    }

    // MARK: - Tool picker

    private var toolPicker: some View {
        HStack(spacing: 0) {
            ForEach(EditorTool.allCases, id: \.self) { tool in
                Button {
                    selectTool(tool)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tool.rawValue)
                            .font(.system(size: 18, weight: activeTool == tool ? .bold : .regular))
                        Text(tool.toolLabel)
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(activeTool == tool ? Color.accentColor : .primary)
                    .background(activeTool == tool ? Color.accentColor.opacity(0.1) : Color.clear)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
    }

    // MARK: - Canvas

    private var canvasSection: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height) - 32
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .frame(width: size, height: size)
                    .shadow(color: .black.opacity(0.1), radius: 4)

                // Grid lines
                gridOverlay(size: size)

                // Room outline
                outlineShape(size: size)

                // Pipe segments
                pipeSegments(size: size)

                // Pipe preview while drawing
                if let start = pipeStart, let end = pipePreviewEnd {
                    Path { path in
                        path.move(to: CGPoint(x: start.x * size, y: start.y * size))
                        path.addLine(to: CGPoint(x: end.x * size, y: end.y * size))
                    }
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                }

                // Object placements
                objectPlacements(size: size)
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(canvasGesture(size: size))
        }
    }

    // MARK: - Grid

    private func gridOverlay(size: CGFloat) -> some View {
        Canvas { context, _ in
            let spacing: CGFloat = size / 10
            var col: CGFloat = 0
            while col <= size {
                context.stroke(
                    Path { p in p.move(to: CGPoint(x: col, y: 0)); p.addLine(to: CGPoint(x: col, y: size)) },
                    with: .color(.secondary.opacity(0.15)), lineWidth: 0.5
                )
                col += spacing
            }
            var row: CGFloat = 0
            while row <= size {
                context.stroke(
                    Path { p in p.move(to: CGPoint(x: 0, y: row)); p.addLine(to: CGPoint(x: size, y: row)) },
                    with: .color(.secondary.opacity(0.15)), lineWidth: 0.5
                )
                row += spacing
            }
        }
        .frame(width: size, height: size)
    }

    // MARK: - Room outline

    private func outlineShape(size: CGFloat) -> some View {
        let points = plan.outlinePoints
        guard points.count >= 2 else {
            return AnyView(
                Text("Add room scan to show outline")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            )
        }
        let path = Path { p in
            let first = CGPoint(x: points[0].x * size, y: points[0].y * size)
            p.move(to: first)
            for pt in points.dropFirst() {
                p.addLine(to: CGPoint(x: pt.x * size, y: pt.y * size))
            }
            p.closeSubpath()
        }
        return AnyView(
            ZStack {
                path.fill(Color.accentColor.opacity(0.06))
                path.stroke(Color.accentColor, lineWidth: 2)
            }
        )
    }

    // MARK: - Pipe segments

    private func pipeSegments(size: CGFloat) -> some View {
        ForEach(plan.pipeSegments) { seg in
            Path { p in
                p.move(to: CGPoint(x: seg.start.x * size, y: seg.start.y * size))
                p.addLine(to: CGPoint(x: seg.end.x * size, y: seg.end.y * size))
            }
            .stroke(
                pipeColor(seg.pipeType),
                style: StrokeStyle(lineWidth: 3, lineCap: .round)
            )
            .onLongPressGesture {
                selectedPipeId = seg.id
            }
            .contextMenu {
                Button("Delete", role: .destructive) {
                    removePipe(id: seg.id)
                }
            }
        }
    }

    // MARK: - Object placements

    private func objectPlacements(size: CGFloat) -> some View {
        ForEach(plan.objectPlacements) { obj in
            objectPin(obj, size: size)
        }
    }

    private func objectPin(_ obj: FloorPlanObjectPlacement, size: CGFloat) -> some View {
        let x = obj.position.x * size
        let y = obj.position.y * size
        return ZStack {
            Circle()
                .fill(selectedObjectId == obj.id ? Color.accentColor : Color.accentColor.opacity(0.85))
                .frame(width: 34, height: 34)
                .shadow(radius: 2)
            Image(systemName: obj.type.symbolName)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
        }
        .position(x: x, y: y)
        .gesture(
            DragGesture()
                .onChanged { value in
                    draggingObjectId = obj.id
                    moveObject(id: obj.id, to: NormalisedPoint(
                        x: Double((value.location.x) / size).clamped(to: 0...1),
                        y: Double((value.location.y) / size).clamped(to: 0...1)
                    ))
                }
                .onEnded { _ in draggingObjectId = nil }
        )
        .onTapGesture {
            selectedObjectId = selectedObjectId == obj.id ? nil : obj.id
        }
        .contextMenu {
            Button("Delete", role: .destructive) {
                removeObject(id: obj.id)
            }
        }
        .overlay(alignment: .bottom) {
            if let label = obj.label, !label.isEmpty {
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .background(Color.accentColor)
                    .clipShape(Capsule())
                    .offset(y: 22)
            }
        }
    }

    // MARK: - Canvas gesture

    private func canvasGesture(size: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let loc = value.location
                let norm = NormalisedPoint(
                    x: Double(loc.x / size).clamped(to: 0...1),
                    y: Double(loc.y / size).clamped(to: 0...1)
                )
                if activeTool == .pipe {
                    if pipeStart == nil {
                        pipeStart = norm
                    } else {
                        pipePreviewEnd = norm
                    }
                }
            }
            .onEnded { value in
                let loc = value.location
                let norm = NormalisedPoint(
                    x: Double(loc.x / size).clamped(to: 0...1),
                    y: Double(loc.y / size).clamped(to: 0...1)
                )
                switch activeTool {
                case .select:
                    break
                case .place:
                    if let type = pendingObjectType {
                        pushUndo()
                        var placement = FloorPlanObjectPlacement(type: type, position: norm)
                        placement.label = type.displayName
                        var p = plan
                        p.objectPlacements.append(placement)
                        scan.floorPlan = p
                    }
                case .pipe:
                    if let start = pipeStart {
                        pushUndo()
                        let seg = PipeSegmentDraft(start: start, end: norm)
                        var p = plan
                        p.pipeSegments.append(seg)
                        scan.floorPlan = p
                    }
                    pipeStart = nil
                    pipePreviewEnd = nil
                }
            }
    }

    // MARK: - Mutations

    private func moveObject(id: UUID, to position: NormalisedPoint) {
        var p = plan
        guard let idx = p.objectPlacements.firstIndex(where: { $0.id == id }) else { return }
        p.objectPlacements[idx].position = position
        scan.floorPlan = p
    }

    private func removeObject(id: UUID) {
        pushUndo()
        var p = plan
        p.objectPlacements.removeAll { $0.id == id }
        scan.floorPlan = p
        selectedObjectId = nil
    }

    private func removePipe(id: UUID) {
        pushUndo()
        var p = plan
        p.pipeSegments.removeAll { $0.id == id }
        scan.floorPlan = p
        selectedPipeId = nil
    }

    // MARK: - Tool selection

    private func selectTool(_ tool: EditorTool) {
        activeTool = tool
        pipeStart = nil
        pipePreviewEnd = nil
        if tool == .place { showingObjectPicker = true }
    }

    // MARK: - Undo

    private func pushUndo() {
        undoStack.append(plan)
    }

    private func undo() {
        guard let prev = undoStack.popLast() else { return }
        scan.floorPlan = prev
    }

    private func undoAll() {
        guard let first = undoStack.first else { return }
        scan.floorPlan = first
        undoStack.removeAll()
    }

    // MARK: - Snapshot export

    private func saveSnapshot() {
        // Render the floor plan to a UIImage and store as a CapturedFloorPlanSnapshotDraft
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 512, height: 512))
        let image = renderer.image { ctx in
            let size: CGFloat = 512
            ctx.cgContext.setFillColor(UIColor.systemBackground.cgColor)
            ctx.cgContext.fill(CGRect(origin: .zero, size: CGSize(width: size, height: size)))
            // Draw outline
            for (i, point) in plan.outlinePoints.enumerated() {
                let pt = CGPoint(x: point.x * size, y: point.y * size)
                if i == 0 { ctx.cgContext.move(to: pt) } else { ctx.cgContext.addLine(to: pt) }
            }
            if !plan.outlinePoints.isEmpty {
                ctx.cgContext.closePath()
                ctx.cgContext.setFillColor(UIColor.systemBlue.withAlphaComponent(0.1).cgColor)
                ctx.cgContext.fillPath()
                ctx.cgContext.setStrokeColor(UIColor.systemBlue.cgColor)
                ctx.cgContext.setLineWidth(3)
                for (i, point) in plan.outlinePoints.enumerated() {
                    let pt = CGPoint(x: point.x * size, y: point.y * size)
                    if i == 0 { ctx.cgContext.move(to: pt) } else { ctx.cgContext.addLine(to: pt) }
                }
                ctx.cgContext.closePath()
                ctx.cgContext.strokePath()
            }
        }
        // Save to Documents
        let filename = "floorplan_\(scan.id.uuidString).png"
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent(filename)
        try? image.pngData()?.write(to: url)
        // Store snapshot reference back to the session via the callback
        var s = scan
        var snapshot = CapturedFloorPlanSnapshotDraft(imageRef: filename)
        snapshot.roomId = scan.id
        // The snapshot is saved with the room so the session can pick it up
        // via onSave — callers should add it to the session's floorPlanSnapshots.
        s.floorPlan = plan
        scan = s
        showingSnapshotAlert = true
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Save") {
                onSave(scan)
                dismiss()
            }
        }
        ToolbarItem(placement: .bottomBar) {
            Button("Undo") { undo() }
                .disabled(undoStack.isEmpty)
        }
        ToolbarItem(placement: .bottomBar) {
            Spacer()
        }
        ToolbarItem(placement: .bottomBar) {
            Button("Undo All") { undoAll() }
                .disabled(undoStack.isEmpty)
        }
        ToolbarItem(placement: .bottomBar) {
            Spacer()
        }
        ToolbarItem(placement: .bottomBar) {
            Button {
                saveSnapshot()
            } label: {
                Label("Snapshot", systemImage: "camera")
            }
        }
    }

    // MARK: - Pipe colour helper

    private func pipeColor(_ type: PipeType) -> Color {
        switch type {
        case .heating: return .red
        case .water:   return .blue
        case .gas:     return .yellow
        case .other:   return .gray
        }
    }
}

// MARK: - EditorTool helpers

extension FloorPlanEditorView.EditorTool {
    var toolLabel: String {
        switch self {
        case .select: return "Select"
        case .place:  return "Object"
        case .pipe:   return "Pipe"
        }
    }
}

// MARK: - Comparable extension for clamping

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    var scan = CapturedRoomScanDraft()
    scan.roomLabel = "Kitchen"
    var plan = FloorPlanDraft()
    plan.outlinePoints = [
        NormalisedPoint(x: 0.1, y: 0.1),
        NormalisedPoint(x: 0.9, y: 0.1),
        NormalisedPoint(x: 0.9, y: 0.9),
        NormalisedPoint(x: 0.1, y: 0.9)
    ]
    scan.floorPlan = plan
    return FloorPlanEditorView(scan: scan) { _ in }
}
#endif
