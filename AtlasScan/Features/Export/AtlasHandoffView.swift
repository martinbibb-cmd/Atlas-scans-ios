import SwiftUI
import AtlasContracts

// MARK: - AtlasHandoffView
//
// Primary handoff surface for sending a PropertyScanSession to Atlas Mind.
//
// Shows a summary of the canonical AtlasPropertyV1 projection and lets the
// engineer share, save, or inspect the payload before it leaves the device.
//
// This is the PR 5 replacement for the legacy ExportPreviewView path on the
// session workflow.  ExportPreviewView (ScanJob-based) is kept for legacy
// compatibility but is no longer reachable from primary navigation.

struct AtlasHandoffView: View {

    let session: PropertyScanSession
    @Environment(\.dismiss) private var dismiss

    @State private var property: AtlasPropertyV1?
    @State private var propertyJSON: String = ""
    @State private var shareItem: HandoffShareItem?
    @State private var isBuilding = false
    @State private var buildError: String?
    @State private var showingJSONInspector = false

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    var body: some View {
        NavigationStack {
            List {
                readinessBannerSection
                propertySummarySection
                if property != nil {
                    roomSummarySection
                    evidenceSummarySection
                    handoffActionsSection
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Send to Atlas Mind")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear { buildHandoff() }
            .sheet(item: $shareItem) { item in
                ShareSheet(items: [item.url])
            }
            .sheet(isPresented: $showingJSONInspector) {
                JSONInspectorView(json: propertyJSON)
            }
        }
    }

    // MARK: - Sections

    private var readinessBannerSection: some View {
        Section {
            HStack(spacing: 12) {
                if isBuilding {
                    ProgressView()
                        .frame(width: 32, height: 32)
                } else if buildError != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title2)
                        .foregroundStyle(.red)
                } else {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(isBuilding ? "Building payload…" : (buildError != nil ? "Build failed" : "Ready to hand off"))
                        .font(.headline)
                    if let error = buildError {
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    } else if !isBuilding {
                        Text("AtlasPropertyV1 · schema \(currentAtlasPropertyVersion)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var propertySummarySection: some View {
        Section("Property") {
            LabeledContent("Address", value: session.propertyAddress)
            LabeledContent("Reference", value: session.jobReference)
            if !session.engineerName.isEmpty {
                LabeledContent("Engineer", value: session.engineerName)
            }
            if let atlasJobID = session.atlasJobID {
                LabeledContent("Atlas Job ID", value: atlasJobID)
            }
            LabeledContent("Capture state", value: session.scanState.displayName)
            LabeledContent("Review state", value: session.reviewState.displayName)
        }
    }

    @ViewBuilder
    private var roomSummarySection: some View {
        if let p = property {
            Section("Rooms") {
                LabeledContent("Total rooms", value: "\(p.rooms.count)")
                LabeledContent(
                    "Reviewed",
                    value: "\(p.rooms.filter(\.isReviewed).count) / \(p.rooms.count)"
                )
                LabeledContent(
                    "LiDAR captured",
                    value: "\(p.rooms.filter(\.geometryCaptured).count) / \(p.rooms.count)"
                )
                let totalObjects = p.rooms.reduce(0) { $0 + $1.objects.count } + p.sessionObjects.count
                LabeledContent("Tagged objects", value: "\(totalObjects)")
                if !p.adjacencies.isEmpty {
                    LabeledContent("Room links", value: "\(p.adjacencies.count)")
                }
            }
        }
    }

    @ViewBuilder
    private var evidenceSummarySection: some View {
        if let p = property {
            Section("Evidence") {
                LabeledContent("Photos", value: "\(p.evidenceSummary.totalPhotos)")
                LabeledContent("Voice notes", value: "\(p.evidenceSummary.totalVoiceNotes)")
            }
        }
    }

    private var handoffActionsSection: some View {
        Section {
            Button {
                shareHandoff()
            } label: {
                Label("Share to Atlas Mind (.json)", systemImage: "square.and.arrow.up")
            }
            .disabled(propertyJSON.isEmpty || isBuilding)

            Button {
                saveToFiles()
            } label: {
                Label("Save to Files", systemImage: "arrow.down.doc")
            }
            .disabled(propertyJSON.isEmpty || isBuilding)

            Button {
                showingJSONInspector = true
            } label: {
                Label("Inspect Payload", systemImage: "doc.text.magnifyingglass")
            }
            .disabled(propertyJSON.isEmpty)

            Button {
                copyJSONToClipboard()
            } label: {
                Label("Copy JSON", systemImage: "doc.on.clipboard")
            }
            .disabled(propertyJSON.isEmpty)
        } header: {
            Text("Handoff")
        } footer: {
            Text("The canonical AtlasPropertyV1 payload is self-describing. Atlas Mind reads this directly — no conversion needed.")
                .font(.caption2)
        }
    }

    // MARK: - Logic

    private func buildHandoff() {
        isBuilding = true
        buildError = nil

        let built = session.toAtlasPropertyV1()
        do {
            let data = try encoder.encode(built)
            propertyJSON = String(decoding: data, as: UTF8.self)
            property = built
        } catch {
            buildError = "Failed to encode payload: \(error.localizedDescription)"
        }

        isBuilding = false
    }

    private func shareHandoff() {
        guard !propertyJSON.isEmpty else { return }
        let fileName = "\(session.safeFileNameReference).atlasproperty.json"
        let url = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(fileName)
        do {
            try propertyJSON.write(to: url, atomically: true, encoding: .utf8)
            shareItem = HandoffShareItem(url: url)
        } catch {
            buildError = error.localizedDescription
        }
    }

    private func saveToFiles() {
        guard !propertyJSON.isEmpty else { return }
        let docURLs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        guard let docs = docURLs.first else {
            buildError = "Could not resolve Documents directory."
            return
        }
        let file = docs.appendingPathComponent("\(session.safeFileNameReference).atlasproperty.json")
        do {
            try propertyJSON.write(to: file, atomically: true, encoding: .utf8)
            dismiss()
        } catch {
            buildError = error.localizedDescription
        }
    }

    private func copyJSONToClipboard() {
        guard !propertyJSON.isEmpty else { return }
        #if canImport(UIKit)
        UIPasteboard.general.string = propertyJSON
        #endif
    }
}

// MARK: - HandoffShareItem

private struct HandoffShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - Previews

#if DEBUG
#Preview {
    AtlasHandoffView(session: MockData.sampleSession)
}
#endif
