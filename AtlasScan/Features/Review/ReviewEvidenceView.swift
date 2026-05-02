import SwiftUI

// MARK: - ReviewEvidenceView
//
// Engineer confirmation layer: lets the engineer review every piece of captured
// evidence before the visit can be completed.
//
// Sections:
//   - Rooms
//   - Photos
//   - Voice notes / transcripts
//   - Object pins
//   - Floor plan / 3D area assets
//
// Each row shows:
//   - Title / label
//   - Room association (if available)
//   - Provenance (manual vs LiDAR)
//   - Review status badge
//   - Confirm / Reject / Pending actions (swipe or context menu)
//
// Rules:
//   - Manual items start confirmed; LiDAR items start pending.
//   - Rejected items stay stored for audit.
//   - Pending required items block final completion.

private let transcriptPreviewLength = 40

struct ReviewEvidenceView: View {

    @ObservedObject var store: CaptureSessionStore

    var body: some View {
        List {
            reviewSummarySection
            roomsSection
            photosSection
            voiceNotesSection
            objectPinsSection
            floorPlanSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Review Evidence")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Summary section

    private var reviewSummarySection: some View {
        Section {
            HStack(spacing: 24) {
                reviewCountBadge(
                    count: store.draft.confirmedReviewCount,
                    label: "Confirmed",
                    color: .green,
                    symbol: "checkmark.circle.fill"
                )
                reviewCountBadge(
                    count: store.draft.pendingReviewCount,
                    label: "Pending",
                    color: .orange,
                    symbol: "clock.fill"
                )
                reviewCountBadge(
                    count: store.draft.rejectedReviewCount,
                    label: "Rejected",
                    color: .red,
                    symbol: "xmark.circle.fill"
                )
            }
            .padding(.vertical, 4)
        } header: {
            Text("Review Status")
        } footer: {
            Text("Confirm each piece of evidence. Rejected items remain for audit. Pending items must be resolved before completion.")
                .font(.caption2)
        }
    }

    private func reviewCountBadge(
        count: Int,
        label: String,
        color: Color,
        symbol: String
    ) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .font(.title2)
            Text("\(count)")
                .font(.title3.bold())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Rooms section

    private var roomsSection: some View {
        Section {
            if store.draft.roomScans.isEmpty {
                emptyState("No rooms captured yet", symbol: "lidar.scanner")
            } else {
                ForEach(store.draft.roomScans) { room in
                    EvidenceReviewRow(
                        title: room.roomLabel ?? "Room",
                        subtitle: room.captureSource.displayName,
                        provenanceSymbol: room.captureSource.symbolName,
                        status: room.reviewStatus
                    ) { newStatus in
                        store.updateReviewStatus(id: room.id, status: newStatus)
                    }
                }
            }
        } header: {
            Text("Rooms (\(store.draft.roomScans.count))")
        }
    }

    // MARK: - Photos section

    private var photosSection: some View {
        Section {
            if store.draft.photos.isEmpty {
                emptyState("No photos captured yet", symbol: "camera")
            } else {
                ForEach(store.draft.photos) { photo in
                    EvidenceReviewRow(
                        title: photo.kind.displayName,
                        subtitle: roomLabel(for: photo.roomId),
                        provenanceSymbol: photo.linkedObjectId != nil
                            ? "link" : "camera",
                        status: photo.reviewStatus
                    ) { newStatus in
                        store.updateReviewStatus(id: photo.id, status: newStatus)
                    }
                }
            }
        } header: {
            Text("Photos (\(store.draft.photos.count))")
        }
    }

    // MARK: - Voice notes section

    private var voiceNotesSection: some View {
        Section {
            if store.draft.voiceNotes.isEmpty {
                emptyState("No transcripts yet", symbol: "mic")
            } else {
                ForEach(store.draft.voiceNotes) { note in
                    EvidenceReviewRow(
                        title: noteTitle(for: note),
                        subtitle: roomLabel(for: note.roomId),
                        provenanceSymbol: "mic",
                        status: note.reviewStatus
                    ) { newStatus in
                        store.updateReviewStatus(id: note.id, status: newStatus)
                    }
                }
            }
        } header: {
            Text("Voice Notes (\(store.draft.voiceNotes.count))")
        }
    }

    // MARK: - Object pins section

    private var objectPinsSection: some View {
        Section {
            if store.draft.objectPins.isEmpty {
                emptyState("No object pins placed yet", symbol: "mappin.and.ellipse")
            } else {
                ForEach(store.draft.objectPins) { pin in
                    EvidenceReviewRow(
                        title: pin.label ?? pin.type.displayName,
                        subtitle: roomLabel(for: pin.roomId),
                        provenanceSymbol: pin.pinSource?.symbolName ?? "mappin",
                        status: pin.reviewStatus,
                        confidenceWarning: pin.pinSource == .lidar
                            ? "LiDAR-inferred — verify before confirming"
                            : nil
                    ) { newStatus in
                        store.updateReviewStatus(id: pin.id, status: newStatus)
                    }
                }
            }
        } header: {
            Text("Object Pins (\(store.draft.objectPins.count))")
        }
    }

    // MARK: - Floor plan section

    private var floorPlanSection: some View {
        Section {
            if store.draft.floorPlanSnapshots.isEmpty {
                emptyState("No pipe routes drawn yet", symbol: "map")
            } else {
                ForEach(store.draft.floorPlanSnapshots) { snapshot in
                    EvidenceReviewRow(
                        title: "Floor Plan Snapshot",
                        subtitle: roomLabel(for: snapshot.roomId),
                        provenanceSymbol: "map",
                        status: snapshot.reviewStatus
                    ) { newStatus in
                        store.updateReviewStatus(id: snapshot.id, status: newStatus)
                    }
                }
            }
        } header: {
            Text("Floor Plans (\(store.draft.floorPlanSnapshots.count))")
        }
    }

    // MARK: - Helpers

    private func emptyState(_ message: String, symbol: String) -> some View {
        Label(message, systemImage: symbol)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.vertical, 4)
    }

    private func roomLabel(for roomId: UUID?) -> String? {
        guard let roomId else { return nil }
        let match = store.draft.roomScans.first(where: { $0.id == roomId })
        return match?.roomLabel
    }

    private func noteTitle(for note: CapturedVoiceNoteDraft) -> String {
        let text = note.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return "(empty transcript)" }
        let preview = String(text.prefix(transcriptPreviewLength))
        return text.count > transcriptPreviewLength ? preview + "…" : preview
    }
}

// MARK: - EvidenceReviewRow

private struct EvidenceReviewRow: View {

    let title: String
    let subtitle: String?
    let provenanceSymbol: String
    let status: EvidenceReviewStatus
    var confidenceWarning: String?
    let onStatusChange: (EvidenceReviewStatus) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // Status indicator
            Image(systemName: status.symbolName)
                .foregroundStyle(statusColor)
                .frame(width: 22)

            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .strikethrough(status == .rejected)
                    .foregroundStyle(status == .rejected ? .secondary : .primary)

                HStack(spacing: 6) {
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Image(systemName: provenanceSymbol)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if let warning = confidenceWarning, status == .pending {
                    Text(warning)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            // Quick-action menu
            Menu {
                Button {
                    onStatusChange(.confirmed)
                } label: {
                    Label("Confirm", systemImage: "checkmark.circle")
                }
                .disabled(status == .confirmed)

                Button(role: .destructive) {
                    onStatusChange(.rejected)
                } label: {
                    Label("Reject", systemImage: "xmark.circle")
                }
                .disabled(status == .rejected)

                Button {
                    onStatusChange(.pending)
                } label: {
                    Label("Leave Pending", systemImage: "clock")
                }
                .disabled(status == .pending)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                onStatusChange(.confirmed)
            } label: {
                Label("Confirm", systemImage: "checkmark")
            }
            .tint(.green)

            Button(role: .destructive) {
                onStatusChange(.rejected)
            } label: {
                Label("Reject", systemImage: "xmark")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                onStatusChange(.pending)
            } label: {
                Label("Pending", systemImage: "clock")
            }
            .tint(.orange)
        }
    }

    private var statusColor: Color {
        switch status {
        case .confirmed: return .green
        case .rejected:  return .red
        case .pending:   return .orange
        }
    }
}

// MARK: - ObjectPinSource convenience

private extension ObjectPinSource {
    var symbolName: String {
        switch self {
        case .manual: return "hand.point.up"
        case .lidar:  return "lidar.scanner"
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    let draft: CaptureSessionDraft = {
        var d = CaptureSessionStore.newSession(visitReference: "PREVIEW-001")

        var room = CapturedRoomScanDraft()
        room.roomLabel = "Kitchen"
        room.captureSource = .lidar
        room.reviewStatus = .pending
        d.roomScans.append(room)

        var photo = CapturedPhotoDraft(localFilename: "boiler.jpg")
        photo.kind = .plant
        photo.reviewStatus = .confirmed
        d.photos.append(photo)

        var note = CapturedVoiceNoteDraft()
        note.transcript = "The boiler is in the utility cupboard near the back door."
        note.reviewStatus = .confirmed
        d.voiceNotes.append(note)

        var boilerPin = CapturedObjectPinDraft(type: .boiler)
        boilerPin.pinSource = .lidar
        boilerPin.reviewStatus = .pending
        d.objectPins.append(boilerPin)

        var manualPin = CapturedObjectPinDraft(type: .cylinder)
        manualPin.pinSource = .manual
        manualPin.reviewStatus = .confirmed
        d.objectPins.append(manualPin)

        var rejectedPin = CapturedObjectPinDraft(type: .radiator)
        rejectedPin.pinSource = .lidar
        rejectedPin.reviewStatus = .rejected
        d.objectPins.append(rejectedPin)

        return d
    }()

    NavigationStack {
        ReviewEvidenceView(
            store: CaptureSessionStore(draft: draft)
        )
    }
}
#endif
