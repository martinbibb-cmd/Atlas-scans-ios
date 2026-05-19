/// V2PostScanRoomReviewView — Shown immediately after a room scan completes.
///
/// Replaces the plain name-alert flow with a full-screen review that shows:
///   • Editable room name
///   • Floor plan preview — filled polygon for `closedPolygon`, wall lines for
///     `wallSegmentsOnly`, or a "needs review" banner for `estimated`/`failed`
///   • Area and ceiling height
///   • Evidence counts (pins, photos, voice notes captured during the scan)
///   • Geometry confidence badge
///   • Warning if any pins are screen-only (not spatially anchored)
///   • Action buttons: Save Room · Continue to Next Room · Finish Visit · Discard

import SwiftUI
import AtlasScanCore

struct V2PostScanRoomReviewView: View {

    // MARK: - Input

    let capturedRoom: RoomCaptureV2
    let pendingPinCount: Int
    let screenOnlyPinCount: Int
    let photoCount: Int
    let voiceNoteCount: Int

    // MARK: - Callbacks

    /// User confirmed save — passes chosen room name.
    let onSave: (String) -> Void
    /// User chose to continue directly to next room — passes chosen room name.
    let onContinueToNextRoom: (String) -> Void
    /// User chose to finish the visit — passes chosen room name.
    let onFinishVisit: (String) -> Void
    /// User discarded the scan without saving.
    let onDiscard: () -> Void

    // MARK: - State

    @State private var roomName: String

    // MARK: - Init

    init(
        capturedRoom: RoomCaptureV2,
        suggestedName: String,
        pendingPinCount: Int,
        screenOnlyPinCount: Int = 0,
        photoCount: Int,
        voiceNoteCount: Int,
        onSave: @escaping (String) -> Void,
        onContinueToNextRoom: @escaping (String) -> Void,
        onFinishVisit: @escaping (String) -> Void,
        onDiscard: @escaping () -> Void
    ) {
        self.capturedRoom = capturedRoom
        self.pendingPinCount = pendingPinCount
        self.screenOnlyPinCount = screenOnlyPinCount
        self.photoCount = photoCount
        self.voiceNoteCount = voiceNoteCount
        self.onSave = onSave
        self.onContinueToNextRoom = onContinueToNextRoom
        self.onFinishVisit = onFinishVisit
        self.onDiscard = onDiscard
        _roomName = State(initialValue: suggestedName)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    capturedBadge
                    geometrySection
                    statsSection
                    evidenceSection
                    nameSection
                }
                .padding()
            }
            .navigationTitle("Room Captured")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                actionBar
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard", role: .destructive) { onDiscard() }
                }
            }
        }
    }

    // MARK: - Sub-views

    private var capturedBadge: some View {
        Label("Scan complete", systemImage: "checkmark.circle.fill")
            .font(.headline)
            .foregroundStyle(.green)
    }

    // MARK: Geometry section

    /// The single geometry section adapts to `geometryConfidence`:
    ///   `.closedPolygon`    → filled floor-plan polygon
    ///   `.wallSegmentsOnly` → wall lines only (no fill) + warning banner
    ///   `.estimated`/`.failed` → warning banner only (no fake shape)
    @ViewBuilder
    private var geometrySection: some View {
        switch capturedRoom.geometryConfidence {
        case .closedPolygon:
            floorPlanSection
        case .wallSegmentsOnly:
            VStack(alignment: .leading, spacing: 10) {
                geometryWarningBanner
                wallLinesSection
            }
        case .estimated, .failed:
            geometryWarningBanner
        }
    }

    private var floorPlanSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Floor Plan")
                    .font(.headline)
                Spacer()
                confidenceBadge
            }
            V2CustomRoomShapeRenderer(vertices: capturedRoom.polygonVertices)
                .fill(Color.accentColor.opacity(0.15))
                .overlay(
                    V2CustomRoomShapeRenderer(vertices: capturedRoom.polygonVertices)
                        .stroke(Color.accentColor, lineWidth: 2)
                )
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var wallLinesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Wall Segments")
                    .font(.headline)
                Spacer()
                confidenceBadge
            }
            V2WallSegmentsShape(segments: capturedRoom.capturedWallSegments2D)
                .stroke(Color.accentColor, lineWidth: 2.5)
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var geometryWarningBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Label("Geometry needs review", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                Spacer()
                confidenceBadge
            }
            if capturedRoom.geometryWarnings.isEmpty {
                Text(defaultGeometryWarningDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(capturedRoom.geometryWarnings, id: \.self) { warning in
                    Text("• \(warning)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text("You can still save this room as a draft and rescan later.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.4), lineWidth: 1)
        )
    }

    private var defaultGeometryWarningDetail: String {
        switch capturedRoom.geometryConfidence {
        case .closedPolygon:
            return ""
        case .wallSegmentsOnly:
            return "Wall segments were captured but the room outline does not form a complete closed polygon. Check the scan for gaps."
        case .estimated:
            return "Room geometry could not be reliably derived from this capture. The scan may need to be redone."
        case .failed:
            return "No usable room geometry was captured. The scan needs to be redone."
        }
    }

    private var confidenceBadge: some View {
        Text(capturedRoom.geometryConfidence.displayLabel)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(confidenceBadgeColor.opacity(0.15), in: Capsule())
            .foregroundStyle(confidenceBadgeColor)
    }

    private var confidenceBadgeColor: Color {
        switch capturedRoom.geometryConfidence {
        case .closedPolygon:    return .green
        case .wallSegmentsOnly: return .orange
        case .estimated:        return .orange
        case .failed:           return .red
        }
    }

    // MARK: Stats

    private var statsSection: some View {
        HStack(spacing: 20) {
            if capturedRoom.geometryConfidence == .closedPolygon {
                statCell(
                    value: formattedFloorArea,
                    label: "Floor area",
                    icon: "square.dashed"
                )
            }
            statCell(
                value: String(format: "%.1f m", capturedRoom.ceilingHeightM),
                label: "Ceiling height",
                icon: "arrow.up.and.down"
            )
            statCell(
                value: "\(capturedRoom.capturedWallSegments2D.count)",
                label: "Walls",
                icon: "square.on.square"
            )
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func statCell(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
            Text(value)
                .font(.subheadline.weight(.semibold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Evidence

    private var evidenceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Evidence Captured")
                .font(.headline)
            HStack(spacing: 16) {
                evidencePill(count: pendingPinCount, icon: "mappin.circle.fill", label: "Pins")
                evidencePill(count: photoCount, icon: "camera.fill", label: "Photos")
                evidencePill(count: voiceNoteCount, icon: "mic.fill", label: "Voice notes")
            }
            if screenOnlyPinCount > 0 {
                screenOnlyPinWarning
            }
        }
    }

    private var screenOnlyPinWarning: some View {
        Label(
            "\(screenOnlyPinCount) pin\(screenOnlyPinCount == 1 ? "" : "s") not spatially anchored — screen-only placement. Pin\(screenOnlyPinCount == 1 ? "" : "s") will be counted but marked as needing review.",
            systemImage: "mappin.slash"
        )
        .font(.caption)
        .foregroundStyle(.orange)
    }

    private func evidencePill(count: Int, icon: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(count > 0 ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(count > 0 ? .primary : .secondary)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Name

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Room Name")
                .font(.headline)
            TextField("e.g. Kitchen", text: $roomName)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
        }
    }

    // MARK: Action bar

    private var actionBar: some View {
        VStack(spacing: 10) {
            Button {
                onSave(resolvedName)
            } label: {
                Label("Save Room", systemImage: "checkmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            HStack(spacing: 10) {
                Button {
                    onContinueToNextRoom(resolvedName)
                } label: {
                    Label("Next Room", systemImage: "arrow.right.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    onFinishVisit(resolvedName)
                } label: {
                    Label("Finish Visit", systemImage: "flag.checkered")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    // MARK: - Helpers

    private var resolvedName: String {
        roomName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Area formatted to one decimal place with unit, e.g. "0.4 m²".
    private var formattedFloorArea: String {
        String(format: "%.1f m²", capturedRoom.floorAreaM2)
    }
}

// MARK: - Previews

#Preview("Stable room — closed polygon") {
    V2PostScanRoomReviewView(
        capturedRoom: {
            var room = RoomCaptureV2(displayName: "Kitchen")
            room.polygonVertices = [
                Vertex2D(x: 0, z: 0), Vertex2D(x: 4, z: 0),
                Vertex2D(x: 4, z: 3.5), Vertex2D(x: 0, z: 3.5)
            ]
            room.capturedWallSegments2D = [
                RoomWallSegment2D(wallIndex: 0, start: Vertex2D(x: 0, z: 0), end: Vertex2D(x: 4, z: 0)),
                RoomWallSegment2D(wallIndex: 1, start: Vertex2D(x: 4, z: 0), end: Vertex2D(x: 4, z: 3.5)),
                RoomWallSegment2D(wallIndex: 2, start: Vertex2D(x: 4, z: 3.5), end: Vertex2D(x: 0, z: 3.5)),
                RoomWallSegment2D(wallIndex: 3, start: Vertex2D(x: 0, z: 3.5), end: Vertex2D(x: 0, z: 0)),
            ]
            room.geometryConfidence = .closedPolygon
            room.ceilingHeightM = 2.4
            return room
        }(),
        suggestedName: "Kitchen",
        pendingPinCount: 3,
        photoCount: 5,
        voiceNoteCount: 1,
        onSave: { _ in },
        onContinueToNextRoom: { _ in },
        onFinishVisit: { _ in },
        onDiscard: {}
    )
}

#Preview("Wall segments only — open scan") {
    V2PostScanRoomReviewView(
        capturedRoom: {
            var room = RoomCaptureV2(displayName: "Living Room")
            room.capturedWallSegments2D = [
                RoomWallSegment2D(wallIndex: 0, start: Vertex2D(x: 0, z: 0), end: Vertex2D(x: 5, z: 0)),
                RoomWallSegment2D(wallIndex: 1, start: Vertex2D(x: 5, z: 0), end: Vertex2D(x: 5, z: 4)),
                RoomWallSegment2D(wallIndex: 2, start: Vertex2D(x: 5, z: 4), end: Vertex2D(x: 0, z: 4)),
                // fourth wall absent — open scan
            ]
            room.geometryConfidence = .wallSegmentsOnly
            room.geometryWarnings = [
                "Room outline gap: 5.00 m between first and last wall endpoint — scan may be incomplete."
            ]
            room.ceilingHeightM = 2.4
            return room
        }(),
        suggestedName: "Living Room",
        pendingPinCount: 1,
        screenOnlyPinCount: 1,
        photoCount: 2,
        voiceNoteCount: 0,
        onSave: { _ in },
        onContinueToNextRoom: { _ in },
        onFinishVisit: { _ in },
        onDiscard: {}
    )
}

#Preview("Estimated — no closed polygon") {
    V2PostScanRoomReviewView(
        capturedRoom: {
            var room = RoomCaptureV2(displayName: "Room 3")
            room.geometryConfidence = .estimated
            room.geometryWarnings = [
                "Only one wall segment was placed — cannot form a room outline."
            ]
            room.ceilingHeightM = 2.4
            return room
        }(),
        suggestedName: "Room 3",
        pendingPinCount: 0,
        photoCount: 1,
        voiceNoteCount: 0,
        onSave: { _ in },
        onContinueToNextRoom: { _ in },
        onFinishVisit: { _ in },
        onDiscard: {}
    )
}

#Preview("Failed — no geometry") {
    V2PostScanRoomReviewView(
        capturedRoom: {
            var room = RoomCaptureV2(displayName: "Bedroom")
            room.geometryConfidence = .failed
            room.geometryWarnings = ["No wall segments were captured."]
            room.ceilingHeightM = 2.3
            return room
        }(),
        suggestedName: "Bedroom",
        pendingPinCount: 0,
        photoCount: 0,
        voiceNoteCount: 0,
        onSave: { _ in },
        onContinueToNextRoom: { _ in },
        onFinishVisit: { _ in },
        onDiscard: {}
    )
}


