/// V2PostScanRoomReviewView — Shown immediately after a room scan completes.
///
/// Replaces the plain name-alert flow with a full-screen review that shows:
///   • Editable room name
///   • Floor plan polygon preview (from scan geometry)
///   • Area and ceiling height
///   • Evidence counts (pins, photos, voice notes captured during the scan)
///   • Geometry QA warning when the room shape needs review
///   • Action buttons: Save Room · Continue to Next Room · Finish Visit · Discard

import SwiftUI
import AtlasScanCore

struct V2PostScanRoomReviewView: View {

    // MARK: - Input

    let capturedRoom: RoomCaptureV2
    let pendingPinCount: Int
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
        photoCount: Int,
        voiceNoteCount: Int,
        onSave: @escaping (String) -> Void,
        onContinueToNextRoom: @escaping (String) -> Void,
        onFinishVisit: @escaping (String) -> Void,
        onDiscard: @escaping () -> Void
    ) {
        self.capturedRoom = capturedRoom
        self.pendingPinCount = pendingPinCount
        self.photoCount = photoCount
        self.voiceNoteCount = voiceNoteCount
        self.onSave = onSave
        self.onContinueToNextRoom = onContinueToNextRoom
        self.onFinishVisit = onFinishVisit
        self.onDiscard = onDiscard
        _roomName = State(initialValue: suggestedName)
    }

    // MARK: - Geometry QA helpers

    /// Rooms smaller than this area (m²) are flagged as suspicious.
    /// At 1 m² a domestic room is barely a cupboard — anything below this
    /// almost always indicates a partial or failed scan rather than a real room.
    private static let minimumTypicalRoomAreaM2 = 1.0

    /// Classifies the captured room's polygon quality.
    private enum GeometryQAResult {
        case collapsed   // < 3 vertices — unusable
        case triangle    // exactly 3 vertices — likely partial scan
        case tiny        // > 3 vertices but area < threshold
        case ok
    }

    private var geometryQA: GeometryQAResult {
        let count = capturedRoom.polygonVertices.count
        if count < 3 { return .collapsed }
        if count == 3 { return .triangle }
        if capturedRoom.floorAreaM2 < Self.minimumTypicalRoomAreaM2 { return .tiny }
        return .ok
    }

    private var hasGeometryQAIssue: Bool { geometryQA != .ok }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    capturedBadge
                    if hasGeometryQAIssue {
                        geometryQAWarningBanner
                    }
                    if capturedRoom.hasClosedFloorPolygon {
                        floorPlanSection
                    }
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

    private var geometryQAWarningBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Room shape needs review", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            Text(geometryQADetail)
                .font(.caption)
                .foregroundStyle(.secondary)
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

    private var geometryQADetail: String {
        switch geometryQA {
        case .collapsed:
            return "The captured room polygon has fewer than 3 points — geometry could not be reconstructed. The scan may need to be redone."
        case .triangle:
            return "The room shape is a triangle (3 points). This usually means the scan was cut short or the device lost tracking. Consider rescanning for a complete floor plan."
        case .tiny:
            return "Captured floor area is \(formattedFloorArea) — unusually small. The scan may be incomplete."
        case .ok:
            return ""
        }
    }

    /// Area formatted to one decimal place with unit, e.g. "0.4 m²".
    private var formattedFloorArea: String {
        String(format: "%.1f m²", capturedRoom.floorAreaM2)
    }

    private var floorPlanSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Floor Plan")
                .font(.headline)
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

    private var statsSection: some View {
        HStack(spacing: 20) {
            if capturedRoom.hasClosedFloorPolygon {
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
                value: "\(capturedRoom.wallSegments.count)",
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

    private var evidenceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Evidence Captured")
                .font(.headline)
            HStack(spacing: 16) {
                evidencePill(count: pendingPinCount, icon: "mappin.circle.fill", label: "Pins")
                evidencePill(count: photoCount, icon: "camera.fill", label: "Photos")
                evidencePill(count: voiceNoteCount, icon: "mic.fill", label: "Voice notes")
            }
        }
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
}

// MARK: - Previews

#Preview("Stable room") {
    V2PostScanRoomReviewView(
        capturedRoom: {
            var room = RoomCaptureV2(displayName: "Kitchen")
            room.polygonVertices = [
                Vertex2D(x: 0, z: 0), Vertex2D(x: 4, z: 0),
                Vertex2D(x: 4, z: 3.5), Vertex2D(x: 0, z: 3.5)
            ]
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

#Preview("Triangle room") {
    V2PostScanRoomReviewView(
        capturedRoom: {
            var room = RoomCaptureV2(displayName: "Living Room")
            room.polygonVertices = [
                Vertex2D(x: 0, z: 0), Vertex2D(x: 5, z: 0), Vertex2D(x: 2.5, z: 4)
            ]
            room.ceilingHeightM = 2.4
            return room
        }(),
        suggestedName: "Living Room",
        pendingPinCount: 1,
        photoCount: 2,
        voiceNoteCount: 0,
        onSave: { _ in },
        onContinueToNextRoom: { _ in },
        onFinishVisit: { _ in },
        onDiscard: {}
    )
}

#Preview("Collapsed room") {
    V2PostScanRoomReviewView(
        capturedRoom: {
            var room = RoomCaptureV2(displayName: "Room 3")
            room.polygonVertices = []
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

#Preview("Incomplete evidence") {
    V2PostScanRoomReviewView(
        capturedRoom: {
            var room = RoomCaptureV2(displayName: "Bedroom")
            room.polygonVertices = [
                Vertex2D(x: 0, z: 0), Vertex2D(x: 3.5, z: 0),
                Vertex2D(x: 3.5, z: 3), Vertex2D(x: 0, z: 3)
            ]
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

