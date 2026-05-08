/// VanModeView — Full review of a captured room from the van (post-scan).

import SwiftUI
import AtlasScanCore

struct VanModeView: View {
    var room: RoomCaptureV2
    @ObservedObject var coordinator: ScanSessionCoordinator
    var onContinueScanning: (() -> Void)? = nil
    var onPropertyMap: (() -> Void)? = nil
    var onFinishVisit: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    private var currentRoom: RoomCaptureV2 {
        coordinator.room(withId: room.id) ?? room
    }

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
        .navigationTitle(currentRoom.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarLeading) { backButton } }
        .safeAreaInset(edge: .bottom) {
            reviewNavigationBar
        }
    }

    private var roomOverview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Floor Plan").font(.headline)
            if currentRoom.hasClosedFloorPolygon {
                V2CustomRoomShapeRenderer(vertices: currentRoom.polygonVertices)
                    .fill(Color.accentColor.opacity(0.12))
                    .overlay(
                        V2CustomRoomShapeRenderer(vertices: currentRoom.polygonVertices)
                            .stroke(Color.accentColor, lineWidth: 2)
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Room outline incomplete", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text("Scan more wall edges or save as draft.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 16) {
                        Label("\(currentRoom.wallSegments.count) walls", systemImage: "line.3.horizontal")
                        Label("\(currentRoom.pinnedObjects.count) pins", systemImage: "mappin.circle")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            HStack {
                if currentRoom.hasClosedFloorPolygon {
                    Label(String(format: "%.1f m²", currentRoom.floorAreaM2), systemImage: "square.dashed")
                } else {
                    Label("Room outline incomplete", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                Spacer()
                Label(String(format: "%.1f m ceiling", currentRoom.ceilingHeightM), systemImage: "arrow.up.and.down")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            if let raw = currentRoom.rawCapturedCeilingHeightM,
               abs(raw - currentRoom.ceilingHeightM) > 0.05 {
                Text(String(format: "Raw capture: %.1f m · Displayed: %.1f m", raw, currentRoom.ceilingHeightM))
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var fabricSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Wall Fabric").font(.headline)
            if currentRoom.wallSegments.isEmpty {
                Text("No wall segments captured").foregroundStyle(.secondary).font(.subheadline)
            } else {
                ForEach(currentRoom.wallSegments.indices, id: \.self) { i in
                    let seg = currentRoom.wallSegments[i]
                    HStack {
                        Text("Wall \(i + 1)").font(.subheadline)
                        Spacer()
                        Menu(wallFabricLabel(seg.fabric)) {
                            ForEach(WallFabric.allCases, id: \.self) { fabric in
                                Button {
                                    setWallFabric(fabric, at: i)
                                } label: {
                                    Label(wallFabricLabel(fabric), systemImage: wallFabricSymbol(fabric))
                                }
                            }
                        }
                        .font(.caption)
                    }
                    .padding(.vertical, 4)
                    if i < currentRoom.wallSegments.count - 1 { Divider() }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var pinsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pinned Objects (\(currentRoom.pinnedObjects.count))").font(.headline)
            ForEach(currentRoom.pinnedObjects) { pin in
                HStack {
                    Image(systemName: iconName(for: pin.objectType))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pin.label ?? pin.objectType.rawValue.capitalized).font(.subheadline)
                        if pin.anchorConfidence == .screenOnly {
                            Text("Screen only — needs review")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        } else if pin.hasResolvedWorldAnchor {
                            Text(String(format: "(%.2f, %.2f, %.2f)", pin.positionX, pin.positionY, pin.positionZ))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Not anchored — needs review")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                        Text(anchorStatusLabel(pin.anchorConfidence))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
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
        let roomFlags = coordinator.session.qaFlags.filter { $0.roomId == currentRoom.id }
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

    private var backButton: some View {
        Button("Back") { dismiss() }
    }

    private var reviewNavigationBar: some View {
        HStack(spacing: 10) {
            Button("Continue Scanning") {
                if let onContinueScanning {
                    onContinueScanning()
                } else {
                    dismiss()
                }
            }
            .buttonStyle(.borderedProminent)

            Button("Property Map") {
                if let onPropertyMap {
                    onPropertyMap()
                } else {
                    dismiss()
                }
            }
            .buttonStyle(.bordered)

            Button("Finish Visit") {
                if let onFinishVisit {
                    onFinishVisit()
                } else {
                    dismiss()
                }
            }
            .buttonStyle(.bordered)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
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
        case .abnormalCeilingHeight:  return "arrow.up.and.down.circle.fill"
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
        case .abnormalCeilingHeight:  return .orange
        }
    }

    private func anchorStatusLabel(_ confidence: SpatialPinAnchorConfidence) -> String {
        switch confidence {
        case .high: return "Anchor confidence: high"
        case .medium: return "Anchor confidence: medium"
        case .low: return "Anchor confidence: low"
        case .estimated: return "Anchor confidence: estimated"
        case .raycastEstimated: return "Anchor confidence: raycast estimated"
        case .screenOnly: return "Anchor confidence: screen only"
        }
    }

    private func setWallFabric(_ fabric: WallFabric, at index: Int) {
        var updatedRoom = currentRoom
        var segments = updatedRoom.wallSegments
        guard segments.indices.contains(index) else { return }
        segments[index].fabric = fabric
        updatedRoom.fabricCapture = FloorPlanFabricCaptureV1(roomId: updatedRoom.id, segments: segments)
        coordinator.upsertRoom(updatedRoom)
    }

    private func wallFabricLabel(_ fabric: WallFabric) -> String {
        switch fabric {
        case .externalWall: return "External Wall"
        case .internalWall: return "Internal Wall"
        case .partyWall: return "Party Wall"
        }
    }

    private func wallFabricSymbol(_ fabric: WallFabric) -> String {
        switch fabric {
        case .externalWall: return "house.fill"
        case .internalWall: return "rectangle.split.2x1"
        case .partyWall: return "building.2.fill"
        }
    }
}
