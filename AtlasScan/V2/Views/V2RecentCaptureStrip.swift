/// V2RecentCaptureStrip — Derived view model and compact evidence strip for recent captures.
///
/// RecentCaptureItemV1 is a lightweight, derived-only view model.
/// It is never persisted; it is built on the fly from the live session state.

import SwiftUI
import AtlasScanCore

// MARK: - RecentCaptureItemV1

/// A lightweight derived view model representing one piece of captured evidence.
///
/// Built on-the-fly from live session data — not persisted separately.
/// `sourceEvidenceId` is the UUID of the underlying evidence record
/// (pin.id, photo.id, voiceNote.id, ghostPlacement.id) so it can be
/// located and removed from the canonical session store.
struct RecentCaptureItemV1: Identifiable, Equatable {

    enum EvidenceType: String, Equatable {
        case objectPin
        case photo
        case voiceNote
        case note
        case ghostAppliance
        case measurement
    }

    let id: UUID
    let roomId: UUID
    let capturePointId: UUID?
    let evidenceType: EvidenceType
    let title: String
    let subtitle: String?
    let createdAt: Date
    /// True when the underlying evidence has anchorConfidence == .screenOnly
    /// or placement plane == .unknown, and should show the amber review badge.
    let needsReview: Bool
    /// UUID of the source evidence record.
    let sourceEvidenceId: UUID

    // MARK: - Static factories

    static func from(pin: SpatialPinV1) -> RecentCaptureItemV1 {
        let subtitle: String? = pin.anchorConfidence == .screenOnly
            ? "Room note only — not spatially anchored"
            : nil
        return RecentCaptureItemV1(
            id: UUID(),
            roomId: pin.roomId,
            capturePointId: pin.capturePointId,
            evidenceType: .objectPin,
            title: pin.label ?? pin.objectType.rawValue.capitalized,
            subtitle: subtitle,
            createdAt: Date(),   // SpatialPinV1 carries no creation timestamp; caller-site Date() is equivalent.
            needsReview: pin.anchorConfidence == .screenOnly,
            sourceEvidenceId: pin.id
        )
    }

    static func from(photo: PhotoEvidenceV1) -> RecentCaptureItemV1 {
        let date = ISO8601DateFormatter().date(from: photo.capturedAt) ?? Date()
        return RecentCaptureItemV1(
            id: UUID(),
            roomId: photo.roomId,
            capturePointId: photo.capturePointId,
            evidenceType: .photo,
            title: "Photo",
            subtitle: nil,
            createdAt: date,
            needsReview: false,
            sourceEvidenceId: photo.id
        )
    }

    static func from(voiceNote: VoiceNoteV1) -> RecentCaptureItemV1 {
        let date = ISO8601DateFormatter().date(from: voiceNote.recordedAt) ?? Date()
        let preview = voiceNote.processedTranscript.isEmpty
            ? nil
            : String(voiceNote.processedTranscript.prefix(40))
        return RecentCaptureItemV1(
            id: UUID(),
            roomId: voiceNote.roomId,
            capturePointId: voiceNote.capturePointId,
            evidenceType: .voiceNote,
            title: "Voice note",
            subtitle: preview,
            createdAt: date,
            needsReview: false,
            sourceEvidenceId: voiceNote.id
        )
    }

    static func fromObservationNote(_ note: VoiceNoteV1) -> RecentCaptureItemV1 {
        let date = ISO8601DateFormatter().date(from: note.recordedAt) ?? Date()
        let preview = note.processedTranscript.isEmpty
            ? nil
            : String(note.processedTranscript.prefix(40))
        return RecentCaptureItemV1(
            id: UUID(),
            roomId: note.roomId,
            capturePointId: note.capturePointId,
            evidenceType: .note,
            title: "Note",
            subtitle: preview,
            createdAt: date,
            needsReview: false,
            sourceEvidenceId: note.id
        )
    }

    static func from(ghost: GhostAppliancePlacementV1, displayLabel: String) -> RecentCaptureItemV1 {
        let dims = ghost.dimensionsMm
        let subtitle = "\(dims.width)×\(dims.height)×\(dims.depth) mm"
        return RecentCaptureItemV1(
            id: UUID(),
            roomId: ghost.roomId,
            capturePointId: ghost.capturePointId,
            evidenceType: .ghostAppliance,
            title: displayLabel,
            subtitle: subtitle,
            createdAt: ghost.createdAt,
            needsReview: ghost.needsReview,
            sourceEvidenceId: ghost.id
        )
    }

    static func from(measurement: SpatialMeasurementV1) -> RecentCaptureItemV1 {
        let distanceText = String(format: "%.2f m", measurement.distanceMeters)
        let vertText: String
        let absV = abs(measurement.verticalOffsetMeters)
        if absV >= 0.01 {
            let sign = measurement.verticalOffsetMeters >= 0 ? "▲" : "▼"
            vertText = " \(sign)\(String(format: "%.2f m", absV))"
        } else {
            vertText = ""
        }
        let subtitle = distanceText + vertText
        return RecentCaptureItemV1(
            id: UUID(),
            roomId: measurement.roomId,
            capturePointId: measurement.startCapturePointId,
            evidenceType: .measurement,
            title: "Measurement",
            subtitle: subtitle,
            createdAt: measurement.createdAt,
            needsReview: measurement.needsReview,
            sourceEvidenceId: measurement.id
        )
    }
}

// MARK: - V2RecentCaptureStripView

/// Compact horizontal evidence strip showing the most recent captures for the active room.
///
/// Placed above the bottom dock during live capture.
/// Hidden automatically when there are no items.
/// - Tap item → triggers `onTap` (show detail / highlight capture point).
/// - Long press item → triggers `onDelete` after confirmation.
struct V2RecentCaptureStripView: View {

    let items: [RecentCaptureItemV1]
    let onTap: (RecentCaptureItemV1) -> Void
    let onDelete: (RecentCaptureItemV1) -> Void

    var body: some View {
        if items.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items) { item in
                        V2EvidenceChipView(item: item) {
                            onTap(item)
                        } onDelete: {
                            onDelete(item)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }
        }
    }
}

// MARK: - V2EvidenceChipView (private)

private struct V2EvidenceChipView: View {
    let item: RecentCaptureItemV1
    let onTap: () -> Void
    let onDelete: () -> Void

    @State private var showDeleteConfirm = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                Image(systemName: iconName)
                    .font(.caption.weight(.semibold))
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                if item.needsReview {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(chipBackground, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .confirmationDialog(
            "Remove \(item.title)?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the item from the current capture session.")
        }
        .onLongPressGesture {
            showDeleteConfirm = true
        }
    }

    private var iconName: String {
        switch item.evidenceType {
        case .objectPin:      return "mappin.circle.fill"
        case .photo:          return "photo.fill"
        case .voiceNote:      return "mic.fill"
        case .note:           return "note.text"
        case .ghostAppliance: return "cube.transparent.fill"
        case .measurement:    return "ruler.fill"
        }
    }

    private var chipBackground: Color {
        item.needsReview
            ? Color.orange.opacity(0.55)
            : Color.white.opacity(0.20)
    }
}

// MARK: - V2RecentItemDetailSheet

/// A compact sheet shown when the user taps an evidence strip item.
/// Displays the item details and provides a delete action.
struct V2RecentItemDetailSheet: View {
    let item: RecentCaptureItemV1
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: iconName)
                        .font(.title2)
                        .foregroundStyle(item.needsReview ? .orange : .accentColor)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.headline)
                        if let subtitle = item.subtitle {
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if item.needsReview {
                    Label("Needs review — room note only or placement unknown", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if let capturePointId = item.capturePointId {
                    Text("Capture point: \(capturePointId.uuidString.prefix(8))…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete \(item.title)", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
            .padding()
            .navigationTitle(evidenceTypeLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Delete \(item.title)?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    onDelete()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the item from the current capture session.")
            }
        }
    }

    private var iconName: String {
        switch item.evidenceType {
        case .objectPin:      return "mappin.circle.fill"
        case .photo:          return "photo.fill"
        case .voiceNote:      return "mic.fill"
        case .note:           return "note.text"
        case .ghostAppliance: return "cube.transparent.fill"
        case .measurement:    return "ruler.fill"
        }
    }

    private var evidenceTypeLabel: String {
        switch item.evidenceType {
        case .objectPin:      return "Object Pin"
        case .photo:          return "Photo"
        case .voiceNote:      return "Voice Note"
        case .note:           return "Note"
        case .ghostAppliance: return "Possible appliance found — needs review"
        case .measurement:    return "Measurement"
        }
    }
}
