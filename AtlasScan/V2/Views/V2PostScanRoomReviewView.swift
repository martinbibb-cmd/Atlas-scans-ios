/// V2PostScanRoomReviewView — Shown immediately after a room scan completes.
///
/// Replaces the plain name-alert flow with a full-screen review that shows:
///   • Editable room name
///   • Floor plan polygon preview (from scan geometry)
///   • Area and ceiling height
///   • Evidence counts (pins, photos, voice notes captured during the scan)
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

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    capturedBadge
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
                    value: String(format: "%.1f m²", capturedRoom.floorAreaM2),
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
