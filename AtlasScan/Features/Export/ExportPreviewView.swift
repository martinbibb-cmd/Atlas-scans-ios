import SwiftUI
import AtlasContracts

// MARK: - ExportPreviewView
//
// Atlas handoff / export delivery UX.
// Shows a validated export readiness summary and lets the engineer
// share, save, or inspect the export bundle before sending it to Atlas.

struct ExportPreviewView: View {

    @Binding var job: ScanJob
    @EnvironmentObject private var jobStore: ScanJobStore
    @Environment(\.dismiss) private var dismiss

    @State private var validationIssues: [ValidationIssue] = []
    @State private var bundle: ScanBundleV1?
    @State private var bundleJSON: String = ""
    @State private var shareItem: ShareItem?
    @State private var pendingPackage: ExportPackage?
    @State private var isBuilding = false
    @State private var buildError: String?
    @State private var showingJSONInspector = false
    @State private var includeEvidence = false

    private let builder = ExportBuilder()
    private let packageBuilder = ExportPackageBuilder()

    // MARK: - Derived state

    private var blockingIssues: [ValidationIssue] {
        validationIssues.filter { $0.severity == .blocking }
    }
    private var warningIssues: [ValidationIssue] {
        validationIssues.filter { $0.severity == .warning }
    }
    private var infoIssues: [ValidationIssue] {
        validationIssues.filter { $0.severity == .info }
    }
    private var isReadyToExport: Bool { blockingIssues.isEmpty }

    var body: some View {
        NavigationStack {
            List {
                readinessBannerSection
                validationSection
                if bundle != nil {
                    bundleSummarySection
                    exportOptionsSection
                    exportActionsSection
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Export to Atlas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear { runValidation() }
            .sheet(item: $shareItem, onDismiss: { pendingPackage?.cleanup(); pendingPackage = nil }) { item in
                ShareSheet(items: [item.url])
            }
            .sheet(isPresented: $showingJSONInspector) {
                JSONInspectorView(json: bundleJSON)
            }
        }
    }

    // MARK: - Sections

    /// Top banner showing overall readiness at a glance.
    private var readinessBannerSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: isReadyToExport ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(isReadyToExport ? .green : (blockingIssues.isEmpty ? .orange : .red))

                VStack(alignment: .leading, spacing: 2) {
                    Text(readinessTitle)
                        .font(.headline)
                    Text(readinessSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var readinessTitle: String {
        if !blockingIssues.isEmpty { return "Not Ready to Export" }
        if !warningIssues.isEmpty  { return "Ready — with warnings" }
        return "Ready to Export"
    }

    private var readinessSubtitle: String {
        if !blockingIssues.isEmpty {
            return "\(blockingIssues.count) blocking \(blockingIssues.count == 1 ? "issue" : "issues") must be resolved."
        }
        if !warningIssues.isEmpty {
            return "\(warningIssues.count) \(warningIssues.count == 1 ? "warning" : "warnings") — export is allowed."
        }
        return "All checks passed. Bundle is ready to share."
    }

    private var validationSection: some View {
        Group {
            if !blockingIssues.isEmpty {
                issueSection(title: "Blocking", issues: blockingIssues, color: .red, icon: "xmark.circle.fill")
            }
            if !warningIssues.isEmpty {
                issueSection(title: "Warnings", issues: warningIssues, color: .orange, icon: "exclamationmark.triangle.fill")
            }
            if !infoIssues.isEmpty {
                issueSection(title: "Notes", issues: infoIssues, color: .blue, icon: "info.circle.fill")
            }
            if validationIssues.isEmpty {
                Section("Validation") {
                    Label("All checks passed", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                }
            }
        }
    }

    private func issueSection(
        title: String,
        issues: [ValidationIssue],
        color: Color,
        icon: String
    ) -> some View {
        Section(title) {
            ForEach(issues) { issue in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: icon)
                        .foregroundStyle(color)
                        .frame(width: 20)
                    Text(issue.message)
                        .font(.subheadline)
                }
            }
        }
    }

    private var bundleSummarySection: some View {
        Section("Bundle Summary") {
            if let b = bundle {
                LabeledContent("Schema version", value: b.version)
                LabeledContent("Bundle ID", value: String(b.bundleId.prefix(8)) + "…")
                LabeledContent("Rooms", value: "\(b.rooms.count)")
                LabeledContent("Tagged objects", value: "\(b.rooms.reduce(0) { $0 + $1.detectedObjects.count })")
                LabeledContent("QA flags", value: "\(b.qaFlags.count)")
                LabeledContent("Captured at", value: b.meta.capturedAt)
            }
        }
    }

    private var exportOptionsSection: some View {
        Section("Options") {
            Toggle(isOn: $includeEvidence) {
                Label("Include evidence photos", systemImage: "photo.on.rectangle")
            }
        }
    }

    private var exportActionsSection: some View {
        Section {
            if isBuilding {
                HStack {
                    ProgressView()
                    Text("Building package…")
                        .foregroundStyle(.secondary)
                }
            } else if let error = buildError {
                Label(error, systemImage: "xmark.circle")
                    .foregroundStyle(.red)
                    .font(.subheadline)
            } else {
                Button {
                    shareBundle()
                } label: {
                    Label("Share Bundle (.json)", systemImage: "square.and.arrow.up")
                }
                .disabled(!isReadyToExport || bundle == nil)

                Button {
                    saveToDocuments()
                } label: {
                    Label("Save to Files", systemImage: "arrow.down.doc")
                }
                .disabled(!isReadyToExport || bundle == nil)

                Button {
                    showingJSONInspector = true
                } label: {
                    Label("Inspect JSON", systemImage: "doc.text.magnifyingglass")
                }
                .disabled(bundleJSON.isEmpty)

                Button {
                    copyJSONToClipboard()
                } label: {
                    Label("Copy JSON", systemImage: "doc.on.clipboard")
                }
                .disabled(bundleJSON.isEmpty)
            }
        } header: {
            Text("Actions")
        } footer: {
            if !isReadyToExport {
                Text("Resolve all blocking issues before sharing or saving.")
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Logic

    private func runValidation() {
        validationIssues = builder.validate(job: job)

        let hasBlockers = validationIssues.contains(where: { $0.severity == .blocking })
        if !hasBlockers {
            buildBundle()
        }
    }

    private func buildBundle() {
        isBuilding = true
        buildError = nil

        let built = builder.buildBundle(from: job)
        do {
            let data = try builder.encode(bundle: built)

            // Validate the encoded payload against the shared contract before
            // allowing the engineer to share or save it.
            let contractResult = builder.validateBundle(data: data)
            if case .failure(let errors) = contractResult {
                buildError = "Contract validation failed: \(errors.joined(separator: "; "))"
                isBuilding = false
                return
            }

            bundleJSON = String(decoding: data, as: UTF8.self)
            bundle = built

            // Persist export draft state.
            var draft = job.exportDraftState ?? ExportDraftState(jobID: job.id)
            draft.status = .readyToExport
            draft.bundlePayloadJSON = bundleJSON
            draft.validationIssues = validationIssues
            job.exportDraftState = draft
            jobStore.save(job)
        } catch {
            buildError = "Failed to encode bundle: \(error.localizedDescription)"
        }

        isBuilding = false
    }

    private func shareBundle() {
        guard isReadyToExport, !bundleJSON.isEmpty else { return }
        isBuilding = true
        buildError = nil
        let capturedJob = job
        let capturedJSON = bundleJSON
        let capturedInclude = includeEvidence
        Task {
            do {
                let pkg = try packageBuilder.buildPackage(
                    from: capturedJob,
                    bundleJSON: capturedJSON,
                    includeEvidence: capturedInclude
                )
                await MainActor.run {
                    pendingPackage = pkg
                    shareItem = ShareItem(url: pkg.bundleFile)
                    isBuilding = false
                }
            } catch {
                await MainActor.run {
                    buildError = error.localizedDescription
                    isBuilding = false
                }
            }
        }
    }

    private func saveToDocuments() {
        guard isReadyToExport, !bundleJSON.isEmpty else { return }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let safeRef = job.jobReference.replacingOccurrences(of: "/", with: "-")
        let file = docs.appendingPathComponent("\(safeRef).scanbundle.json")
        do {
            try bundleJSON.write(to: file, atomically: true, encoding: .utf8)

            var draft = job.exportDraftState ?? ExportDraftState(jobID: job.id)
            draft.status = .exported
            draft.lastSucceededAt = Date()
            job.exportDraftState = draft
            job.status = .exported
            jobStore.save(job)
            dismiss()
        } catch {
            buildError = error.localizedDescription
        }
    }

    private func copyJSONToClipboard() {
        guard !bundleJSON.isEmpty else { return }
        #if canImport(UIKit)
        UIPasteboard.general.string = bundleJSON
        #endif
    }
}

// MARK: - JSONInspectorView

struct JSONInspectorView: View {
    let json: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(json)
                    .font(.system(.caption, design: .monospaced))
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Bundle JSON")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - ShareItem (Identifiable wrapper)

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - ShareSheet (UIActivityViewController wrapper)

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Previews

#if DEBUG
#Preview {
    ExportPreviewView(job: .constant(MockData.sampleJob))
        .environmentObject(ScanJobStore())
}
#endif
