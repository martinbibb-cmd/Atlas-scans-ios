/// PropertyMapView — Root view shown after launch; lists all scanned rooms.

import SwiftUI
import AtlasScanCore

struct PropertyMapView: View {
    @EnvironmentObject var coordinator: ScanSessionCoordinator
    @EnvironmentObject var recallClient: MindRecallClient

    @State private var showRoomCapture = false
    @State private var showHandoff = false
    @State private var showOutdoorFlue = false
    @State private var pendingRecall: UUID?
    @State private var showVisitSetup = false
    @State private var showDiscardConfirmation = false

    var body: some View {
        NavigationStack {
            Group {
                if coordinator.session.rooms.isEmpty {
                    emptyState
                } else {
                    roomList
                }
            }
            .navigationTitle("Property Map")
            .toolbar { toolbarContent }
            .fullScreenCover(isPresented: $showRoomCapture) {
                V2RoomLoopView(coordinator: coordinator)
            }
            .sheet(isPresented: $showVisitSetup) {
                V2VisitSetupSheet(
                    initialReference: coordinator.session.visitReference ?? "",
                    initialLabel: coordinator.session.visitLabel ?? ""
                ) { reference, label in
                    coordinator.session.visitReference = reference
                    coordinator.session.visitLabel = label.isEmpty ? nil : label
                    Task { await coordinator.saveSession() }
                    showVisitSetup = false
                }
            }
            .sheet(isPresented: $coordinator.showHandoff) {
                HandoffView(coordinator: coordinator)
            }
            .sheet(isPresented: $showOutdoorFlue) {
                V2OutdoorFlueModeView(coordinator: coordinator)
            }
            .confirmationDialog(
                "Discard active visit?",
                isPresented: $showDiscardConfirmation,
                titleVisibility: .visible
            ) {
                Button("Discard Visit", role: .destructive) {
                    coordinator.discardActiveSession()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All captured rooms, evidence, and visit data will be permanently deleted.")
            }
            .onAppear {
                if !hasVisitReference && !coordinator.isResumingExistingSession {
                    showVisitSetup = true
                }
            }
        }
        .v2DebugLifecycleOverlay()
    }

    // MARK: - Sub-views

    private var resumeBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Visit in progress", systemImage: "clock.arrow.circlepath")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            if let reference = coordinator.session.visitReference?.trimmingCharacters(in: .whitespacesAndNewlines),
               !reference.isEmpty {
                Text("Ref: \(reference)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            let roomCount = coordinator.session.rooms.count
            if roomCount > 0 {
                Text("\(roomCount) room\(roomCount == 1 ? "" : "s") saved")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Button("Resume Scanning") {
                    showRoomCapture = true
                }
                .buttonStyle(.borderedProminent)
                .font(.caption.weight(.semibold))

                Button("Discard Visit", role: .destructive) {
                    showDiscardConfirmation = true
                }
                .buttonStyle(.bordered)
                .font(.caption.weight(.semibold))
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            if coordinator.isResumingExistingSession {
                resumeBanner
            }
            Image(systemName: "house.fill")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("No rooms captured yet")
                .font(.headline)
            Button("Start Scan") {
                guard hasVisitReference else {
                    showVisitSetup = true
                    return
                }
                showRoomCapture = true
            }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    /// Rooms to render on the stitched map (geometry is available and trusted).
    private var mapVisibleRooms: [RoomCaptureV2] {
        coordinator.session.rooms.filter {
            $0.captureStatus == .saved || $0.captureStatus == .needsReview || $0.captureStatus == .captured
        }
    }

    /// Rooms to show in the room list (everything except deliberately discarded rooms).
    private var listedRooms: [RoomCaptureV2] {
        coordinator.session.rooms.filter { $0.captureStatus != .discarded }
    }

    private var roomList: some View {
        List {
            Section("Stitched Property Plan") {
                if mapVisibleRooms.isEmpty {
                    Text("No rooms saved yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    V2StitchedPropertyMapPreview(rooms: mapVisibleRooms)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            Section("Rooms") {
                ForEach(listedRooms) { room in
                    NavigationLink(destination: VanModeView(room: room, coordinator: coordinator)) {
                        roomRow(room)
                    }
                }
            }
        }
    }

    private func roomRow(_ room: RoomCaptureV2) -> some View {
        HStack {
            V2CustomRoomShapeRenderer(vertices: room.polygonVertices)
                .fill(Color.accentColor.opacity(0.15))
                .overlay(
                    V2CustomRoomShapeRenderer(vertices: room.polygonVertices)
                        .stroke(Color.accentColor, lineWidth: 1.5)
                )
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(room.displayName).font(.headline)
                if room.hasClosedFloorPolygon {
                    Text(String(format: "%.1f m²", room.floorAreaM2))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Room outline incomplete")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if let review = room.incomingConnectionReview {
                    let statusSuffix = review.status == .needsReview ? " · needs review" : ""
                    Text("\(review.note)\(statusSuffix)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(review.status == .needsReview ? .orange : .secondary)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button { showRoomCapture = true } label: {
                    Label("Add Room", systemImage: "plus.circle")
                }
                .disabled(!hasVisitReference)
                .accessibilityHint("Visit reference required before adding rooms.")
                Button { showOutdoorFlue = true } label: {
                    Label("Outdoor Flue Check", systemImage: "wind")
                }
                Button { coordinator.handOffToMind() } label: {
                    Label("Hand Off to Mind", systemImage: "arrow.up.forward.app")
                }
                Button {
                    showVisitSetup = true
                } label: {
                    Label("Set Visit Reference", systemImage: "number")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    private var hasVisitReference: Bool {
        !(coordinator.session.visitReference?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}

struct V2StitchedPropertyMapPreview: View {
    let rooms: [RoomCaptureV2]

    var body: some View {
        GeometryReader { geometry in
            let metrics = V2PropertyMapMetrics(rooms: rooms, size: geometry.size)
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentColor.opacity(0.06))

                ForEach(Array(rooms.enumerated()), id: \.element.id) { index, room in
                    let points = metrics.points(for: room.polygonVertices)
                    if points.count >= 3 {
                        Path { path in
                            path.move(to: points[0])
                            points.dropFirst().forEach { path.addLine(to: $0) }
                            path.closeSubpath()
                        }
                        .fill(Color.accentColor.opacity(0.08 + Double(index % 3) * 0.04))
                        .overlay(
                            Path { path in
                                path.move(to: points[0])
                                points.dropFirst().forEach { path.addLine(to: $0) }
                                path.closeSubpath()
                            }
                            .stroke(Color.accentColor.opacity(0.8), lineWidth: 1.5)
                        )
                    }

                    let centroid = metrics.point(for: roomCentroid(room))
                    Text(room.displayName)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color(.systemBackground).opacity(0.9), in: Capsule())
                        .position(centroid)
                }
            }
        }
    }

    private func roomCentroid(_ room: RoomCaptureV2) -> Vertex2D {
        guard !room.polygonVertices.isEmpty else { return .init(x: 0, z: 0) }
        let sum = room.polygonVertices.reduce((x: 0.0, z: 0.0)) { partial, vertex in
            (partial.x + vertex.x, partial.z + vertex.z)
        }
        let count = Double(room.polygonVertices.count)
        return Vertex2D(x: sum.x / count, z: sum.z / count)
    }
}

struct V2PropertyMapMetrics {
    private static let inset: CGFloat = 18
    let minX: Double
    let minZ: Double
    let scale: CGFloat
    let offsetX: CGFloat
    let offsetY: CGFloat
    let contentHeight: CGFloat

    init(rooms: [RoomCaptureV2], size: CGSize) {
        let vertices = rooms.flatMap(\.polygonVertices)
        let xs = vertices.map(\.x)
        let zs = vertices.map(\.z)
        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? 1
        let minZ = zs.min() ?? 0
        let maxZ = zs.max() ?? 1
        let rangeX = max(maxX - minX, 0.001)
        let rangeZ = max(maxZ - minZ, 0.001)
        let availableWidth = max(size.width - Self.inset * 2, 1)
        let availableHeight = max(size.height - Self.inset * 2, 1)
        let scale = min(availableWidth / CGFloat(rangeX), availableHeight / CGFloat(rangeZ))
        let contentWidth = CGFloat(rangeX) * scale
        let contentHeight = CGFloat(rangeZ) * scale
        self.minX = minX
        self.minZ = minZ
        self.scale = scale
        self.offsetX = Self.inset + (availableWidth - contentWidth) / 2
        self.offsetY = Self.inset + (availableHeight - contentHeight) / 2
        self.contentHeight = contentHeight
    }

    func point(for vertex: Vertex2D) -> CGPoint {
        CGPoint(
            x: offsetX + CGFloat(vertex.x - minX) * scale,
            y: offsetY + contentHeight - CGFloat(vertex.z - minZ) * scale
        )
    }

    func points(for vertices: [Vertex2D]) -> [CGPoint] {
        vertices.map(point(for:))
    }
}

private struct V2VisitSetupSheet: View {
    let initialReference: String
    let initialLabel: String
    let onSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var reference = ""
    @State private var label = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. JOB-2026-001", text: $reference)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                } header: {
                    Text("Visit / Job reference")
                } footer: {
                    Text("Required before capture begins.")
                }
                Section {
                    TextField("e.g. Smith / SW1A", text: $label)
                        .autocorrectionDisabled()
                } header: {
                    Text("Customer / postcode label (optional)")
                }
            }
            .navigationTitle("Start Visit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        let trimmedReference = reference.trimmingCharacters(in: .whitespacesAndNewlines)
                        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(trimmedReference, trimmedLabel)
                    }
                    .disabled(reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                reference = initialReference
                label = initialLabel
            }
        }
    }
}
