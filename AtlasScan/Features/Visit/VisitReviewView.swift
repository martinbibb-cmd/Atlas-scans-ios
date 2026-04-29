import SwiftUI

// MARK: - VisitReviewView
//
// Review all captured evidence for a visit and export the package.
//
// Sections:
//   1. Visit details
//   2. Photos (thumbnail grid)
//   3. Notes (transcript list)
//   4. Export (validation status + share-sheet trigger)
//
// This view is always presented as a sheet so the engineer can always
// dismiss back to the active visit.

struct VisitReviewView: View {

    @ObservedObject var store: CaptureSessionStore
    let onDone: () -> Void

    @State private var isExporting   = false
    @State private var exportError: String?
    @State private var shareItems: [Any]?
    @State private var showingShare  = false

    var body: some View {
        NavigationStack {
            List {
                visitSection
                photosSection
                notesSection
                exportSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Review Visit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { onDone() }
                }
            }
        }
        .sheet(isPresented: $showingShare) {
            if let items = shareItems {
                ShareSheet(items: items)
            }
        }
    }

    // MARK: - Visit section

    private var visitSection: some View {
        Section("Visit Details") {
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
        }
    }

    // MARK: - Photos section

    private var photosSection: some View {
        Section {
            if store.draft.photos.isEmpty {
                Text("No photos captured.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 88), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(store.draft.photos) { photo in
                        PhotoThumbnail(filename: photo.localFilename)
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Photos (\(store.draft.photos.count))")
        }
    }

    // MARK: - Notes section

    private var notesSection: some View {
        Section {
            if store.draft.voiceNotes.isEmpty {
                Text("No notes captured.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.draft.voiceNotes) { note in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(note.transcript.isEmpty ? "(empty note)" : note.transcript)
                            .font(.subheadline)
                        Text(note.startedAt, style: .time)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                }
            }
        } header: {
            Text("Notes (\(store.draft.voiceNotes.count))")
        }
    }

    // MARK: - Export section

    private var exportSection: some View {
        Section {
            if let error = exportError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.subheadline)
            }

            Button {
                performExport()
            } label: {
                HStack {
                    Label(
                        store.draft.exportState == .exported
                            ? "Export Again"
                            : "Export Visit Package",
                        systemImage: "square.and.arrow.up"
                    )
                    Spacer()
                    if isExporting {
                        ProgressView()
                    }
                }
            }
            .disabled(isExporting || !validationErrors.isEmpty)
        } header: {
            Text("Export")
        } footer: {
            Text(validationErrors.isEmpty
                 ? "Ready to export a contract-valid visit package."
                 : validationErrors.joined(separator: " "))
        }
    }

    private var validationErrors: [String] {
        CaptureSessionExporter.validate(store.draft)
            .compactMap { $0.errorDescription }
    }

    // MARK: - Export action

    private func performExport() {
        isExporting = true
        exportError = nil
        Task {
            do {
                let result = try CaptureSessionExporter.export(store.draft)
                let ref = store.draft.visitReference.isEmpty
                    ? "visit"
                    : store.draft.visitReference
                let filename = "\(ref)-export.json"
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(filename)
                try result.jsonData.write(to: tempURL, options: .atomic)
                await MainActor.run {
                    isExporting = false
                    shareItems = [tempURL]
                    showingShare = true
                    store.markExported()
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    exportError = error.localizedDescription
                    store.markExportFailed()
                }
            }
        }
    }
}

// MARK: - PhotoThumbnail

private struct PhotoThumbnail: View {

    let filename: String

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.tertiarySystemFill))
                .aspectRatio(1, contentMode: .fit)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.tertiary)
            }
        }
        .onAppear { loadImage() }
    }

    private func loadImage() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs
            .appendingPathComponent("CapturePhotos")
            .appendingPathComponent(filename)
        if let data = try? Data(contentsOf: url),
           let uiImage = UIImage(data: data) {
            image = uiImage
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    let draft = CaptureSessionStore.newSession(visitReference: "PREVIEW-001")
    VisitReviewView(
        store: CaptureSessionStore(draft: draft),
        onDone: {}
    )
}
#endif
