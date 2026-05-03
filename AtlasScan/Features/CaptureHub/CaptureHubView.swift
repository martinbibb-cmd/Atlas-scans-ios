import SwiftUI

// MARK: - CaptureHubDestination

enum CaptureHubDestination: Hashable {
    case roomScans
    case photos
    case voiceNotes
    case objectPins
    case quotePlannerAnchors
    case reviewExport
}

// MARK: - CaptureHubView
//
// The single home screen for a visit capture session.
//
// After entering a visit number, the engineer lands here.
// Everything for this visit lives on this screen.
//
// "One visit, one session, one home screen."
//
// Each section card shows the current capture count and status,
// and navigates to the dedicated capture screen for that section.

struct CaptureHubView: View {

    @ObservedObject var store: CaptureSessionStore
    @State private var destination: CaptureHubDestination?
    @State private var showNewJob = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    visitHeader
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 12)

                    sectionsStack
                        .padding(.horizontal, 16)

                    exportBadge
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 24)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Capture Hub")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .navigationDestination(item: $destination) { dest in
                destinationView(for: dest)
            }
        }
    }

    // MARK: - Visit header

    private var visitHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(store.draft.visitReference.isEmpty ? "No Reference" : store.draft.visitReference)
                    .font(.title2.bold())
                Text(store.draft.capturedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            exportStateBadge
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var exportStateBadge: some View {
        Text(store.draft.exportState.displayName)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(exportStateBadgeColor.opacity(0.15))
            .foregroundStyle(exportStateBadgeColor)
            .clipShape(Capsule())
    }

    private var exportStateBadgeColor: Color {
        switch store.draft.exportState {
        case .draft:          return .orange
        case .readyForExport: return .blue
        case .exported:       return .green
        case .exportFailed:   return .red
        }
    }

    // MARK: - Section cards

    private var sectionsStack: some View {
        VStack(spacing: 10) {
            CaptureHubSectionCard(
                title: "Room Scans",
                subtitle: "LiDAR capture of each room",
                symbolName: "lidar.scanner",
                status: roomScanStatus,
                actionLabel: store.draft.roomScans.isEmpty ? "Start Scan" : "View Scans"
            ) { destination = .roomScans }

            CaptureHubSectionCard(
                title: "Photos",
                subtitle: "Evidence photos for rooms and objects",
                symbolName: "camera",
                status: photoStatus,
                actionLabel: store.draft.photos.isEmpty ? "Capture Photo" : "View Photos"
            ) { destination = .photos }

            CaptureHubSectionCard(
                title: "Voice Notes",
                subtitle: "Observations and site notes",
                symbolName: "mic",
                status: voiceNoteStatus,
                actionLabel: store.draft.voiceNotes.isEmpty ? "Record Note" : "View Notes"
            ) { destination = .voiceNotes }

            CaptureHubSectionCard(
                title: "Objects & Pins",
                subtitle: "Tag boilers, radiators, and other items",
                symbolName: "mappin.and.ellipse",
                status: objectPinStatus,
                actionLabel: store.draft.objectPins.isEmpty ? "Add Object" : "View Objects"
            ) { destination = .objectPins }

            CaptureHubSectionCard(
                title: "Quote Points",
                subtitle: "Candidate install and service locations",
                symbolName: "mappin.circle",
                status: quotePlannerStatus,
                actionLabel: store.draft.quotePlannerAnchors.isEmpty ? "Add Quote Point" : "View Quote Points"
            ) { destination = .quotePlannerAnchors }

            CaptureHubSectionCard(
                title: "Review & Export",
                subtitle: "Check completeness and send to Atlas Mind",
                symbolName: "checklist",
                status: reviewExportStatus,
                actionLabel: "Review"
            ) { destination = .reviewExport }
        }
    }

    // MARK: - Section statuses

    private var roomScanStatus: CaptureHubSectionStatus {
        let count = store.draft.roomScans.count
        if count == 0 { return .notStarted }
        return .inProgress(count: count)
    }

    private var photoStatus: CaptureHubSectionStatus {
        let count = store.draft.photos.count
        if count == 0 { return .notStarted }
        return .inProgress(count: count)
    }

    private var voiceNoteStatus: CaptureHubSectionStatus {
        let notes = store.draft.voiceNotes
        if notes.isEmpty { return .notStarted }
        let untranscribed = notes.filter { $0.transcript.trimmingCharacters(in: .whitespaces).isEmpty }.count
        if untranscribed > 0 {
            return .needsAttention(message: "\(untranscribed) awaiting transcript")
        }
        return .ready(count: notes.count)
    }

    private var objectPinStatus: CaptureHubSectionStatus {
        let count = store.draft.objectPins.count
        if count == 0 { return .notStarted }
        return .inProgress(count: count)
    }

    private var quotePlannerStatus: CaptureHubSectionStatus {
        let count = store.draft.quotePlannerAnchors.count
        if count == 0 { return .notStarted }
        return .inProgress(count: count)
    }

    private var reviewExportStatus: CaptureHubSectionStatus {
        let errors = CaptureSessionExporter.validate(store.draft)
        if errors.isEmpty {
            return .ready(count: store.draft.totalArtefactCount)
        }
        return .needsAttention(message: "\(errors.count) issue(s)")
    }

    // MARK: - Export badge

    @ViewBuilder
    private var exportBadge: some View {
        if store.draft.exportState == .exported {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Text("Session exported to Atlas Mind")
                    .font(.caption.bold())
                    .foregroundStyle(.green)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.green.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            VStack(spacing: 1) {
                Text("Capture Hub")
                    .font(.headline)
                saveStateBadge
            }
        }
    }

    @ViewBuilder
    private var saveStateBadge: some View {
        switch store.saveState {
        case .unsaved:
            Text("Unsaved")
                .font(.caption2)
                .foregroundStyle(.orange)
        case .saving:
            Text("Saving…")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .saved:
            EmptyView()
        }
    }

    // MARK: - Destinations

    @ViewBuilder
    private func destinationView(for destination: CaptureHubDestination) -> some View {
        switch destination {
        case .roomScans:
            RoomScanListView(store: store)
        case .photos:
            PhotoListView(store: store)
        case .voiceNotes:
            VoiceNotesView(store: store)
        case .objectPins:
            ObjectPinListView(store: store)
        case .quotePlannerAnchors:
            QuotePlannerCaptureView(store: store)
        case .reviewExport:
            ReviewExportView(store: store)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    let persistence = CaptureSessionPersistence.shared
    var draft = CaptureSessionDraft()
    draft.visitReference = "JOB-2025-0001"
    draft.roomScans = [
        CapturedRoomScanDraft(roomLabel: "Kitchen")
    ]
    draft.photos = [
        CapturedPhotoDraft(localFilename: "photo1.jpg"),
        CapturedPhotoDraft(localFilename: "photo2.jpg")
    ]
    let store = CaptureSessionStore(draft: draft, persistence: persistence)
    return CaptureHubView(store: store)
}
#endif
