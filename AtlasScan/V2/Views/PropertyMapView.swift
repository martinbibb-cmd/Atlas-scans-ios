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
            .sheet(isPresented: $coordinator.showHandoff) {
                HandoffView(coordinator: coordinator)
            }
            .sheet(isPresented: $showOutdoorFlue) {
                V2OutdoorFlueModeView(coordinator: coordinator)
            }
        }
    }

    // MARK: - Sub-views

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "house.fill")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("No rooms captured yet")
                .font(.headline)
            Button("Start Scan") { showRoomCapture = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private var roomList: some View {
        List(coordinator.session.rooms) { room in
            NavigationLink(destination: VanModeView(room: room, coordinator: coordinator)) {
                roomRow(room)
            }
        }
    }

    private func roomRow(_ room: RoomCaptureV2) -> some View {
        HStack {
            V2CustomRoomShapeRenderer(vertices: room.polygonVertices)
                .fill(Color.accentColor.opacity(0.15))
                .stroke(Color.accentColor, lineWidth: 1.5)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(room.displayName).font(.headline)
                Text(String(format: "%.1f m²", room.floorAreaM2)).font(.caption).foregroundStyle(.secondary)
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
                Button { showOutdoorFlue = true } label: {
                    Label("Outdoor Flue Check", systemImage: "wind")
                }
                Button { coordinator.handOffToMind() } label: {
                    Label("Hand Off to Mind", systemImage: "arrow.up.forward.app")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }
}
