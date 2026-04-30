import SwiftUI
import PhotosUI

// MARK: - VisitDetailView
//
// Main capture container for a single visit session.
//
// The engineer can:
//   • Scan rooms / areas via the room scan flow
//   • Place typed object pins (boiler, radiator, etc.)
//   • Review and annotate floor plans
//   • Record voice notes (transcript-only export)
//   • Add photos via the system photo picker
//   • Add free-text notes
//   • Review all captured evidence and export
//   • End / exit the visit at any time
//
// Design rule: the "End Visit" action is always visible in the toolbar.
// No route may trap the user.

struct VisitDetailView: View {

    let initialDraft: CaptureSessionDraft
    let onClose: () -> Void

    @StateObject private var store: CaptureSessionStore

    @State private var showingPhotoCapture         = false
    @State private var showingTextNote             = false
    @State private var showingObjectPinPlacement   = false
    @State private var showingVoiceNoteRecorder    = false
    @State private var showingExitConfirm          = false

    // MARK: Init

    init(initialDraft: CaptureSessionDraft, onClose: @escaping () -> Void) {
        self.initialDraft = initialDraft
        self.onClose = onClose
        _store = StateObject(
            wrappedValue: CaptureSessionStore(draft: initialDraft, persistence: .shared)
        )
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            List {
                visitInfoSection
                captureSection
                evidenceSummarySection
            }
            .listStyle(.insetGrouped)
            .navigationTitle(store.draft.visitReference.isEmpty ? "Visit" : store.draft.visitReference)
            .navigationBarTitleDisplayMode(.large)
            .toolbar { toolbarItems }
            .confirmationDialog(
                "End this visit?",
                isPresented: $showingExitConfirm,
                titleVisibility: .visible
            ) {
                Button("End Visit", role: .destructive) { onClose() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your captured evidence is saved locally. You can reopen this visit from Saved Visits.")
            }
        }
        .sheet(isPresented: $showingPhotoCapture) {
            PhotoCaptureSheet(store: store)
        }
        .sheet(isPresented: $showingTextNote) {
            TextNoteSheet(store: store)
        }
        .sheet(isPresented: $showingObjectPinPlacement) {
            ObjectPinPlacementView(
                roomScans: store.draft.roomScans,
                photos: store.draft.photos
            ) { pin in
                store.addObjectPin(pin)
                showingObjectPinPlacement = false
            }
        }
        .sheet(isPresented: $showingVoiceNoteRecorder) {
            CaptureVoiceNoteRecorderSheet(
                roomScans: store.draft.roomScans
            ) { note in
                store.addVoiceNote(note)
                showingVoiceNoteRecorder = false
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button {
                showingExitConfirm = true
            } label: {
                Label("End Visit", systemImage: "xmark")
                    .labelStyle(.iconOnly)
            }
            .tint(.red)
        }
        ToolbarItem(placement: .confirmationAction) {
            NavigationLink {
                ReviewExportView(store: store)
            } label: {
                Text("Review")
                    .fontWeight(.semibold)
            }
        }
    }

    // MARK: - Visit info section

    private var visitInfoSection: some View {
        Section("Visit") {
            LabeledContent("Reference") {
                Text(store.draft.visitReference.isEmpty ? "–" : store.draft.visitReference)
                    .foregroundStyle(.secondary)
            }
            if !store.draft.propertyAddress.isEmpty {
                LabeledContent("Address") {
                    Text(store.draft.propertyAddress)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
            LabeledContent("Started") {
                Text(store.draft.capturedAt, style: .date)
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Status") {
                Text(store.draft.exportState.displayName)
                    .foregroundStyle(exportStateColor)
            }
        }
    }

    private var exportStateColor: Color {
        switch store.draft.exportState {
        case .draft:          return .orange
        case .readyForExport: return .green
        case .exported:       return .secondary
        case .exportFailed:   return .red
        }
    }

    // MARK: - Capture section

    private var captureSection: some View {
        Section("Capture Evidence") {
            NavigationLink {
                RoomScanListView(store: store)
            } label: {
                Label("Scan Room / Area", systemImage: "cube.transparent")
            }
            Button {
                showingObjectPinPlacement = true
            } label: {
                Label("Place Object", systemImage: "mappin.circle")
            }
            NavigationLink {
                FloorPlanReviewView(store: store)
            } label: {
                Label("Review Floor Plan", systemImage: "map")
            }
            Button {
                showingVoiceNoteRecorder = true
            } label: {
                Label("Record Voice Note", systemImage: "mic.badge.plus")
            }
            Button {
                showingPhotoCapture = true
            } label: {
                Label("Add Photo", systemImage: "camera")
            }
            Button {
                showingTextNote = true
            } label: {
                Label("Add Text Note", systemImage: "note.text.badge.plus")
            }
        }
    }

    // MARK: - Evidence summary section

    private var evidenceSummarySection: some View {
        Section("Evidence") {
            NavigationLink {
                RoomScanListView(store: store)
            } label: {
                evidenceRow(
                    title: "Room Scans",
                    symbol: "cube.transparent",
                    count: store.draft.roomScans.count
                )
            }
            NavigationLink {
                PhotoListView(store: store)
            } label: {
                evidenceRow(
                    title: "Photos",
                    symbol: "camera",
                    count: store.draft.photos.count
                )
            }
            NavigationLink {
                VoiceNotesView(store: store)
            } label: {
                evidenceRow(
                    title: "Notes",
                    symbol: "mic",
                    count: store.draft.voiceNotes.count,
                    detail: transcriptDetail
                )
            }
            NavigationLink {
                ObjectPinListView(store: store)
            } label: {
                evidenceRow(
                    title: "Objects & Pins",
                    symbol: "mappin.and.ellipse",
                    count: store.draft.objectPins.count
                )
            }
            NavigationLink {
                FloorPlanReviewView(store: store)
            } label: {
                evidenceRow(
                    title: "Floor Plans",
                    symbol: "map",
                    count: store.draft.floorPlanSnapshots.count
                )
            }
        }
    }

    private var transcriptDetail: String? {
        let total = store.draft.voiceNotes.count
        guard total > 0 else { return nil }
        let transcribed = store.draft.voiceNotes.filter {
            !$0.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
        return "\(transcribed)/\(total) transcribed"
    }

    private func evidenceRow(title: String, symbol: String, count: Int, detail: String? = nil) -> some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(count)")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(count == 0 ? .tertiary : .secondary)
                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    VisitDetailView(
        initialDraft: CaptureSessionStore.newSession(visitReference: "PREVIEW-001"),
        onClose: {}
    )
}
#endif
