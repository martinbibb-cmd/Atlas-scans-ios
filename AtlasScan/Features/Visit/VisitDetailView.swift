import SwiftUI
import PhotosUI

// MARK: - VisitDetailView
//
// Main capture container for a single visit session.
//
// The engineer can:
//   • Add photos via the system photo picker
//   • Add free-text notes
//   • Review all captured evidence
//   • End / exit the visit at any time
//
// Design rule: the "End Visit" action is always visible in the toolbar.
// No route may trap the user.

struct VisitDetailView: View {

    let initialDraft: CaptureSessionDraft
    let onClose: () -> Void

    @StateObject private var store: CaptureSessionStore

    @State private var showingPhotoCapture  = false
    @State private var showingTextNote      = false
    @State private var showingReview        = false
    @State private var showingExitConfirm   = false

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
        .sheet(isPresented: $showingReview) {
            VisitReviewView(store: store, onDone: { showingReview = false })
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
            Button("Review") {
                showingReview = true
            }
            .fontWeight(.semibold)
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
            if store.draft.photos.isEmpty && store.draft.voiceNotes.isEmpty {
                Text("No evidence captured yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                if !store.draft.photos.isEmpty {
                    LabeledContent("Photos") {
                        Text("\(store.draft.photos.count)")
                            .foregroundStyle(.secondary)
                    }
                }
                if !store.draft.voiceNotes.isEmpty {
                    LabeledContent("Notes") {
                        Text("\(store.draft.voiceNotes.count)")
                            .foregroundStyle(.secondary)
                    }
                }
                Button("Review All Evidence →") {
                    showingReview = true
                }
                .font(.subheadline)
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
