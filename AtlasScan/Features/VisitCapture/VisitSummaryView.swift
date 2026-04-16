import SwiftUI
import AtlasContracts

// MARK: - VisitSummaryView

/// Session summary, validation, and Atlas Mind handoff screen.
///
/// Shows the complete capture state, runs validation, and provides
/// the export button that produces a `AtlasPropertyV1` payload.
struct VisitSummaryView: View {

    @ObservedObject var viewModel: VisitCaptureViewModel
    @State private var showingExport = false
    @State private var exportPayload: Data? = nil
    @State private var exportError: String? = nil
    @State private var showingFinishConfirm = false

    var body: some View {
        List {
            visitSummarySection
            captureStatsSection
            validationSection
            handoffSection
        }
        .listStyle(.insetGrouped)
        .sheet(isPresented: $showingExport) {
            if let data = exportPayload {
                exportPreviewSheet(data: data)
            }
        }
        .confirmationDialog(
            "Finish Session",
            isPresented: $showingFinishConfirm,
            titleVisibility: .visible
        ) {
            Button("Mark as Complete") {
                viewModel.completeSession()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will mark the session as complete and ready for handoff.")
        }
    }

    // MARK: - Visit summary header

    private var visitSummarySection: some View {
        Section("Visit") {
            LabeledContent("Reference", value: viewModel.session.jobReference)
            LabeledContent("Property", value: viewModel.session.propertyAddress)
            if !viewModel.session.engineerName.isEmpty {
                LabeledContent("Engineer", value: viewModel.session.engineerName)
            }
            LabeledContent("Status", value: viewModel.session.scanState.displayName)
            LabeledContent("Started", value: viewModel.session.createdAt.formatted(date: .abbreviated, time: .shortened))
            LabeledContent("Updated", value: viewModel.session.updatedAt.formatted(date: .abbreviated, time: .shortened))
        }
    }

    // MARK: - Capture stats

    private var captureStatsSection: some View {
        let scannedRooms = viewModel.session.rooms.filter(\.geometryCaptured).count
        let transcripts = viewModel.session.allVoiceNotes.filter { $0.transcript != nil }.count

        return Section("Capture Summary") {
            statsRow(title: "Rooms", value: "\(viewModel.session.rooms.count)", detail: "\(scannedRooms) LiDAR-scanned", symbol: "square.split.2x1")
            statsRow(title: "Objects", value: "\(viewModel.session.totalTaggedObjects)", symbol: "tag")
            statsRow(title: "Photos", value: "\(viewModel.session.totalPhotos)", symbol: "camera")
            statsRow(title: "Voice Notes", value: "\(viewModel.session.totalVoiceNotes)", symbol: "mic")
            statsRow(title: "Transcripts", value: "\(transcripts) / \(viewModel.session.totalVoiceNotes)", symbol: "text.bubble")
        }
    }

    private func statsRow(title: String, value: String, detail: String? = nil, symbol: String) -> some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(value).bold().monospacedDigit()
                if let detail {
                    Text(detail).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Validation

    private var validationSection: some View {
        let result = viewModel.validationResult

        return Section("Validation") {
            if result.isReadyForHandoff {
                Label(
                    result.isFullyClean ? "Ready for Atlas Mind" : "Ready (with warnings)",
                    systemImage: result.isFullyClean ? "checkmark.seal.fill" : "checkmark.seal"
                )
                .foregroundStyle(result.isFullyClean ? .green : .orange)
                .fontWeight(.semibold)
            } else {
                Label("Not ready — blocking issues exist", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .fontWeight(.semibold)
            }

            ForEach(result.blockingIssues, id: \.self) { issue in
                issueRow(issue, isBlocking: true)
            }

            ForEach(result.warnings, id: \.self) { warning in
                issueRow(warning, isBlocking: false)
            }
        }
    }

    private func issueRow(_ text: String, isBlocking: Bool) -> some View {
        Label(text, systemImage: isBlocking ? "xmark.circle" : "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(isBlocking ? .red : .orange)
    }

    // MARK: - Handoff

    private var handoffSection: some View {
        let result = viewModel.validationResult

        return Section("Handoff") {
            if viewModel.session.handoffState != .notSent {
                handoffStateBanner
            }

            Button {
                prepareExport()
            } label: {
                Label("Export to Atlas Mind", systemImage: "arrow.up.circle.fill")
                    .font(.body.bold())
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!result.isReadyForHandoff)
            .listRowBackground(Color.clear)

            if viewModel.session.scanState != .completed {
                Button {
                    showingFinishConfirm = true
                } label: {
                    Label("Mark Session Complete", systemImage: "checkmark.circle")
                }
            }

            if let errorMessage = exportError {
                Label(errorMessage, systemImage: "xmark.circle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var handoffStateBanner: some View {
        HStack {
            Image(systemName: viewModel.session.handoffState.symbolName)
            Text(viewModel.session.handoffState.displayName)
                .font(.caption.bold())
        }
        .foregroundStyle(handoffStateColor)
    }

    private var handoffStateColor: Color {
        switch viewModel.session.handoffState {
        case .notSent:  return .secondary
        case .sent:     return .blue
        case .exported: return .green
        }
    }

    // MARK: - Export

    private func prepareExport() {
        exportError = nil
        do {
            let property = VisitSessionMapper.toAtlasPropertyV1(viewModel.session)
            let data = try VisitSessionMapper.encode(property)
            exportPayload = data
            showingExport = true
        } catch {
            exportError = "Export failed: \(error.localizedDescription)"
        }
    }

    @ViewBuilder
    private func exportPreviewSheet(data: Data) -> some View {
        NavigationStack {
            JSONInspectorView(
                json: String(data: data, encoding: .utf8) ?? "(empty)"
            )
            .navigationTitle("Export Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        showingExport = false
                        exportPayload = nil
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: data, preview: SharePreview("atlas_property_\(viewModel.session.safeFileNameReference).json"))
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    let store = ScanSessionStore()
    var session = PropertyScanSession(jobReference: "JOB-001", propertyAddress: "12 Test Lane")
    session.addRoom(ScannedRoom(jobID: session.id, name: "Kitchen", geometryCaptured: true))
    let vm = VisitCaptureViewModel(session: session, sessionStore: store, atlasSync: AtlasSync())
    return VisitSummaryView(viewModel: vm)
}
#endif
