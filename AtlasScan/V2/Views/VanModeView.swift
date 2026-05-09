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
    @State private var selectedWallIndex = 0
    @State private var showNextRoomConnectionDialog = false

    private let sharedWallMidpointToleranceM = 0.45
    private let sharedWallAngleToleranceRadians = 0.35
    private let sharedWallLengthToleranceM = 0.8
    private let maxPinToWallDistanceM = 0.9
    /// Rejects effectively zero-length walls before point-to-segment projection.
    private let minimumValidSegmentLengthSquared = 0.0001

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

    private var visitHeaderText: String? {
        let reference = coordinator.session.visitReference?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !reference.isEmpty else { return nil }
        let label = coordinator.session.visitLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if label.isEmpty {
            return "Visit \(reference)"
        }
        return "Visit \(reference) · \(label)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                roomOverview
                evidenceByPointSection
                fabricSection
                pinsSection
                ghostPlacementsSection
                measurementsSection
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
        .confirmationDialog(
            "How does the next room connect?",
            isPresented: $showNextRoomConnectionDialog,
            titleVisibility: .visible
        ) {
            Button("Through selected doorway / opening") {
                continueToNextRoom(using: .throughOpening)
            }
            Button("Adjacent to selected wall") {
                continueToNextRoom(using: .adjacentWall)
            }
            Button("Separate / unlinked room") {
                continueToNextRoom(using: .separate)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(nextRoomConnectionPrompt)
        }
    }

    private var roomOverview: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let visitHeaderText {
                Label(visitHeaderText, systemImage: "number")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.tertiarySystemBackground), in: Capsule())
            }
            Text("Floor Plan").font(.headline)
            if currentRoom.hasClosedFloorPolygon {
                WallFabricRoomPlan(
                    walls: reviewWalls,
                    selectedWallIndex: selectedReviewWall?.index,
                    pinMarkers: wallPlanPins
                ) { selectedIndex in
                    selectedWallIndex = selectedIndex
                }
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                Text("Tap a wall to inspect or correct it. Atlas infers most walls automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    private var reviewWalls: [ReviewWallModel] {
        currentRoom.wallSegments.enumerated().map { index, segment in
            let inferred = inferredWallState(for: segment, at: index)
            let manualFabric = manualWallFabric(at: index)
            let displayedFabric = manualFabric ?? inferred.fabric
            let confidence: ReviewWallConfidence = {
                if let manualFabric, manualFabric == .partyWall {
                    return .manualException
                }
                if let manualFabric, manualFabric != inferred.fabric {
                    return .manualException
                }
                if inferred.isConfident {
                    return .inferred
                }
                return .unconfirmed
            }()
            let reason: String = {
                if confidence == .manualException {
                    if displayedFabric == .partyWall {
                        return "Marked as party wall by user."
                    }
                    return "Corrected from \(lowercasedWallFabricLabel(inferred.fabric))."
                }
                return inferred.reason
            }()
            return ReviewWallModel(
                index: index,
                segment: segment,
                displayedFabric: displayedFabric,
                inferredFabric: inferred.fabric,
                confidence: confidence,
                label: contextualWallLabel(for: segment, at: index, inferred: inferred),
                reason: reason,
                relatedRoomName: inferred.sharedRoomName
            )
        }
    }

    private var selectedReviewWall: ReviewWallModel? {
        let walls = reviewWalls
        guard !walls.isEmpty else { return nil }
        let safeIndex = walls.indices.contains(selectedWallIndex) ? selectedWallIndex : 0
        return walls[safeIndex]
    }

    private var wallPlanPins: [WallPlanPin] {
        currentRoom.pinnedObjects.compactMap { pin in
            guard pin.hasResolvedWorldAnchor else { return nil }
            return WallPlanPin(
                position: Vertex2D(x: pin.positionX, z: pin.positionZ),
                symbolName: iconName(for: pin.objectType),
                tint: .orange
            )
        }
    }

    private var nextRoomConnectionPrompt: String {
        guard let wall = selectedReviewWall else {
            return "Choose how the next room connects."
        }
        return "Use “\(wall.label)” as the connection context for the next room."
    }

    private var fabricSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Wall Fabric").font(.headline)
            if let wall = selectedReviewWall {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(reviewWalls) { candidate in
                            Button {
                                selectedWallIndex = candidate.index
                            } label: {
                                WallSelectorChip(
                                    title: candidate.chipLabel,
                                    subtitle: candidate.displayedFabricBadgeTitle,
                                    isSelected: candidate.index == wall.index
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(wall.label)
                                .font(.headline)
                            Text(String(format: "%.2f m wall run", wall.segment.lengthM))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: wallFabricSymbol(wall.displayedFabric))
                            .foregroundStyle(color(for: wall.displayedFabric))
                    }

                    HStack(spacing: 8) {
                        WallInferenceBadge(title: wall.displayedFabricBadgeTitle, tint: color(for: wall.displayedFabric))
                        WallInferenceBadge(title: wall.confidence.badgeTitle, tint: wall.confidence.tint)
                        if let relatedRoomName = wall.relatedRoomName {
                            WallInferenceBadge(title: "Shared with \(relatedRoomName)", tint: .blue)
                        }
                    }

                    Text(wall.reason)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        ForEach(WallFabric.allCases, id: \.self) { fabric in
                            Button {
                                setWallFabric(fabric, at: wall.index)
                            } label: {
                                Label(wallFabricLabel(fabric), systemImage: wallFabricSymbol(fabric))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(fabric == wall.displayedFabric ? color(for: fabric) : .gray)
                        }
                    }

                    if wall.displayedFabric != wall.inferredFabric || wall.confidence == .manualException {
                        Button("Use inferred \(wallFabricLabel(wall.inferredFabric))") {
                            setWallFabric(wall.inferredFabric, at: wall.index)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                Text("No wall segments captured")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func inferredWallState(for segment: WallSegmentV1, at index: Int) -> InferredWallState {
        guard currentRoom.hasClosedFloorPolygon else {
            return InferredWallState(
                fabric: .externalWall,
                reason: "Unconfirmed — needs review because the room outline is incomplete.",
                sharedRoomName: nil,
                isConfident: false
            )
        }

        if let match = sharedWallMatch(for: segment, excludingRoomId: currentRoom.id) {
            return InferredWallState(
                fabric: .internalWall,
                reason: "Shared with \(match.roomName).",
                sharedRoomName: match.roomName,
                isConfident: true
            )
        }

        return InferredWallState(
            fabric: .externalWall,
            reason: "Outer boundary.",
            sharedRoomName: nil,
            isConfident: true
        )
    }

    private func contextualWallLabel(
        for segment: WallSegmentV1,
        at index: Int,
        inferred: InferredWallState
    ) -> String {
        if let sharedRoomName = inferred.sharedRoomName {
            return "Shared with \(sharedRoomName)"
        }
        if manualWallFabric(at: index) == .partyWall {
            return "Party wall"
        }
        if let nearbyPinLabel = nearestPinWallLabel(to: segment) {
            return nearbyPinLabel
        }
        return inferred.fabric == .externalWall ? "External boundary wall" : "Internal wall"
    }

    private func sharedWallMatch(
        for segment: WallSegmentV1,
        excludingRoomId roomId: UUID
    ) -> SharedWallMatch? {
        let midpoint = v2WallMidpoint(segment)
        let angle = wallAngle(segment)
        let length = segment.lengthM

        return coordinator.session.rooms
            .filter { $0.id != roomId }
            .compactMap { otherRoom -> SharedWallMatch? in
                let match = otherRoom.wallSegments
                    .map { candidate -> (score: Double, candidate: WallSegmentV1)? in
                        let midpointDelta = distanceBetween(midpoint, v2WallMidpoint(candidate))
                        let angleDelta = wallAlignmentDifference(angle, wallAngle(candidate))
                        let lengthDelta = abs(length - candidate.lengthM)
                        guard
                            midpointDelta <= sharedWallMidpointToleranceM,
                            angleDelta <= sharedWallAngleToleranceRadians,
                            lengthDelta <= sharedWallLengthToleranceM
                        else {
                            return nil
                        }
                        let score =
                            (midpointDelta / sharedWallMidpointToleranceM) +
                            (angleDelta / sharedWallAngleToleranceRadians) +
                            (lengthDelta / sharedWallLengthToleranceM)
                        return (score, candidate)
                    }
                    .compactMap { $0 }
                    .min(by: { $0.score < $1.score })
                guard let match else { return nil }
                return SharedWallMatch(roomName: otherRoom.displayName, score: match.score)
            }
            .min(by: { $0.score < $1.score })
    }

    private func nearestPinWallLabel(to segment: WallSegmentV1) -> String? {
        let candidates = currentRoom.pinnedObjects.compactMap { pin -> (Double, String)? in
            guard pin.hasResolvedWorldAnchor else { return nil }
            let distance = distanceFromPoint(
                Vertex2D(x: pin.positionX, z: pin.positionZ),
                to: segment
            )
            guard distance <= maxPinToWallDistanceM else { return nil }
            return (distance, wallContextLabel(for: pin))
        }
        return candidates.min(by: { $0.0 < $1.0 })?.1
    }

    private func wallContextLabel(for pin: SpatialPinV1) -> String {
        if let label = pin.label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
            return "\(label) wall"
        }
        switch pin.objectType {
        case .boiler, .heatPump: return "Boiler wall"
        case .flueTerminal: return "Flue wall"
        case .hotWaterCylinder: return "Cylinder wall"
        case .electricalPanel: return "Consumer unit wall"
        case .gasmeter: return "Meter wall"
        case .nearbyOpening: return "Door wall"
        case .other: return "Equipment wall"
        }
    }

    private func manualWallFabric(at index: Int) -> WallFabric? {
        currentRoom.fabricCapture?.segments[safe: index]?.fabric
    }

    private func color(for fabric: WallFabric) -> Color {
        switch fabric {
        case .externalWall: return .indigo
        case .internalWall: return .green
        case .partyWall: return .orange
        }
    }

    private func continueToNextRoom(using kind: NextRoomConnectionKind) {
        coordinator.prepareNextRoomConnection(
            fromRoomId: currentRoom.id,
            wallIndex: selectedReviewWall?.index,
            kind: kind
        )
        if let onContinueScanning {
            onContinueScanning()
        } else {
            dismiss()
        }
    }

    private func wallAngle(_ segment: WallSegmentV1) -> Double {
        atan2(segment.endVertex.z - segment.startVertex.z, segment.endVertex.x - segment.startVertex.x)
    }

    private func wallAlignmentDifference(_ lhs: Double, _ rhs: Double) -> Double {
        min(
            abs(v2SmallestAngleDifference(lhs, rhs)),
            abs(v2SmallestAngleDifference(lhs, rhs + .pi))
        )
    }

    private func distanceBetween(_ lhs: Vertex2D, _ rhs: Vertex2D) -> Double {
        let dx = lhs.x - rhs.x
        let dz = lhs.z - rhs.z
        return sqrt(dx * dx + dz * dz)
    }

    private func distanceFromPoint(_ point: Vertex2D, to segment: WallSegmentV1) -> Double {
        let dx = segment.endVertex.x - segment.startVertex.x
        let dz = segment.endVertex.z - segment.startVertex.z
        let lengthSquared = dx * dx + dz * dz
        guard lengthSquared > minimumValidSegmentLengthSquared else { return distanceBetween(point, segment.startVertex) }
        let t = max(0, min(1, ((point.x - segment.startVertex.x) * dx + (point.z - segment.startVertex.z) * dz) / lengthSquared))
        let projection = Vertex2D(
            x: segment.startVertex.x + t * dx,
            z: segment.startVertex.z + t * dz
        )
        return distanceBetween(point, projection)
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
                    .foregroundStyle(Color.accentColor)
                Text(group.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }

            ForEach(group.pins) { pin in
                evidenceRow(
                    icon: iconName(for: pin.objectType),
                    title: pin.label ?? pin.objectType.rawValue.capitalized,
                    subtitle: pin.anchorConfidence == .screenOnly ? "Room note only — not spatially anchored" : nil,
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

            ForEach(group.measurements) { measurement in
                evidenceRow(
                    icon: "ruler.fill",
                    title: measurementTitle(measurement),
                    subtitle: measurementSubtitle(measurement),
                    needsReview: measurement.needsReview,
                    onDelete: {
                        coordinator.deleteEvidenceItem(
                            RecentCaptureItemV1.from(measurement: measurement)
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

        for measurement in currentRoom.measurements {
            let key: UUID? = measurement.startCapturePointId
            if groups[key] == nil {
                groups[key] = CapturePointEvidenceGroup(capturePointId: key)
            }
            groups[key]?.measurements.append(measurement)
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

    private var pinsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pinned Objects (\(currentRoom.pinnedObjects.count))").font(.headline)
            ForEach(currentRoom.pinnedObjects) { pin in
                HStack {
                    Image(systemName: iconName(for: pin.objectType))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pin.label ?? pin.objectType.rawValue.capitalized).font(.subheadline)
                        if pin.anchorConfidence == .screenOnly {
                            Text("Room note only — not spatially anchored")
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
            Text("Possible appliances (\(currentRoom.ghostAppliancePlacements.count))").font(.headline)
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

    private var measurementsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Measurements (\(currentRoom.measurements.count))").font(.headline)
            if currentRoom.measurements.isEmpty {
                Text("No measurements captured.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(currentRoom.measurements) { measurement in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Label(measurementTitle(measurement), systemImage: "ruler.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(measurement.needsReview ? .orange : .primary)
                            Spacer()
                            Button(role: .destructive) {
                                coordinator.deleteEvidenceItem(
                                    RecentCaptureItemV1.from(measurement: measurement)
                                )
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption2)
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        }
                        if let sub = measurementSubtitle(measurement) {
                            Text(sub)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("Start: \(measurement.startSurfaceSemantic.displayName) → End: \(measurement.endSurfaceSemantic.displayName)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(anchorStatusLabel(measurement.anchorConfidence))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if measurement.needsReview {
                            Label("Needs review", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.orange)
                        }
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
            Button("Continue to Next Room") {
                showNextRoomConnectionDialog = true
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
        case .worldLocked: return "Anchor confidence: world locked"
        case .screenOnly: return "Anchor confidence: room-note-only (not spatially anchored)"
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

    private func measurementTitle(_ measurement: SpatialMeasurementV1) -> String {
        String(format: "%.2f m", measurement.distanceMeters)
    }

    private func measurementSubtitle(_ measurement: SpatialMeasurementV1) -> String? {
        let h = measurement.horizontalDistanceMeters
        let v = measurement.verticalOffsetMeters
        if abs(v) >= 0.01 {
            let vSign = v >= 0 ? "▲" : "▼"
            return String(format: "H: %.2f m · %@%.2f m vertical", h, vSign, abs(v))
        }
        return String(format: "H: %.2f m · level", h)
    }

    private func wallFabricLabel(_ fabric: WallFabric) -> String {
        switch fabric {
        case .externalWall: return "External Wall"
        case .internalWall: return "Internal Wall"
        case .partyWall: return "Party Wall"
        }
    }

    private func lowercasedWallFabricLabel(_ fabric: WallFabric) -> String {
        wallFabricLabel(fabric).lowercased()
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

private struct ReviewWallModel: Identifiable {
    let index: Int
    let segment: WallSegmentV1
    let displayedFabric: WallFabric
    let inferredFabric: WallFabric
    let confidence: ReviewWallConfidence
    let label: String
    let reason: String
    let relatedRoomName: String?

    var id: Int { index }

    var chipLabel: String {
        if let relatedRoomName {
            return relatedRoomName
        }
        return displayedFabricBadgeTitle
    }

    var displayedFabricBadgeTitle: String {
        switch displayedFabric {
        case .externalWall: return "External"
        case .internalWall: return "Internal"
        case .partyWall: return "Party"
        }
    }
}

private struct InferredWallState {
    let fabric: WallFabric
    let reason: String
    let sharedRoomName: String?
    let isConfident: Bool
}

private struct SharedWallMatch {
    let roomName: String
    let score: Double
}

private enum ReviewWallConfidence: Equatable {
    case inferred
    case manualException
    case unconfirmed

    var badgeTitle: String {
        switch self {
        case .inferred: return "Inferred"
        case .manualException: return "Exception"
        case .unconfirmed: return "Unconfirmed"
        }
    }

    var tint: Color {
        switch self {
        case .inferred: return .blue
        case .manualException: return .orange
        case .unconfirmed: return .gray
        }
    }
}

private struct WallPlanPin: Identifiable {
    let id = UUID()
    let position: Vertex2D
    let symbolName: String
    let tint: Color
}

private struct WallFabricRoomPlan: View {
    let walls: [ReviewWallModel]
    let selectedWallIndex: Int?
    let pinMarkers: [WallPlanPin]
    let onSelectWall: (Int) -> Void

    init(
        walls: [ReviewWallModel],
        selectedWallIndex: Int?,
        pinMarkers: [WallPlanPin],
        onSelectWall: @escaping (Int) -> Void
    ) {
        self.walls = walls
        self.selectedWallIndex = selectedWallIndex
        self.pinMarkers = pinMarkers
        self.onSelectWall = onSelectWall
    }

    var body: some View {
        GeometryReader { geometry in
            let metrics = WallPlanMetrics(walls: walls.map(\.segment), size: geometry.size)
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.accentColor.opacity(0.06))

                ForEach(walls) { wall in
                    let line = metrics.line(for: wall.segment)
                    Path { path in
                        path.move(to: line.start)
                        path.addLine(to: line.end)
                    }
                    .stroke(
                        wall.index == selectedWallIndex ? Color.accentColor : wall.confidence.tint.opacity(0.7),
                        style: StrokeStyle(
                            lineWidth: wall.index == selectedWallIndex ? 10 : 6,
                            lineCap: .round
                        )
                    )
                    .overlay {
                        Path { path in
                            path.move(to: line.start)
                            path.addLine(to: line.end)
                        }
                        .stroke(.clear, style: StrokeStyle(lineWidth: 28, lineCap: .round))
                        .contentShape(Rectangle())
                        .onTapGesture { onSelectWall(wall.index) }
                    }
                }

                ForEach(pinMarkers) { pin in
                    let point = metrics.point(for: pin.position)
                    Image(systemName: pin.symbolName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(pin.tint, in: Circle())
                        .position(point)
                }
            }
        }
    }
}

private struct WallPlanMetrics {
    private static let planInset: CGFloat = 24

    let minX: Double
    let minZ: Double
    let scale: CGFloat
    let offsetX: CGFloat
    let offsetY: CGFloat
    let contentHeight: CGFloat

    init(walls: [WallSegmentV1], size: CGSize) {
        let vertices = walls.flatMap { [$0.startVertex, $0.endVertex] }
        let xs = vertices.map(\.x)
        let zs = vertices.map(\.z)
        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? 1
        let minZ = zs.min() ?? 0
        let maxZ = zs.max() ?? 1
        let rangeX = max(maxX - minX, 0.001)
        let rangeZ = max(maxZ - minZ, 0.001)
        let inset = Self.planInset
        let availableWidth = max(size.width - inset * 2, 1)
        let availableHeight = max(size.height - inset * 2, 1)
        let scale = min(availableWidth / CGFloat(rangeX), availableHeight / CGFloat(rangeZ))
        let contentWidth = CGFloat(rangeX) * scale
        let contentHeight = CGFloat(rangeZ) * scale

        self.minX = minX
        self.minZ = minZ
        self.scale = scale
        self.offsetX = inset + (availableWidth - contentWidth) / 2
        self.offsetY = inset + (availableHeight - contentHeight) / 2
        self.contentHeight = contentHeight
    }

    func point(for vertex: Vertex2D) -> CGPoint {
        CGPoint(
            x: offsetX + CGFloat(vertex.x - minX) * scale,
            y: offsetY + contentHeight - CGFloat(vertex.z - minZ) * scale
        )
    }

    func line(for segment: WallSegmentV1) -> (start: CGPoint, end: CGPoint) {
        (point(for: segment.startVertex), point(for: segment.endVertex))
    }
}

private struct WallSelectorChip: View {
    let title: String
    let subtitle: String
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            isSelected ? Color.accentColor.opacity(0.15) : Color(.tertiarySystemBackground),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
        )
    }
}

private struct WallInferenceBadge: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(tint.opacity(0.14), in: Capsule())
            .foregroundStyle(tint)
    }
}

// MARK: - CapturePointEvidenceGroup

/// Groups all evidence for one capture point within a room, used by VanModeView.
private struct CapturePointEvidenceGroup: Identifiable {
    let capturePointId: UUID?
    var pins: [SpatialPinV1] = []
    var ghosts: [GhostAppliancePlacementV1] = []
    var measurements: [SpatialMeasurementV1] = []

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

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
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
