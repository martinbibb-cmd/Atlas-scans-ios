import SwiftUI

// MARK: - PropertyPlanView
//
// Whole-property plan overview screen.
//
// Shows:
//   • an interactive canvas with draggable room cards and adjacency link lines
//   • a list of rooms with link counts and navigation to individual room reviews
//   • a list of all confirmed and tentative room-to-room links
//
// Engineers can:
//   • drag rooms on the canvas to reposition them for review clarity
//   • tap a room card or row to navigate to its RoomReviewView
//   • add room-to-room links via the "Link Rooms" sheet
//   • swipe to delete an existing link

struct PropertyPlanView: View {

    @Binding var job: ScanJob
    @EnvironmentObject private var jobStore: ScanJobStore

    @State private var showingLinkSheet = false

    var body: some View {
        List {
            canvasSection
            roomsSection
            adjacenciesSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Property Plan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingLinkSheet = true
                } label: {
                    Label("Link Rooms", systemImage: "link.badge.plus")
                }
                .disabled(job.rooms.count < 2)
            }
        }
        .sheet(isPresented: $showingLinkSheet) {
            LinkRoomsSheet(job: $job) { adjacency in
                job.addAdjacency(adjacency)
                jobStore.save(job)
            }
        }
    }

    // MARK: - Sections

    private var canvasSection: some View {
        Section {
            PropertyPlanCanvas(job: $job) {
                jobStore.save(job)
            }
            .listRowInsets(EdgeInsets())
            .frame(minHeight: 280)
        } header: {
            Text("Layout Overview")
        } footer: {
            Text("Drag rooms to reposition for review clarity. Tap + to link rooms.")
                .font(.caption2)
        }
    }

    private var roomsSection: some View {
        Section("Rooms") {
            if job.rooms.isEmpty {
                Text("No rooms captured yet.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(job.rooms) { room in
                    NavigationLink {
                        RoomReviewView(room: room, job: $job)
                    } label: {
                        PropertyPlanRoomRow(
                            room: room,
                            adjacencies: job.adjacencies(for: room.id),
                            allRooms: job.rooms
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var adjacenciesSection: some View {
        if !job.roomAdjacencies.isEmpty {
            Section("Room Links") {
                ForEach(job.roomAdjacencies) { adjacency in
                    AdjacencyRowView(
                        adjacency: adjacency,
                        fromRoom: job.rooms.first { $0.id == adjacency.fromRoomID },
                        toRoom: job.rooms.first { $0.id == adjacency.toRoomID }
                    )
                }
                .onDelete { offsets in
                    for index in offsets {
                        job.removeAdjacency(id: job.roomAdjacencies[index].id)
                    }
                    jobStore.save(job)
                }
            }
        }
    }
}

// MARK: - PropertyPlanCanvas

/// Interactive canvas showing rooms as draggable cards with connection lines between linked rooms.
struct PropertyPlanCanvas: View {

    @Binding var job: ScanJob
    let onJobUpdated: () -> Void

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                Color(.systemGroupedBackground)

                // Adjacency connection lines drawn below the room cards.
                Canvas { ctx, _ in
                    for adjacency in job.roomAdjacencies {
                        let from = cardPosition(for: adjacency.fromRoomID, in: size)
                        let to   = cardPosition(for: adjacency.toRoomID,   in: size)
                        var path = Path()
                        path.move(to: from)
                        path.addLine(to: to)
                        let dash: [CGFloat] = adjacency.isConfirmed ? [] : [6, 4]
                        ctx.stroke(
                            path,
                            with: .color(adjacency.isConfirmed ? .blue.opacity(0.7) : .secondary.opacity(0.5)),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: dash)
                        )
                    }
                }

                // Draggable room cards.
                ForEach(job.rooms) { room in
                    let pos = cardPosition(for: room.id, in: size)
                    RoomPlanCard(
                        room: room,
                        hasLinks: !job.adjacencies(for: room.id).isEmpty
                    )
                    .position(pos)
                    .gesture(
                        DragGesture(minimumDistance: 4)
                            .onChanged { value in
                                let fx = max(0.08, min(0.92, value.location.x / size.width))
                                let fy = max(0.08, min(0.92, value.location.y / size.height))
                                job.setRoomPlacement(
                                    RoomPlacementOverride(id: room.id, x: fx, y: fy)
                                )
                            }
                            .onEnded { _ in
                                onJobUpdated()
                            }
                    )
                }
            }
        }
    }

    // MARK: - Position helpers

    private func cardPosition(for roomID: UUID, in size: CGSize) -> CGPoint {
        if let override = job.roomPlacement(for: roomID) {
            return CGPoint(x: override.x * size.width, y: override.y * size.height)
        }
        guard let index = job.rooms.firstIndex(where: { $0.id == roomID }) else {
            return CGPoint(x: size.width / 2, y: size.height / 2)
        }
        return defaultPosition(at: index, total: job.rooms.count, in: size)
    }

    /// Arranges rooms in a balanced grid when no placement override exists.
    private func defaultPosition(at index: Int, total: Int, in size: CGSize) -> CGPoint {
        let cols = max(1, Int(ceil(sqrt(Double(total)))))
        let rows = max(1, Int(ceil(Double(total) / Double(cols))))
        let col = index % cols
        let row = index / cols
        let xStep = size.width  / Double(cols + 1)
        let yStep = size.height / Double(rows + 1)
        return CGPoint(x: xStep * Double(col + 1), y: yStep * Double(row + 1))
    }
}

// MARK: - RoomPlanCard

/// A compact card representing one room in the property plan canvas.
struct RoomPlanCard: View {

    let room: ScannedRoom
    let hasLinks: Bool

    private let cardWidth:  CGFloat = 80
    private let cardHeight: CGFloat = 72

    var body: some View {
        VStack(spacing: 3) {
            // Show up to 3 service-object icons as a compact summary.
            HStack(spacing: 2) {
                ForEach(Array(room.taggedObjects.prefix(3))) { obj in
                    Image(systemName: obj.category.symbolName)
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
                if room.taggedObjects.count > 3 {
                    Text("+\(room.taggedObjects.count - 3)")
                        .font(.system(size: 7))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 12)

            Text(room.name)
                .font(.system(size: 10, weight: .semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.75)

            HStack(spacing: 3) {
                Text(room.displayFloor)
                    .font(.system(size: 7))
                    .foregroundStyle(.secondary)
                if room.isReviewed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .frame(width: cardWidth, height: cardHeight)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    hasLinks ? Color.blue.opacity(0.6) : Color(.separator),
                    lineWidth: 1.5
                )
        )
        .shadow(color: .black.opacity(0.12), radius: 3, x: 0, y: 1)
    }
}

// MARK: - PropertyPlanRoomRow

/// Room row for the rooms section of PropertyPlanView.
struct PropertyPlanRoomRow: View {

    let room: ScannedRoom
    let adjacencies: [RoomAdjacency]
    let allRooms: [ScannedRoom]

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(room.name)
                    .font(.subheadline.bold())

                HStack(spacing: 8) {
                    Text(room.displayFloor)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !room.taggedObjects.isEmpty {
                        Label("\(room.taggedObjects.count)", systemImage: "tag.fill")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }

                    if !adjacencies.isEmpty {
                        Label("\(adjacencies.count)", systemImage: "link")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !adjacencies.isEmpty {
                    connectedRoomsLabel
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if room.isReviewed {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 2)
    }

    private var connectedRoomsLabel: some View {
        let names = adjacencies.compactMap { adj -> String? in
            let otherID = adj.fromRoomID == room.id ? adj.toRoomID : adj.fromRoomID
            return allRooms.first { $0.id == otherID }?.name
        }
        return Text("Links to: \(names.joined(separator: ", "))")
    }
}

// MARK: - AdjacencyRowView

/// Row summarising one room-to-room adjacency link.
struct AdjacencyRowView: View {

    let adjacency: RoomAdjacency
    let fromRoom: ScannedRoom?
    let toRoom: ScannedRoom?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: adjacency.kind.symbolName)
                .frame(width: 28, height: 28)
                .foregroundStyle(.white)
                .background(adjacency.isConfirmed ? Color.blue : Color.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(fromRoom?.name ?? "Unknown")
                        .font(.subheadline.bold())
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(toRoom?.name ?? "Unknown")
                        .font(.subheadline.bold())
                }
                HStack(spacing: 6) {
                    Text(adjacency.kind.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !adjacency.isConfirmed {
                        Text("Unconfirmed")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    if !adjacency.notes.isEmpty {
                        Image(systemName: "note.text")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Previews

#if DEBUG
#Preview {
    NavigationStack {
        PropertyPlanView(job: .constant(MockData.sampleJob))
            .environmentObject(ScanJobStore())
    }
}
#endif
