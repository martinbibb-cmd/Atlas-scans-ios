import SwiftUI
import AtlasContracts

// MARK: - ReviewExportView
//
// Visit summary and export screen.
//
// Shows capture completeness, capture-only warnings, and provides
// the export button that produces a SessionCaptureV2 payload.
//
// Rules:
//   • No recommendation language.
//   • No simulated outputs.
//   • Warnings are capture-layer only (no artefacts, untranscribed notes, etc.)

struct ReviewExportView: View {

    @ObservedObject var store: CaptureSessionStore

    @State private var showingExport = false
    @State private var exportResult: CaptureExportResult?
    @State private var exportError: String?
    @State private var showingExportConfirm = false

    @State private var showingWorkspaceExport = false
    @State private var workspacePackageURL: URL?
    @State private var showingWorkspaceExportConfirm = false

    var body: some View {
        List {
            visitSummarySection
            captureCountsSection
            warningsSection
            exportSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Review & Export")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingExport) {
            if let result = exportResult {
                exportPreviewSheet(result: result)
            }
        }
        .sheet(isPresented: $showingWorkspaceExport) {
            if let url = workspacePackageURL {
                ShareSheet(items: [url])
            }
        }
        .confirmationDialog(
            "Export to Atlas Mind?",
            isPresented: $showingExportConfirm,
            titleVisibility: .visible
        ) {
            Button("Export Now") { performExport() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will package the session capture and mark it as exported.")
        }
        .confirmationDialog(
            "Open in Atlas Mind?",
            isPresented: $showingWorkspaceExportConfirm,
            titleVisibility: .visible
        ) {
            Button("Build Package") { performWorkspaceExport() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will assemble a .atlasvisit package with the session capture, photos, and floor plans.")
        }
    }

    // MARK: - Visit summary

    private var visitSummarySection: some View {
        Section("Visit") {
            LabeledContent("Reference", value: store.draft.visitReference.isEmpty ? "—" : store.draft.visitReference)
            LabeledContent("Started", value: store.draft.capturedAt.formatted(date: .abbreviated, time: .shortened))
            LabeledContent("Updated", value: store.draft.updatedAt.formatted(date: .abbreviated, time: .shortened))
            LabeledContent("Status", value: store.draft.exportState.displayName)
        }
    }

    // MARK: - Capture counts

    private var captureCountsSection: some View {
        Section("Capture Summary") {
            countRow(title: "Room Scans", count: store.draft.roomScans.count, symbol: "lidar.scanner")
            countRow(title: "Photos", count: store.draft.photos.count, symbol: "camera")
            countRow(title: "Voice Notes", count: store.draft.voiceNotes.count, symbol: "mic",
                     detail: transcriptDetail)
            countRow(title: "Objects & Pins", count: store.draft.objectPins.count, symbol: "mappin.and.ellipse")
            countRow(title: "Floor Plan Snapshots", count: store.draft.floorPlanSnapshots.count, symbol: "map")
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

    private func countRow(title: String, count: Int, symbol: String, detail: String? = nil) -> some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(count)")
                    .font(.body.monospacedDigit().bold())
                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Warnings

    private var warningsSection: some View {
        let errors = CaptureSessionExporter.validate(store.draft)
        let captureWarnings = buildCaptureWarnings()

        return Section("Readiness") {
            if errors.isEmpty && captureWarnings.isEmpty {
                Label("Ready for export", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .fontWeight(.semibold)
            } else {
                if !errors.isEmpty {
                    Label("Not ready — blocking issues exist", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .fontWeight(.semibold)
                    ForEach(errors, id: \.errorDescription) { error in
                        issueRow(error.localizedDescription, isBlocking: true)
                    }
                } else {
                    Label("Ready (with warnings)", systemImage: "checkmark.seal")
                        .foregroundStyle(.orange)
                        .fontWeight(.semibold)
                }
                ForEach(captureWarnings, id: \.self) { warning in
                    issueRow(warning, isBlocking: false)
                }
            }
        }
    }

    private func buildCaptureWarnings() -> [String] {
        var warnings: [String] = []

        if store.draft.roomScans.isEmpty {
            warnings.append("No room scans captured yet.")
        }
        if store.draft.photos.isEmpty {
            warnings.append("No evidence photos captured.")
        }
        let untranscribed = store.draft.voiceNotes.filter {
            $0.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
        if untranscribed > 0 {
            warnings.append("\(untranscribed) voice note(s) have no transcript.")
        }
        let unlabelledNotes = store.draft.objectPins.filter {
            $0.type == .genericNote && ($0.label ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        }.count
        if unlabelledNotes > 0 {
            warnings.append("\(unlabelledNotes) note pin(s) have no label.")
        }

        return warnings
    }

    private func issueRow(_ text: String, isBlocking: Bool) -> some View {
        Label(text, systemImage: isBlocking ? "xmark.circle" : "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(isBlocking ? .red : .orange)
    }

    // MARK: - Export

    private var exportSection: some View {
        let errors = CaptureSessionExporter.validate(store.draft)
        let isReady = errors.isEmpty

        return Section("Export") {
            if store.draft.exportState == .exported {
                exportedBanner
            }

            Button {
                showingExportConfirm = true
            } label: {
                Label("Export to Atlas Mind", systemImage: "arrow.up.circle.fill")
                    .font(.body.bold())
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isReady || store.draft.exportState == .exported)
            .listRowBackground(Color.clear)

            Button {
                showingWorkspaceExportConfirm = true
            } label: {
                Label("Open in Atlas Mind", systemImage: "square.and.arrow.up")
                    .font(.body.bold())
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!isReady)
            .listRowBackground(Color.clear)

            if let errorMessage = exportError {
                Label(errorMessage, systemImage: "xmark.circle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var exportedBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
            Text("Session exported")
                .font(.caption.bold())
                .foregroundStyle(.green)
        }
    }

    // MARK: - Actions

    private func performExport() {
        exportError = nil
        do {
            let result = try CaptureSessionExporter.export(store.draft)
            exportResult = result
            store.markExported()
            showingExport = true
        } catch {
            exportError = "Export failed: \(error.localizedDescription)"
            store.markExportFailed()
        }
    }

    private func performWorkspaceExport() {
        exportError = nil
        do {
            let result = try CaptureSessionExporter.export(store.draft)
            let package = try WorkspaceExporter.exportPackage(store.draft, jsonData: result.jsonData)
            workspacePackageURL = package.packageURL
            store.markExported()
            showingWorkspaceExport = true
        } catch {
            exportError = "Workspace export failed: \(error.localizedDescription)"
            store.markExportFailed()
        }
    }

    // MARK: - Export preview sheet

    @ViewBuilder
    private func exportPreviewSheet(result: CaptureExportResult) -> some View {
        NavigationStack {
            ScrollView {
                Text(String(data: result.jsonData, encoding: .utf8) ?? "(empty)")
                    .font(.system(.caption, design: .monospaced))
                    .padding()
            }
            .navigationTitle("Export Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        showingExport = false
                        exportResult = nil
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    let jsonString = String(data: result.jsonData, encoding: .utf8) ?? ""
                    ShareLink(
                        item: jsonString,
                        subject: Text("Atlas Capture Export"),
                        message: Text("atlas_capture_\(store.draft.visitReference).json")
                    )
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    var draft = CaptureSessionDraft()
    draft.visitReference = "JOB-2025-0001"
    var scan = CapturedRoomScanDraft()
    scan.roomLabel = "Kitchen"
    draft.roomScans = [scan]
    draft.photos = [CapturedPhotoDraft(localFilename: "p1.jpg")]
    var note = CapturedVoiceNoteDraft()
    note.transcript = "Boiler in utility room."
    draft.voiceNotes = [note]
    let store = CaptureSessionStore(draft: draft)
    return NavigationStack {
        ReviewExportView(store: store)
    }
}
#endif
