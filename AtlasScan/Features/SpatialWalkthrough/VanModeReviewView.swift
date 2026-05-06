import SwiftUI

// MARK: - VanModeReviewView
//
// Retrospective review mode — lets the engineer (or office staff) open
// previously captured room scans in the van or office and review evidence
// without returning to site.
//
// Because each room's USDZ mesh is stored at rawScanAssetRef, engineers
// can open the 3-D file, identify measurements they missed on-site, and
// add late annotations.
//
// Feature summary:
//   • Lists all captured rooms with their scan assets and artefact counts.
//   • Tapping a room opens the floor-plan editor (2-D) and the full
//     room-level evidence panel (object pins, photos, voice notes).
//   • A "Van Mode" banner makes clear the engineer is in retrospective review.
//   • New pins, photos, or voice notes added here are stamped with
//     captureSource = .vanModeReview so Atlas Mind can distinguish on-site
//     from retrospective evidence.

struct VanModeReviewView: View {

    // MARK: - Dependencies

    @ObservedObject var store: CaptureSessionStore

    // MARK: - State

    @State private var selectedRoom: CapturedRoomScanDraft?
    @State private var showingFloorPlanFor: CapturedRoomScanDraft?

    // MARK: - Body

    var body: some View {
        List {
            vanModeBanner
            roomListSection
            sessionLevelSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Van Mode — Review")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $showingFloorPlanFor) { scan in
            FloorPlanEditorView(
                scan: scan,
                onSnapshot: { snapshot in store.addFloorPlanSnapshot(snapshot) },
                onSave: { updated in
                    store.updateRoomScan(updated)
                    showingFloorPlanFor = nil
                }
            )
        }
    }

    // MARK: - Van mode banner

    private var vanModeBanner: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "car.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Van Mode — Retrospective Review")
                        .font(.headline)
                    Text("You are reviewing captured evidence off-site. Any new annotations are marked as retrospective.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Room list

    private var roomListSection: some View {
        Section("Captured Rooms (\(store.draft.roomScans.count))") {
            if store.draft.roomScans.isEmpty {
                Text("No rooms captured in this session.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.draft.roomScans) { scan in
                    NavigationLink {
                        vanRoomDetailView(for: scan)
                    } label: {
                        vanRoomRow(scan)
                    }
                }
            }
        }
    }

    private func vanRoomRow(_ scan: CapturedRoomScanDraft) -> some View {
        HStack(spacing: 12) {
            roomThumbnail(scan)
            VStack(alignment: .leading, spacing: 3) {
                Text(scan.roomLabel ?? "Unnamed Room")
                    .font(.body)
                HStack(spacing: 6) {
                    if let w = scan.rawWidthM, let d = scan.rawDepthM {
                        Text(String(format: "%.1f×%.1f m", w, d))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    artefactBadge(for: scan)
                }
            }
            Spacer()
            if scan.rawScanAssetRef != nil {
                Image(systemName: "cube.fill")
                    .foregroundStyle(.blue)
                    .font(.caption)
            }
        }
    }

    private func roomThumbnail(_ scan: CapturedRoomScanDraft) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.accentColor.opacity(0.12))
            .frame(width: 44, height: 44)
            .overlay {
                Image(systemName: scan.captureSource == .lidar ? "lidar.scanner" : "cube.fill")
                    .foregroundStyle(Color.accentColor)
            }
    }

    private func artefactBadge(for scan: CapturedRoomScanDraft) -> some View {
        let pins   = store.draft.objectPins.filter { $0.roomId == scan.id }.count
        let photos = store.draft.photos.filter     { $0.roomId == scan.id }.count
        let notes  = store.draft.voiceNotes.filter { $0.roomId == scan.id }.count
        let total  = pins + photos + notes
        return Text("\(total) artefact(s)")
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(total > 0 ? Color.blue.opacity(0.12) : Color.secondary.opacity(0.12))
            .foregroundStyle(total > 0 ? .blue : .secondary)
            .clipShape(Capsule())
    }

    // MARK: - Room detail (van mode)

    @ViewBuilder
    private func vanRoomDetailView(for scan: CapturedRoomScanDraft) -> some View {
        List {
            scanInfoSection(scan)
            meshAssetSection(scan)
            evidenceSection(scan)
        }
        .listStyle(.insetGrouped)
        .navigationTitle(scan.roomLabel ?? "Room")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingFloorPlanFor = scan
                } label: {
                    Label("Floor Plan", systemImage: "map")
                }
            }
        }
    }

    private func scanInfoSection(_ scan: CapturedRoomScanDraft) -> some View {
        Section("Scan Info") {
            LabeledContent("Room", value: scan.roomLabel ?? "Unnamed")
            LabeledContent("Captured", value: scan.captureTimestamp.formatted(date: .abbreviated, time: .shortened))
            LabeledContent("Confidence", value: scan.confidence.displayName)
            if let w = scan.rawWidthM {
                LabeledContent("Width", value: String(format: "%.2f m", w))
            }
            if let d = scan.rawDepthM {
                LabeledContent("Depth", value: String(format: "%.2f m", d))
            }
            if let h = scan.rawHeightM {
                LabeledContent("Height", value: String(format: "%.2f m", h))
            }
        }
    }

    private func meshAssetSection(_ scan: CapturedRoomScanDraft) -> some View {
        Section("3-D Mesh Asset") {
            if let assetRef = scan.rawScanAssetRef {
                HStack(spacing: 10) {
                    Image(systemName: "cube.fill")
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("USDZ Scan File")
                            .font(.subheadline)
                        Text(assetRef)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "cube.transparent")
                        .foregroundStyle(.secondary)
                    Text("No mesh asset — room was entered manually")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func evidenceSection(_ scan: CapturedRoomScanDraft) -> some View {
        let pins   = store.draft.objectPins.filter { $0.roomId == scan.id }
        let photos = store.draft.photos.filter     { $0.roomId == scan.id }
        let notes  = store.draft.voiceNotes.filter { $0.roomId == scan.id }

        return Group {
            if !pins.isEmpty {
                Section("Object Pins (\(pins.count))") {
                    ForEach(pins) { pin in
                        Label(pin.displayLabel, systemImage: pin.type.symbolName)
                    }
                }
            }
            if !photos.isEmpty {
                Section("Photos (\(photos.count))") {
                    ForEach(photos) { photo in
                        Label(photo.localFilename, systemImage: "camera")
                            .font(.caption)
                    }
                }
            }
            if !notes.isEmpty {
                Section("Voice Notes (\(notes.count))") {
                    ForEach(notes) { note in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.transcript.isEmpty ? "No transcript yet" : note.transcript)
                                .font(.caption)
                                .foregroundStyle(note.transcript.isEmpty ? .secondary : .primary)
                            Text(note.captureStartedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            if pins.isEmpty && photos.isEmpty && notes.isEmpty {
                Section {
                    Text("No evidence recorded for this room.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Session-level section

    private var sessionLevelSection: some View {
        Section("Session Totals") {
            LabeledContent("Rooms",       value: "\(store.draft.roomScans.count)")
            LabeledContent("Object Pins", value: "\(store.draft.objectPins.count)")
            LabeledContent("Photos",      value: "\(store.draft.photos.count)")
            LabeledContent("Voice Notes", value: "\(store.draft.voiceNotes.count)")
            LabeledContent("Total Artefacts", value: "\(store.draft.totalArtefactCount)")
        }
    }
}

// MARK: - Display helpers

private extension CapturedObjectPinDraft {
    var displayLabel: String {
        if let l = label, !l.isEmpty { return l }
        return type.displayName
    }
}

private extension CapturedVoiceNoteDraft {
    var captureStartedAt: Date { startedAt }
}

// MARK: - Preview

#if DEBUG
#Preview {
    var draft = CaptureSessionStore.newSession(visitReference: "PREVIEW-VAN")
    var scan = CapturedRoomScanDraft()
    scan.roomLabel = "Kitchen"
    scan.rawWidthM = 4.2
    scan.rawDepthM = 3.8
    scan.rawHeightM = 2.4
    draft.roomScans = [scan]
    let store = CaptureSessionStore(draft: draft, persistence: .shared)
    return NavigationStack {
        VanModeReviewView(store: store)
    }
}
#endif
