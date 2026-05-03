import SwiftUI
import AtlasContracts

// MARK: - VisitHomeView
//
// Primary hub for an active visit capture session.
//
// This is the engineer's home during a visit. Every capture action
// and the exit/complete lifecycle are accessible from here.
//
// Cards:
//   Scan Rooms · Photos · Voice Notes · Floor Plan
//   Objects & Pipe Routes · Review Evidence
//
// Actions:
//   Complete Capture  — gates on readiness; shows blocking checklist if missing
//   Exit Visit        — always available; saves evidence and returns to app home
//
// Design rule: no route may trap the engineer. Every sub-screen has a
// "Back to Visit Home" path via the NavigationStack back button.

struct VisitHomeView: View {

    // MARK: Environment

    @EnvironmentObject private var visitStore: AtlasScanVisitStore

    // MARK: Callbacks

    let onExit: () -> Void

    // MARK: Capture session

    @StateObject private var captureStore: CaptureSessionStore

    // MARK: Presentation state

    @State private var showingExitConfirm      = false
    @State private var showingCompleteGate     = false
    @State private var showingCompletion       = false
    @State private var showingVoiceNote        = false
    @State private var showingPhotoCapture     = false
    @State private var showingTextNote         = false
    @State private var showingCaptureV2Debug   = false

    /// Pre-built handoff delivered to VisitCompleteView on successful completion.
    @State private var completionHandoff: ScanToMindHandoffV1?

    // MARK: Init

    init(visit: AtlasScanVisit, onExit: @escaping () -> Void) {
        self.onExit = onExit

        // Load the linked capture session draft, or fall back to a fresh one.
        let draft: CaptureSessionDraft
        if let sessionId = visit.captureSessionId,
           let existing = CaptureSessionPersistence.shared.load(id: sessionId) {
            draft = existing
        } else {
            draft = CaptureSessionStore.newSession(visitReference: visit.visitNumber ?? "")
        }
        _captureStore = StateObject(
            wrappedValue: CaptureSessionStore(draft: draft, persistence: .shared)
        )
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            List {
                visitInfoSection
                captureSectionCards
                readinessSection
                actionsSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle(visitStore.activeVisit?.visitNumber ?? "Visit")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { saveStateBadge }
            .confirmationDialog(
                "Exit this visit?",
                isPresented: $showingExitConfirm,
                titleVisibility: .visible
            ) {
                Button("Exit Visit", role: .destructive) { performExit() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your captured evidence is saved locally. You can resume this visit from the home screen.")
            }
            .sheet(isPresented: $showingCompleteGate) {
                completeGateSheet
            }
            .fullScreenCover(isPresented: $showingCompletion) {
                VisitCompleteView(handoff: completionHandoff) {
                    showingCompletion = false
                    completionHandoff = nil
                    visitStore.clearActiveVisit()
                    onExit()
                }
            }
            .sheet(isPresented: $showingPhotoCapture) {
                PhotoCaptureSheet(store: captureStore)
            }
            .sheet(isPresented: $showingVoiceNote) {
                CaptureVoiceNoteRecorderSheet(
                    roomScans: captureStore.draft.roomScans
                ) { note in
                    captureStore.addVoiceNote(note)
                    showingVoiceNote = false
                }
            }
            .sheet(isPresented: $showingTextNote) {
                TextNoteSheet(store: captureStore)
            }
            .sheet(isPresented: $showingCaptureV2Debug) {
                if let visit = visitStore.activeVisit {
                    SessionCaptureV2DebugView(visit: visit, draft: captureStore.draft)
                }
            }
        }
        .onAppear { syncReadiness() }
        .onReceive(
            captureStore.$draft.debounce(for: .milliseconds(800), scheduler: DispatchQueue.main)
        ) { _ in rebuildAndPersistCapture() }
    }

    // MARK: - Visit info section

    private var visitInfoSection: some View {
        Section {
            LabeledContent("Reference") {
                Text(captureStore.draft.visitReference.isEmpty
                     ? "–"
                     : captureStore.draft.visitReference)
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Status") {
                Text(visitStore.activeVisit?.status.displayName ?? "–")
                    .foregroundStyle(statusColor)
            }
            LabeledContent("Started") {
                Text(captureStore.draft.capturedAt, style: .date)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Visit")
        }
    }

    private var statusColor: Color {
        switch visitStore.activeVisit?.status {
        case .capturing:       return .blue
        case .readyToComplete: return .green
        case .complete:        return .secondary
        default:               return .orange
        }
    }

    // MARK: - Capture section cards

    private var captureSectionCards: some View {
        Section {
            NavigationLink {
                RoomScanListView(store: captureStore)
            } label: {
                captureRow("Scan Rooms", symbol: "lidar.scanner",
                           badge: captureStore.draft.roomScans.count)
            }

            Button { showingPhotoCapture = true } label: {
                captureRow("Photos", symbol: "camera",
                           badge: captureStore.draft.photos.count)
            }

            Button { showingVoiceNote = true } label: {
                captureRow("Voice Notes", symbol: "mic.badge.plus",
                           badge: captureStore.draft.voiceNotes.count)
            }

            NavigationLink {
                FloorPlanReviewView(store: captureStore)
            } label: {
                captureRow("Floor Plan", symbol: "map",
                           badge: captureStore.draft.floorPlanSnapshots.count)
            }

            NavigationLink {
                ObjectPinListView(store: captureStore)
            } label: {
                captureRow("Objects & Pipe Routes", symbol: "mappin.and.ellipse",
                           badge: captureStore.draft.objectPins.count)
            }

            NavigationLink {
                FabricCaptureView(store: captureStore)
            } label: {
                captureRow("Fabric & Perimeter", symbol: "square.3.layers.3d",
                           badge: captureStore.draft.fabricRecords.reduce(0) { $0 + $1.boundaries.count + $1.openings.count })
            }

            NavigationLink {
                HazardCaptureView(store: captureStore)
            } label: {
                captureRow("Hazard Observations", symbol: "exclamationmark.triangle",
                           badge: captureStore.draft.hazardObservations.count)
            }

            NavigationLink {
                ReviewEvidenceView(store: captureStore)
            } label: {
                reviewEvidenceRow
            }
        } header: {
            Text("Capture Evidence")
        }
    }

    private func captureRow(_ title: String, symbol: String, badge: Int) -> some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            if badge > 0 {
                Text("\(badge)")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(Capsule())
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Review Evidence card row with confirmed / pending / rejected counts.
    private var reviewEvidenceRow: some View {
        HStack(spacing: 8) {
            Label("Review Evidence", systemImage: "checklist")
            Spacer()
            let pending   = captureStore.draft.pendingReviewCount
            let rejected  = captureStore.draft.rejectedReviewCount
            let confirmed = captureStore.draft.confirmedReviewCount
            if pending > 0 {
                reviewBadge("\(pending)", color: .orange)
            }
            if rejected > 0 {
                reviewBadge("\(rejected)", color: .red)
            }
            if confirmed > 0 {
                reviewBadge("\(confirmed)", color: .green)
            }
        }
    }

    private func reviewBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    // MARK: - Readiness section

    private var readinessSection: some View {
        Section {
            VisitReadinessPanel(readiness: currentReadiness)
        } header: {
            Text("Readiness")
        }
    }

    // MARK: - Actions section

    private var actionsSection: some View {
        Section {
            Button {
                handleCompleteTapped()
            } label: {
                Label("Complete Capture", systemImage: "checkmark.circle.fill")
                    .fontWeight(.semibold)
                    .foregroundStyle(allComplete ? .green : .orange)
            }

            Button(role: .destructive) {
                showingExitConfirm = true
            } label: {
                Label("Exit Visit", systemImage: "xmark.circle")
            }
        } header: {
            Text("Actions")
        } footer: {
            if !allComplete {
                Text("Some required evidence is still missing. Tap Complete Capture to see what's needed.")
                    .font(.caption2)
            }
        }
    }

    // MARK: - Complete gate sheet

    private var completeGateSheet: some View {
        NavigationStack {
            List {
                Section {
                    VisitReadinessPanel(readiness: currentReadiness)
                } header: {
                    Text("Missing Required Evidence")
                } footer: {
                    Text("All seven items must be completed before the visit can be marked as done.")
                }

                if captureStore.draft.pendingReviewCount > 0 {
                    Section {
                        NavigationLink {
                            ReviewEvidenceView(store: captureStore)
                        } label: {
                            Label(
                                "\(captureStore.draft.pendingReviewCount) item(s) awaiting review",
                                systemImage: "clock.fill"
                            )
                            .foregroundStyle(.orange)
                        }
                    } header: {
                        Text("Pending Review")
                    } footer: {
                        Text("Review and confirm or reject these items to progress toward completion.")
                            .font(.caption2)
                    }
                }

                if DeveloperModeStore.shared.isEnabled {
                    Section {
                        Button {
                            showingCompleteGate = false
                            showingCaptureV2Debug = true
                        } label: {
                            Label("View SessionCaptureV2", systemImage: "doc.text.magnifyingglass")
                                .foregroundStyle(.orange)
                        }
                    } header: {
                        Text("Developer Tools")
                    } footer: {
                        Text("Inspect the current capture payload. Not visible to customers.")
                            .font(.caption2)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Not Ready to Complete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showingCompleteGate = false }
                }
                if DeveloperModeStore.shared.isEnabled {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Developer: mark ready for handoff") {
                            showingCompleteGate = false
                            forceComplete()
                        }
                        .tint(.orange)
                    }
                }
            }
        }
    }

    // MARK: - Save state toolbar badge

    @ToolbarContentBuilder
    private var saveStateBadge: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            switch captureStore.saveState {
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
    }

    // MARK: - Computed readiness

    /// Live readiness derived from the current capture session.
    private var currentReadiness: VisitReadinessV1 {
        AtlasScanVisit.deriveReadiness(from: captureStore.draft)
    }

    /// True when the completion validator says all 7 flags pass.
    private var allComplete: Bool {
        validateVisitForCompletion(readiness: currentReadiness).isCompletable
    }

    // MARK: - Actions

    private func syncReadiness() {
        visitStore.updateReadiness(currentReadiness)
    }

    private func handleCompleteTapped() {
        let result = validateVisitForCompletion(readiness: currentReadiness)
        if result.isCompletable {
            visitStore.updateStatus(.readyToComplete)
            visitStore.updateStatus(.complete)
            completionHandoff = buildCompletionHandoff(reason: .completedCapture)
            showingCompletion = true
        } else {
            showingCompleteGate = true
        }
    }

    private func forceComplete() {
        visitStore.updateStatus(.complete)
        completionHandoff = buildCompletionHandoff(reason: .reviewInMind)
        showingCompletion = true
    }

    /// Builds a ``ScanToMindHandoffV1`` from the active visit and its current capture.
    ///
    /// Returns nil when the active visit is missing or the handoff cannot be assembled
    /// (e.g. visit ID / session ID mismatch).  In that case Mind is opened without a
    /// preloaded payload — the engineer is never blocked by a handoff build failure.
    private func buildCompletionHandoff(reason: ScanToMindHandoffReasonV1) -> ScanToMindHandoffV1? {
        guard let visit = visitStore.activeVisit else { return nil }
        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(
            visit: visit,
            draft: captureStore.draft
        )
        do {
            return try ScanToMindHandoffBuilder.buildHandoff(
                visit: visit,
                capture: capture,
                reason: reason
            )
        } catch {
            print("[VisitHomeView] Failed to build ScanToMind handoff: \(error.localizedDescription)")
            return nil
        }
    }

    private func performExit() {
        captureStore.saveNow()
        visitStore.clearActiveVisit()
        onExit()
    }

    /// Rebuilds SessionCaptureV2 from current draft and persists it alongside the visit.
    ///
    /// Called whenever the capture draft changes so the persisted payload stays current.
    private func rebuildAndPersistCapture() {
        guard let visit = visitStore.activeVisit else { return }
        let capture = SessionCaptureV2Builder.buildSessionCaptureV2(
            visit: visit,
            draft: captureStore.draft
        )
        SessionCaptureV2Store.shared.saveCapture(capture, for: visit.visitId)
        visitStore.updateReadiness(currentReadiness)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    let store = AtlasScanVisitStore.makeTestInstance()
    let visit = store.createVisit(visitNumber: "PREVIEW-001", brandId: nil)
    return VisitHomeView(visit: visit, onExit: {})
        .environmentObject(store)
}
#endif
