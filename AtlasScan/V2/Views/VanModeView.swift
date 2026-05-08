/// VanModeView — Full review of a captured room from the van (post-scan).

import SwiftUI
import simd
import AtlasScanCore
import AtlasContracts

struct VanModeView: View {
    var room: RoomCaptureV2
    @ObservedObject var coordinator: ScanSessionCoordinator
    var onContinueScanning: (() -> Void)? = nil
    var onPropertyMap: (() -> Void)? = nil
    var onFinishVisit: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var placementBeingRefined: GhostAppliancePlacementV1?

    private var currentRoom: RoomCaptureV2 {
        coordinator.room(withId: room.id) ?? room
    }

    private var photoCount: Int {
        coordinator.session.photos.filter { $0.roomId == currentRoom.id }.count
    }

    private var voiceNoteCount: Int {
        coordinator.session.voiceNotes.filter { $0.roomId == currentRoom.id }.count
    }

    private var transcriptCount: Int {
        coordinator.session.transcripts.filter { $0.roomId == currentRoom.id }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                roomOverview
                evidenceByPointSection
                fabricSection
                pinsSection
                ghostPlacementsSection
                qaSection
            }
            .padding()
        }
        .navigationTitle(currentRoom.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarLeading) { backButton } }
        .sheet(item: $placementBeingRefined) { placement in
            V2GhostPlacementRefinementSheet(
                title: ghostModelLabel(for: placement),
                placement: placement
            ) { updatedPlacement in
                saveRefinedGhostPlacement(updatedPlacement)
            }
            .presentationDetents([.medium])
        }
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
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 16) {
                            Label(pluralLabel(currentRoom.pinnedObjects.count, singular: "pin"), systemImage: "mappin.circle")
                            Label(pluralLabel(photoCount, singular: "photo"), systemImage: "camera")
                            Label(pluralLabel(voiceNoteCount, singular: "voice note"), systemImage: "mic")
                        }
                        HStack(spacing: 16) {
                            Label(pluralLabel(transcriptCount, singular: "transcript"), systemImage: "text.quote")
                            Label(pluralLabel(currentRoom.ghostAppliancePlacements.count, singular: "ghost box", plural: "ghost boxes"), systemImage: "cube.transparent")
                        }
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

    // MARK: - Evidence by Capture Point

    /// All evidence for the current room, grouped by capturePointId.
    private var evidenceByPointSection: some View {
        let groups = capturePointGroups
        return VStack(alignment: .leading, spacing: 8) {
            Text("Evidence by Capture Point").font(.headline)
            if groups.isEmpty {
                Text("No evidence captured yet.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(groups) { group in
                    capturePointGroupView(group)
                    Divider()
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func capturePointGroupView(_ group: CapturePointEvidenceGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "scope")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.accentColor)
                Text(group.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.accentColor)
            }

            ForEach(group.pins) { pin in
                evidenceRow(
                    icon: iconName(for: pin.objectType),
                    title: pin.label ?? pin.objectType.rawValue.capitalized,
                    subtitle: pin.anchorConfidence == .screenOnly ? "Screen only — needs review" : nil,
                    needsReview: pin.anchorConfidence == .screenOnly,
                    onDelete: {
                        coordinator.deleteEvidenceItem(RecentCaptureItemV1.from(pin: pin))
                    }
                )
            }

            ForEach(roomPhotos.filter { $0.capturePointId == group.capturePointId }) { photo in
                evidenceRow(
                    icon: "photo.fill",
                    title: "Photo",
                    subtitle: nil,
                    needsReview: false,
                    onDelete: {
                        coordinator.deleteEvidenceItem(RecentCaptureItemV1.from(photo: photo))
                    }
                )
            }

            ForEach(roomVoiceNotes.filter { $0.capturePointId == group.capturePointId }) { note in
                let preview = note.processedTranscript.isEmpty ? nil : String(note.processedTranscript.prefix(50))
                evidenceRow(
                    icon: "mic.fill",
                    title: "Voice note",
                    subtitle: preview,
                    needsReview: false,
                    onDelete: {
                        coordinator.deleteEvidenceItem(RecentCaptureItemV1.from(voiceNote: note))
                    }
                )
            }

            ForEach(group.ghosts) { placement in
                let dims = placement.dimensionsMm
                evidenceRow(
                    icon: "cube.transparent.fill",
                    title: ghostModelLabel(for: placement),
                    subtitle: "\(dims.width)×\(dims.height)×\(dims.depth) mm",
                    needsReview: placement.needsReview,
                    onDelete: {
                        coordinator.deleteEvidenceItem(
                            RecentCaptureItemV1.from(ghost: placement, displayLabel: ghostModelLabel(for: placement))
                        )
                    }
                )
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func evidenceRow(
        icon: String,
        title: String,
        subtitle: String?,
        needsReview: Bool,
        onDelete: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(needsReview ? .orange : .secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if needsReview {
                    Text("Needs review")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .font(.caption2)
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
        .padding(.vertical, 2)
    }

    private var capturePointGroups: [CapturePointEvidenceGroup] {
        var groups: [UUID?: CapturePointEvidenceGroup] = [:]

        for pin in currentRoom.pinnedObjects {
            let key = pin.capturePointId
            if groups[key] == nil {
                groups[key] = CapturePointEvidenceGroup(capturePointId: key)
            }
            groups[key]?.pins.append(pin)
        }

        for photo in roomPhotos {
            let key = photo.capturePointId
            if groups[key] == nil {
                groups[key] = CapturePointEvidenceGroup(capturePointId: key)
            }
            // Photos are displayed inline from `roomPhotos`; group creation ensures the key exists.
        }

        for note in roomVoiceNotes {
            let key = note.capturePointId
            if groups[key] == nil {
                groups[key] = CapturePointEvidenceGroup(capturePointId: key)
            }
        }

        for ghost in currentRoom.ghostAppliancePlacements {
            let key = ghost.capturePointId
            if groups[key] == nil {
                groups[key] = CapturePointEvidenceGroup(capturePointId: key)
            }
            groups[key]?.ghosts.append(ghost)
        }

        // Sort: anchored capture points (non-nil id) first, unanchored last.
        // Within anchored groups, sort by UUID string for a deterministic stable order.
        return groups.values
            .sorted {
                switch ($0.capturePointId, $1.capturePointId) {
                case (.some(let a), .some(let b)): return a.uuidString < b.uuidString
                case (.some, .none):               return true
                case (.none, .some):               return false
                case (.none, .none):               return false
                }
            }
    }

    private var roomPhotos: [PhotoEvidenceV1] {
        coordinator.session.photos.filter { $0.roomId == currentRoom.id }
    }

    private var roomVoiceNotes: [VoiceNoteV1] {
        coordinator.session.voiceNotes.filter { $0.roomId == currentRoom.id }
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

    private var ghostPlacementsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ghost Appliances (\(currentRoom.ghostAppliancePlacements.count))").font(.headline)
            if currentRoom.ghostAppliancePlacements.isEmpty {
                Text("No ghost appliance placements captured.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(currentRoom.ghostAppliancePlacements) { placement in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Label(ghostModelLabel(for: placement), systemImage: "cube.transparent")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Label(placement.surfaceSemantic.displayName,
                                  systemImage: placement.surfaceSemantic.symbolName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(placement.surfaceSemantic.requiresReview ? .orange : .secondary)
                        }
                        Text("\(placement.dimensionsMm.width)x\(placement.dimensionsMm.height)x\(placement.dimensionsMm.depth) mm")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Capture point: \(placement.capturePointId.uuidString)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(anchorStatusLabel(placement.anchorConfidence))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(String(format: "Yaw %.0f° · Screen (%.0f%%, %.0f%%)", placement.rotationYaw, placement.screenPoint.x * 100, placement.screenPoint.y * 100))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if placement.needsReview {
                            Text("Needs review")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.orange)
                        }
                        Text(clearanceSummary(placement.clearanceOffsetsMm))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Button("Refine placement") {
                            placementBeingRefined = placement
                        }
                            .font(.caption2.weight(.semibold))
                            .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 4)
                    Divider()
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

    private func ghostModelLabel(for placement: GhostAppliancePlacementV1) -> String {
        if let customId = placement.customApplianceDefinitionId,
           let custom = currentRoom.customApplianceDefinitions.first(where: { $0.id == customId }) {
            return "\(custom.brand) \(custom.modelName)"
        }
        if let definition = MasterHardwareRegistry.registry.definition(for: placement.applianceModelId) {
            return "\(definition.brand) \(definition.displayName)"
        }
        return placement.applianceModelId
    }

    private func clearanceSummary(_ clearance: GhostApplianceClearanceOffsetsMmV1) -> String {
        clearance.formattedSummary
    }

    private func setWallFabric(_ fabric: WallFabric, at index: Int) {
        var updatedRoom = currentRoom
        var segments = updatedRoom.wallSegments
        guard segments.indices.contains(index) else { return }
        segments[index].fabric = fabric
        updatedRoom.fabricCapture = FloorPlanFabricCaptureV1(roomId: updatedRoom.id, segments: segments)
        coordinator.upsertRoom(updatedRoom)
    }

    private func saveRefinedGhostPlacement(_ placement: GhostAppliancePlacementV1) {
        var updatedRoom = currentRoom
        guard let index = updatedRoom.ghostAppliancePlacements.firstIndex(where: { $0.id == placement.id }) else { return }
        updatedRoom.ghostAppliancePlacements[index] = placement
        coordinator.upsertRoom(updatedRoom)
        Task { await coordinator.saveSession() }
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

    /// Returns `"\(count) \(singular)"` or `"\(count) \(plural)"`.
    /// When `plural` is omitted, an "s" suffix is appended for the plural form.
    private func pluralLabel(_ count: Int, singular: String, plural: String? = nil) -> String {
        let word = count == 1 ? singular : (plural ?? "\(singular)s")
        return "\(count) \(word)"
    }
}

// MARK: - CapturePointEvidenceGroup

/// Groups all evidence for one capture point within a room, used by VanModeView.
private struct CapturePointEvidenceGroup: Identifiable {
    let capturePointId: UUID?
    var pins: [SpatialPinV1] = []
    var ghosts: [GhostAppliancePlacementV1] = []

    var id: String { capturePointId?.uuidString ?? "unanchored" }

    var label: String {
        if let id = capturePointId {
            return "Point \(id.uuidString.prefix(8))…"
        }
        return "Unanchored evidence"
    }
}

private extension GhostApplianceClearanceOffsetsMmV1 {
    var formattedSummary: String {
        let entries: [(String, Int)] = [
            ("Top", top),
            ("Bottom", bottom),
            ("Front", front),
            ("Back", back),
            ("Left", left),
            ("Right", right),
        ]
        let nonZero = entries.filter { $0.1 != 0 }
        guard !nonZero.isEmpty else { return "Clearance: none specified" }
        let summary = nonZero
            .map { "\($0.0): \($0.1)mm" }
            .joined(separator: ", ")
        return "Clearance: \(summary)"
    }
}

private struct V2GhostPlacementRefinementSheet: View {
    let title: String
    let onSave: (GhostAppliancePlacementV1) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draftPlacement: GhostAppliancePlacementV1
    @State private var draftSurfaceSemantic: SurfaceSemanticV1

    private let nudgeStepM: Double = 0.05
    private let rotationStepDegrees: Double = 15

    init(
        title: String,
        placement: GhostAppliancePlacementV1,
        onSave: @escaping (GhostAppliancePlacementV1) -> Void
    ) {
        self.title = title
        self.onSave = onSave
        _draftPlacement = State(initialValue: placement)
        _draftSurfaceSemantic = State(initialValue: placement.surfaceSemantic)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Placement") {
                    Text(title)
                    Text("\(draftPlacement.dimensionsMm.width)x\(draftPlacement.dimensionsMm.height)x\(draftPlacement.dimensionsMm.depth) mm")
                        .foregroundStyle(.secondary)
                    Text(placementSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if draftPlacement.needsReview {
                        Label("Needs review", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                Section("Surface") {
                    Picker("Surface type", selection: $draftSurfaceSemantic) {
                        ForEach(SurfaceSemanticV1.allCases, id: \.self) { semantic in
                            Label(semantic.displayName, systemImage: semantic.symbolName)
                                .tag(semantic)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    if draftSurfaceSemantic.requiresReview {
                        Text("Surface type is unknown — please select the correct surface before saving.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Section("Rotate") {
                    HStack {
                        Button("-15°") { rotate(by: -rotationStepDegrees) }
                        Spacer()
                        Text("\(Int(draftPlacement.rotationYaw.rounded()))°")
                            .font(.headline.monospacedDigit())
                        Spacer()
                        Button("+15°") { rotate(by: rotationStepDegrees) }
                    }
                }

                Section("Nudge") {
                    HStack {
                        Button("Left") { nudge(by: horizontalVector * -nudgeStepM) }
                        Spacer()
                        Button("Right") { nudge(by: horizontalVector * nudgeStepM) }
                    }
                    HStack {
                        Button(verticalMinusLabel) { nudge(by: verticalVector * -nudgeStepM) }
                        Spacer()
                        Button(verticalPlusLabel) { nudge(by: verticalVector * nudgeStepM) }
                    }
                    HStack {
                        Button(depthMinusLabel) { nudge(by: depthVector * -nudgeStepM) }
                        Spacer()
                        Button(depthPlusLabel) { nudge(by: depthVector * nudgeStepM) }
                    }
                }
            }
            .navigationTitle("Refine placement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draftPlacement.withSurfaceSemantic(draftSurfaceSemantic))
                        dismiss()
                    }
                }
            }
        }
    }

    private var placementSummary: String {
        String(
            format: "World (%.2f, %.2f, %.2f) · Capture %@",
            draftPlacement.worldPositionX,
            draftPlacement.worldPositionY,
            draftPlacement.worldPositionZ,
            draftPlacement.capturePointId.uuidString
        )
    }

    private var verticalPlusLabel: String {
        draftPlacement.placementPlane == .wall ? "Up" : "Raise"
    }

    private var verticalMinusLabel: String {
        draftPlacement.placementPlane == .wall ? "Down" : "Lower"
    }

    private var depthPlusLabel: String {
        draftPlacement.placementPlane == .wall ? "Away from wall" : "Forward"
    }

    private var depthMinusLabel: String {
        draftPlacement.placementPlane == .wall ? "Toward wall" : "Back"
    }

    private var horizontalVector: SIMD3<Double> {
        switch draftPlacement.placementPlane {
        case .wall:
            let up = SIMD3<Double>(0, 1, 0)
            let normal = planeNormal
            return normalized(simd_cross(up, normal), fallback: SIMD3<Double>(1, 0, 0))
        case .floor, .ceiling, .worktop, .unknown:
            return SIMD3<Double>(1, 0, 0)
        }
    }

    private var verticalVector: SIMD3<Double> {
        SIMD3<Double>(0, 1, 0)
    }

    private var depthVector: SIMD3<Double> {
        switch draftPlacement.placementPlane {
        case .wall:
            return planeNormal
        case .floor, .ceiling, .worktop, .unknown:
            return SIMD3<Double>(0, 0, -1)
        }
    }

    private var planeNormal: SIMD3<Double> {
        normalized(
            SIMD3<Double>(
                draftPlacement.planeNormalX,
                draftPlacement.planeNormalY,
                draftPlacement.planeNormalZ
            ),
            fallback: SIMD3<Double>(0, 0, -1)
        )
    }

    private func rotate(by delta: Double) {
        draftPlacement = draftPlacement.translated(rotationYawDelta: delta)
    }

    private func nudge(by delta: SIMD3<Double>) {
        draftPlacement = draftPlacement.translated(dx: delta.x, dy: delta.y, dz: delta.z)
    }

    private func normalized(
        _ vector: SIMD3<Double>,
        fallback: SIMD3<Double>
    ) -> SIMD3<Double> {
        let length = simd_length(vector)
        guard length > 0.000_1 else { return fallback }
        return vector / length
    }
}
