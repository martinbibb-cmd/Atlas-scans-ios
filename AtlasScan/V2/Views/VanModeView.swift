/// VanModeView — Full review of a captured room from the van (post-scan).

import SwiftUI
import AtlasScanCore

struct VanModeView: View {
    var room: RoomCaptureV2
    @ObservedObject var coordinator: ScanSessionCoordinator

    @State private var showPinPicker = false
    @State private var selectedPinType: PinnedObjectType = .boiler

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                roomOverview
                fabricSection
                pinsSection
                qaSection
            }
            .padding()
        }
        .navigationTitle(room.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem {
                Button {
                    showPinPicker = true
                } label: {
                    Image(systemName: "mappin.and.ellipse")
                }
            }
        }
        .sheet(isPresented: $showPinPicker) {
            SpatialPinARView(
                roomId: room.id,
                pins: pinBinding,
                pendingObjectType: selectedPinType
            )
            .ignoresSafeArea()
        }
    }

    private var roomOverview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Floor Plan").font(.headline)
            CustomRoomShapeRenderer(vertices: room.polygonVertices)
                .fill(Color.accentColor.opacity(0.12))
                .stroke(Color.accentColor, lineWidth: 2)
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            HStack {
                Label(String(format: "%.1f m²", room.floorAreaM2), systemImage: "square.dashed")
                Spacer()
                Label(String(format: "%.1f m ceiling", room.ceilingHeightM), systemImage: "arrow.up.and.down")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    private var fabricSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Wall Fabric").font(.headline)
            if room.wallSegments.isEmpty {
                Text("No wall segments captured").foregroundStyle(.secondary).font(.subheadline)
            } else {
                ForEach(room.wallSegments.indices, id: \.self) { i in
                    let seg = room.wallSegments[i]
                    HStack {
                        Text("Wall \(i + 1)").font(.subheadline)
                        Spacer()
                        Text(seg.fabric.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    if i < room.wallSegments.count - 1 { Divider() }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var pinsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pinned Objects (\(room.pinnedObjects.count))").font(.headline)
            ForEach(room.pinnedObjects) { pin in
                HStack {
                    Image(systemName: iconName(for: pin.objectType))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pin.label ?? pin.objectType.rawValue.capitalized).font(.subheadline)
                        Text(String(format: "(%.2f, %.2f, %.2f)", pin.positionX, pin.positionY, pin.positionZ))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var qaSection: some View {
        let roomFlags = coordinator.session.qaFlags.filter { $0.roomId == room.id }
        return VStack(alignment: .leading, spacing: 8) {
            Text("QA Flags (\(roomFlags.count))").font(.headline)
            if roomFlags.isEmpty {
                Text("No QA flags for this room.").foregroundStyle(.secondary).font(.subheadline)
            } else {
                ForEach(roomFlags) { flag in
                    Label(flag.detail, systemImage: flagIcon(for: flag.type))
                        .font(.subheadline)
                        .foregroundStyle(flagColor(for: flag.type))
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Binding helper

    private var pinBinding: Binding<[SpatialPinV1]> {
        Binding {
            coordinator.session.rooms.first { $0.id == room.id }?.pinnedObjects ?? []
        } set: { newPins in
            guard let idx = coordinator.session.rooms.firstIndex(where: { $0.id == room.id }) else { return }
            coordinator.session.rooms[idx].pinnedObjects = newPins
        }
    }

    // MARK: - Icon helpers

    private func iconName(for type: PinnedObjectType) -> String {
        switch type {
        case .boiler, .heatPump:    return "flame.fill"
        case .flueTerminal:         return "arrow.up.circle.fill"
        case .hotWaterCylinder:     return "drop.fill"
        case .electricalPanel:      return "bolt.fill"
        case .gasmeter:             return "gauge"
        case .nearbyOpening:        return "door.left.hand.open"
        case .other:                return "mappin"
        }
    }

    private func flagIcon(for type: QAFlagType) -> String {
        switch type {
        case .clearancePass:          return "checkmark.circle.fill"
        case .clearanceConflict:      return "exclamationmark.triangle.fill"
        case .missingFabric:          return "questionmark.circle"
        case .lowPhotoCount:          return "photo.badge.exclamationmark"
        case .incompleteTranscript:   return "mic.slash"
        case .flueConflict:           return "exclamationmark.triangle"
        }
    }

    private func flagColor(for type: QAFlagType) -> Color {
        switch type {
        case .clearancePass:          return .green
        case .clearanceConflict:      return .red
        case .flueConflict:           return .red
        case .missingFabric:          return .orange
        case .lowPhotoCount:          return .orange
        case .incompleteTranscript:   return .orange
        }
    }
}
