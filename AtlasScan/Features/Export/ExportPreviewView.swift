import SwiftUI

// MARK: - ExportPreviewView
//
// Shows validation results and the export bundle summary.
// Lets the engineer share or save the JSON export bundle.

struct ExportPreviewView: View {

    @Binding var job: ScanJob
    @EnvironmentObject private var jobStore: ScanJobStore
    @Environment(\.dismiss) private var dismiss

    @State private var validationIssues: [ValidationIssue] = []
    @State private var bundle: ScanBundleV1?
    @State private var bundleJSON: String = ""
    @State private var shareItem: ShareItem?
    @State private var isBuilding = false
    @State private var buildError: String?

    private let builder = ExportBuilder()

    var body: some View {
        NavigationStack {
            List {
                validationSection
                if bundle != nil {
                    bundleSummarySection
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
            .sheet(item: $shareItem) { item in
                ShareSheet(items: [item.url])
            }
        }
    }

    // MARK: - Sections

    private var validationSection: some View {
        Section {
            if validationIssues.isEmpty {
                Label("All checks passed", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            } else {
                ForEach(validationIssues) { issue in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: issue.severity == .blocking ? "xmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(issue.severity == .blocking ? .red : .orange)

                        VStack(alignment: .leading) {
                            Text(issue.message)
                                .font(.subheadline)
                            if issue.severity == .info {
                                Text("Info only")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        } header: {
            Text("Validation")
        }
    }

    private var bundleSummarySection: some View {
        Section("Bundle Summary") {
            if let b = bundle {
                LabeledContent("Schema version", value: b.schemaVersion)
                LabeledContent("Bundle ID", value: String(b.bundleID.prefix(8)) + "…")
                LabeledContent("Rooms", value: "\(b.rooms.count)")
                LabeledContent("Tagged objects", value: "\(b.rooms.reduce(0) { $0 + $1.taggedObjects.count })")
                LabeledContent("Exported at", value: b.exportedAt)
            }
        }
    }

    private var exportActionsSection: some View {
        Section {
            if isBuilding {
                HStack {
                    ProgressView()
                    Text("Building bundle…")
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
                .disabled(bundle == nil)

                Button {
                    saveToDocuments()
                } label: {
                    Label("Save to Files", systemImage: "arrow.down.doc")
                }
                .disabled(bundle == nil)
            }
        } header: {
            Text("Actions")
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
            bundleJSON = String(decoding: data, as: UTF8.self)
            bundle = built

            // Update job state
            var draft = ExportDraftState(jobID: job.id)
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
        guard !bundleJSON.isEmpty else { return }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(job.jobReference.replacingOccurrences(of: "/", with: "-")).scanbundle.json")
        do {
            try bundleJSON.write(to: tmp, atomically: true, encoding: .utf8)
            shareItem = ShareItem(url: tmp)
        } catch {
            buildError = error.localizedDescription
        }
    }

    private func saveToDocuments() {
        guard !bundleJSON.isEmpty else { return }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let file = docs.appendingPathComponent("\(job.jobReference.replacingOccurrences(of: "/", with: "-")).scanbundle.json")
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
