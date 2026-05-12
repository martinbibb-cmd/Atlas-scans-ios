import SwiftUI
import AtlasContracts

// MARK: - ReviewExportView
//
// Visit summary and export screen.
//
// Shows capture completeness, capture-only warnings, and provides
// handoff actions to continue work in Atlas Mind.
//
// Primary actions (always visible):
//   • Continue in Atlas Mind    — opens Mind WebView pre-loaded to this visit
//   • Open Quote Planner        — opens Mind at /quote-planner with evidence preloaded
//   • Save to Files / Cloud Drive — saves the .atlasvisit package to Files.app
//   • Share Capture Package     — builds .atlasvisit and opens the iOS share sheet
//
// Developer-only actions (require Developer Mode):
//   • Inspect JSON — opens the raw SessionCaptureV2 JSON inspector
//   • Copy JSON to Clipboard
//
// Rules:
//   • No recommendation language.
//   • No simulated outputs.
//   • Warnings are capture-layer only (no artefacts, untranscribed notes, etc.)

struct ReviewExportView: View {

    @ObservedObject var store: CaptureSessionStore
    @ObservedObject private var developerMode = DeveloperModeStore.shared

    // MARK: - State: Mind handoff

    @State private var showingMindHandoff         = false
    @State private var mindHandoffVisitId: String?

    // MARK: - State: quote planner handoff

    @State private var quotePlannerHandoffError: String?
    @State private var quotePlannerLinkURL: URL?
    @State private var isBuildingQuotePlanner     = false
    @State private var copiedQuotePlannerLink     = false

    // MARK: - State: workspace package

    @State private var atlasVisitURL: URL?
    @State private var workspacePackageError: String?
    @State private var isBuildingPackage          = false
    @State private var showingWorkspaceShare      = false
    @State private var showingDocumentPicker      = false

    // MARK: - State: JSON inspector (dev only)

    @State private var showingJSONInspector       = false
    @State private var exportResult: CaptureExportResult?
    @State private var jsonExportError: String?
    @State private var copiedToClipboard          = false

    var body: some View {
        List {
            visitSummarySection
            captureCountsSection
            warningsSection
            handoffSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Review & Export")
        .navigationBarTitleDisplayMode(.inline)
        // Mind WebView
        .fullScreenCover(isPresented: $showingMindHandoff) {
            MindRootView(visitId: mindHandoffVisitId) {
                showingMindHandoff = false
                mindHandoffVisitId = nil
            }
        }
        // .atlasvisit share sheet
        .sheet(isPresented: $showingWorkspaceShare) {
            if let url = atlasVisitURL {
                ShareSheet(items: [url])
            }
        }
        // Save to Files document picker
        .sheet(isPresented: $showingDocumentPicker) {
            if let url = atlasVisitURL {
                DocumentPickerSheet(urls: [url]) {
                    showingDocumentPicker = false
                }
            }
        }
        // JSON inspector (dev only)
        .sheet(isPresented: $showingJSONInspector) {
            if let result = exportResult {
                JSONInspectorView(
                    json: String(data: result.jsonData, encoding: .utf8)
                        ?? "Error: unable to decode JSON data as UTF-8."
                )
            }
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
                Label("Ready for handoff", systemImage: "checkmark.seal.fill")
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

    // MARK: - Handoff section

    private var handoffSection: some View {
        let errors = CaptureSessionExporter.validate(store.draft)
        let canBuildHandoff = errors.isEmpty
        let handoff = reviewHandoff
        let finalOutputsLocked = handoff?.requiresReview ?? false

        return Section {
            if let handoff, handoff.requiresReview {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Incomplete capture — review required", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                    if !handoff.missingEvidence.isEmpty {
                        ForEach(handoff.missingEvidence, id: \.self) { item in
                            Label(item, systemImage: "minus.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !handoff.unresolvedEvidence.isEmpty {
                        Text("\(handoff.unresolvedEvidence.count) unresolved item(s) still need review in Atlas Mind.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !handoff.geometryQAFlags.isEmpty {
                        Text("\(handoff.geometryQAFlags.count) geometry QA flag(s) still need review.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if store.draft.exportState == .exported {
                exportedBanner
            }

            // PRIMARY — Continue in Atlas Mind
            Button {
                performMindHandoff()
            } label: {
                HStack {
                    if isBuildingPackage {
                        ProgressView()
                            .padding(.trailing, 6)
                    } else {
                        Image(systemName: "brain.head.profile")
                    }
                    Text("Continue in Atlas Mind")
                        .fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canBuildHandoff || isBuildingPackage)
            .listRowBackground(Color.clear)

            // SECONDARY — Open Quote Planner in Atlas Mind
            Button {
                performQuotePlannerHandoff()
            } label: {
                HStack {
                    if isBuildingQuotePlanner {
                        ProgressView()
                            .padding(.trailing, 6)
                    } else {
                        Image(systemName: "list.clipboard")
                    }
                    Text("Open Quote Planner in Atlas Mind")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!canBuildHandoff || finalOutputsLocked || isBuildingQuotePlanner)
            .listRowBackground(Color.clear)

            // Quote planner error + fallback actions
            if let errorMessage = quotePlannerHandoffError {
                Label(errorMessage, systemImage: "xmark.circle")
                    .font(.caption)
                    .foregroundStyle(.red)

                if let url = quotePlannerLinkURL, !finalOutputsLocked {
                    quotePlannerFallbackActions(url: url)
                }
            } else if let url = quotePlannerLinkURL, !finalOutputsLocked {
                quotePlannerFallbackActions(url: url)
            }

            // Save to Files / Cloud Drive
            Button {
                buildPackageIfNeeded { showingDocumentPicker = true }
            } label: {
                Label("Save to Files / Cloud Drive", systemImage: "folder.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!canBuildHandoff || finalOutputsLocked || isBuildingPackage)
            .listRowBackground(Color.clear)

            // Share Capture Package
            Button {
                buildPackageIfNeeded { showingWorkspaceShare = true }
            } label: {
                Label("Share Capture Package", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!canBuildHandoff || finalOutputsLocked || isBuildingPackage)
            .listRowBackground(Color.clear)

            if finalOutputsLocked {
                Label("Final outputs stay locked until review is completed in Atlas Mind.", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let errorMessage = workspacePackageError {
                Label(errorMessage, systemImage: "xmark.circle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            // Developer-only actions
            if developerMode.isEnabled {
                Divider()
                    .listRowBackground(Color.clear)

                Button {
                    buildJSONIfNeeded { showingJSONInspector = true }
                } label: {
                    Label("Inspect JSON", systemImage: "chevron.left.forwardslash.chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    buildJSONIfNeeded { copyJSONToClipboard() }
                } label: {
                    HStack {
                        Label(
                            copiedToClipboard ? "Copied!" : "Copy JSON to Clipboard",
                            systemImage: copiedToClipboard ? "checkmark" : "doc.on.clipboard"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage = jsonExportError {
                    Label(errorMessage, systemImage: "xmark.circle")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
        } header: {
            Text("Handoff")
        } footer: {
            if developerMode.isEnabled {
                Text("Developer mode is active. JSON actions are visible.")
                    .foregroundStyle(.orange)
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

    /// Compact fallback row offering "Copy Link" and "Retry" for the quote planner handoff.
    private func quotePlannerFallbackActions(url: URL) -> some View {
        HStack(spacing: 12) {
            Button {
                #if canImport(UIKit)
                UIPasteboard.general.string = url.absoluteString
                #endif
                copiedQuotePlannerLink = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    copiedQuotePlannerLink = false
                }
            } label: {
                Label(
                    copiedQuotePlannerLink ? "Copied!" : "Copy Link",
                    systemImage: copiedQuotePlannerLink ? "checkmark" : "doc.on.clipboard"
                )
                .font(.caption)
            }

            Button {
                performQuotePlannerHandoff()
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.caption)
            }
        }
        .foregroundStyle(Color.accentColor)
    }

    // MARK: - Actions: Mind handoff

    /// Builds the workspace package and opens Atlas Mind with the visitId.
    private func performMindHandoff() {
        workspacePackageError = nil
        isBuildingPackage = true

        buildPackageIfNeeded {
            isBuildingPackage = false
            mindHandoffVisitId = store.draft.visitReference
            showingMindHandoff = true
        }
    }

    private var reviewHandoff: ScanToMindHandoffV1? {
        guard let result = try? CaptureSessionExporter.export(store.draft) else {
            return nil
        }
        return ScanToMindHandoffBuilder.buildHandoffFromDraft(
            store.draft,
            capture: result.payload,
            reason: .reviewInMind
        )
    }

    // MARK: - Actions: Quote planner handoff

    /// Builds the SessionCaptureV2, constructs a quote-planner handoff, and
    /// opens Atlas Mind at the /quote-planner route.
    ///
    /// Caches the quote-planner URL so the "Copy Link" fallback is available
    /// without re-encoding.  Always clears any previous error before attempting.
    private func performQuotePlannerHandoff() {
        quotePlannerHandoffError = nil
        isBuildingQuotePlanner = true

        do {
            let result = try CaptureSessionExporter.export(store.draft)
            let handoff = ScanToMindHandoffBuilder.buildHandoffFromDraft(
                store.draft,
                capture: result.payload,
                reason: .quotePlanner
            )
            let url = OpenAtlasMind.makeQuotePlannerURL(for: handoff)
            quotePlannerLinkURL = url
            isBuildingQuotePlanner = false
            OpenAtlasMind.openQuotePlanner(with: handoff)
        } catch {
            quotePlannerHandoffError = "Quote Planner handoff failed: \(error.localizedDescription)"
            isBuildingQuotePlanner = false
        }
    }

    // MARK: - Actions: workspace package

    /// Builds the workspace package if not already built, then calls `completion`.
    private func buildPackageIfNeeded(completion: @escaping () -> Void) {
        workspacePackageError = nil
        isBuildingPackage = true
        do {
            let result = try CaptureSessionExporter.export(store.draft)
            let package = try WorkspaceExporter.exportPackage(store.draft, jsonData: result.jsonData)
            atlasVisitURL = package.atlasVisitURL
            store.markExported()
            isBuildingPackage = false
            completion()
        } catch {
            workspacePackageError = "Package build failed: \(error.localizedDescription)"
            store.markExportFailed()
            isBuildingPackage = false
        }
    }

    // MARK: - Actions: JSON (dev only)

    // Note: JSON is cached because the SessionCaptureV2 payload is deterministic from the
    // draft and re-encoding on every tap is wasteful. Workspace packages are always rebuilt
    // fresh because they embed timestamps and copy media files from disk at build time.
    private func buildJSONIfNeeded(completion: @escaping () -> Void) {
        jsonExportError = nil
        if exportResult != nil {
            completion()
            return
        }
        do {
            let result = try CaptureSessionExporter.export(store.draft)
            exportResult = result
            completion()
        } catch {
            jsonExportError = "JSON export failed: \(error.localizedDescription)"
        }
    }

    private func copyJSONToClipboard() {
        guard let result = exportResult else { return }
        #if canImport(UIKit)
        UIPasteboard.general.string = String(data: result.jsonData, encoding: .utf8)
        #endif
        copiedToClipboard = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copiedToClipboard = false
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
