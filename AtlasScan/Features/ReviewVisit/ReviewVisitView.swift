import SwiftUI
import AtlasContracts

// MARK: - ReviewVisitView
//
// Full visit review screen shown before export.
//
// Sections:
//   1. Visit details (reference, address, customer, dates)
//   2. Rooms — LiDAR status, dimensions, floor plan thumbnail, per-room counts
//   3. Objects — all placed pins with type, label, room link
//   4. Photos — grid with room/object badges
//   5. Transcript — voice notes grouped by room with status badges
//   6. Readiness — blocking errors + non-blocking warnings
//   7. Export — export button + sync state

struct ReviewVisitView: View {

    @ObservedObject var store: CaptureSessionStore

    @State private var showingExportPreview = false
    @State private var exportResult: CaptureExportResult?
    @State private var exportError: String?
    @State private var showingExportConfirm = false
    @State private var showingFullPhoto: CapturedPhotoDraft? = nil

    @State private var showingAtlasMindShare = false
    @State private var atlasVisitURL: URL?
    @State private var showingAtlasMindConfirm = false

    var body: some View {
        List {
            visitSection
            roomsSection
            objectsSection
            photosSection
            transcriptSection
            readinessSection
            exportSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Review Visit")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingExportPreview) {
            if let result = exportResult {
                exportPreviewSheet(result: result)
            }
        }
        .sheet(isPresented: $showingAtlasMindShare) {
            if let url = atlasVisitURL {
                ShareSheet(items: [url])
            }
        }
        .confirmationDialog(
            "Export to Atlas Recommendations?",
            isPresented: $showingExportConfirm,
            titleVisibility: .visible
        ) {
            Button("Export Now") { performExport() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This packages the session and sends it to Atlas Recommendations.")
        }
        .confirmationDialog(
            "Open in Atlas Mind?",
            isPresented: $showingAtlasMindConfirm,
            titleVisibility: .visible
        ) {
            Button("Build & Share Package") { performAtlasMindExport() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This assembles a .atlasvisit package and opens the iOS share sheet so you can send it to Atlas Mind.")
        }
    }

    // MARK: - Visit section

    private var visitSection: some View {
        Section("Visit") {
            LabeledContent("Reference") {
                Text(store.draft.visitReference.isEmpty ? "—" : store.draft.visitReference)
                    .foregroundStyle(store.draft.visitReference.isEmpty ? .red : .primary)
            }
            if let apptId = store.draft.appointmentId {
                LabeledContent("Appointment ID") {
                    Text(apptId)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            if !store.draft.propertyAddress.isEmpty {
                LabeledContent("Address", value: store.draft.propertyAddress)
            }
            if !store.draft.customerName.isEmpty {
                LabeledContent("Customer", value: store.draft.customerName)
            }
            LabeledContent("Started", value: store.draft.capturedAt.formatted(date: .abbreviated, time: .shortened))
            LabeledContent("Updated", value: store.draft.updatedAt.formatted(date: .abbreviated, time: .shortened))
            LabeledContent("Status", value: store.draft.exportState.displayName)
            if store.draft.syncState != .notSynced {
                LabeledContent("Sync", value: store.draft.syncState.displayName)
            }
            if let remoteId = store.draft.remoteVisitId {
                LabeledContent("Remote ID", value: remoteId)
                    .font(.caption)
            }
        }
    }

    // MARK: - Rooms section

    private var roomsSection: some View {
        Section("Rooms (\(store.draft.roomScans.count))") {
            if store.draft.roomScans.isEmpty {
                Label("No rooms captured", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.caption)
            } else {
                ForEach(store.draft.roomScans) { scan in
                    roomRow(scan)
                }
            }
        }
    }

    private func roomRow(_ scan: CapturedRoomScanDraft) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: scan.rawScanAssetRef != nil ? "lidar.scanner" : "square.dashed")
                    .foregroundStyle(scan.rawScanAssetRef != nil ? .green : .secondary)
                    .font(.caption.bold())
                Text(scan.roomLabel ?? "Unnamed Room")
                    .font(.body)
                Spacer()
                if scan.floorPlan != nil {
                    Image(systemName: "pencil.tip.crop.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
            }
            HStack(spacing: 12) {
                if let w = scan.rawWidthM, let d = scan.rawDepthM {
                    Text(String(format: "%.1f × %.1f m", w, d))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                let pinCount = store.draft.objectPins.filter { $0.roomId == scan.id }.count
                if pinCount > 0 {
                    Label("\(pinCount) objects", systemImage: "mappin.and.ellipse")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                let photoCount = store.draft.photos.filter { $0.roomId == scan.id }.count
                if photoCount > 0 {
                    Label("\(photoCount) photos", systemImage: "camera")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                let noteCount = store.draft.voiceNotes.filter { $0.roomId == scan.id }.count
                if noteCount > 0 {
                    Label("\(noteCount) notes", systemImage: "mic")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Objects section

    private var objectsSection: some View {
        Section("Objects (\(store.draft.objectPins.count))") {
            if store.draft.objectPins.isEmpty {
                Text("No objects placed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.draft.objectPins.sorted { $0.placedAt < $1.placedAt }) { pin in
                    objectRow(pin)
                }
            }
        }
    }

    private func objectRow(_ pin: CapturedObjectPinDraft) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: pin.type.symbolName)
                    .font(.caption.bold())
                    .foregroundStyle(Color.accentColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(pin.label ?? pin.type.displayName)
                    .font(.body)
                HStack(spacing: 6) {
                    Text(pin.type.displayName)
                        .font(.caption2).foregroundStyle(.secondary)
                    if let roomId = pin.roomId,
                       let scan = store.draft.roomScans.first(where: { $0.id == roomId }) {
                        Text("·").foregroundStyle(.tertiary).font(.caption2)
                        Text(scan.roomLabel ?? "Room")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            if pin.linkedPhotoId != nil {
                Image(systemName: "camera.fill")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Photos section

    private var photosSection: some View {
        Section("Photos (\(store.draft.photos.count))") {
            if store.draft.photos.isEmpty {
                Text("No photos captured")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 8) {
                    ForEach(store.draft.photos) { photo in
                        photoCell(photo)
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            }
        }
    }

    private func photoCell(_ photo: CapturedPhotoDraft) -> some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.2))
                .frame(height: 70)
                .overlay {
                    Image(systemName: photo.kind.symbolName)
                        .foregroundStyle(.secondary)
                }
            Text(photo.kind.displayName)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let roomId = photo.roomId,
               let scan = store.draft.roomScans.first(where: { $0.id == roomId }) {
                Text(scan.roomLabel ?? "Room")
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .onTapGesture { showingFullPhoto = photo }
    }

    // MARK: - Transcript section

    private var transcriptSection: some View {
        Section("Transcript (\(store.draft.voiceNotes.count) notes)") {
            if store.draft.voiceNotes.isEmpty {
                Text("No voice notes recorded")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                // Summary of latest 2 notes
                let recent = Array(store.draft.voiceNotes.suffix(2))
                ForEach(recent) { note in
                    transcriptNoteRow(note)
                }
                // Navigation link to full transcript view
                NavigationLink {
                    TranscriptView(draft: store.draft)
                } label: {
                    Label("View All Transcripts (\(store.draft.voiceNotes.count))", systemImage: "text.bubble")
                        .font(.caption.bold())
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    private func transcriptNoteRow(_ note: CapturedVoiceNoteDraft) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if note.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Label("No transcript", systemImage: "clock")
                        .font(.caption2).foregroundStyle(.orange)
                } else {
                    Label("Transcribed", systemImage: "checkmark.circle.fill")
                        .font(.caption2).foregroundStyle(.green)
                }
                Spacer()
                Text(note.startedAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            if !note.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(note.transcript)
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Readiness section

    private var readinessSection: some View {
        let blockingErrors = CaptureSessionExporter.validate(store.draft)
        let warnings = buildWarnings()

        return Section("Readiness") {
            if blockingErrors.isEmpty && warnings.isEmpty {
                Label("Ready for export", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green).fontWeight(.semibold)
            } else {
                if !blockingErrors.isEmpty {
                    Label("Blocking issues — fix before export", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red).fontWeight(.semibold).font(.caption.bold())
                    ForEach(blockingErrors, id: \.errorDescription) { err in
                        warningRow(err.localizedDescription, isBlocking: true)
                    }
                } else {
                    Label("Ready (with warnings)", systemImage: "checkmark.seal")
                        .foregroundStyle(.orange).fontWeight(.semibold)
                }
                ForEach(warnings, id: \.self) { w in
                    warningRow(w, isBlocking: false)
                }
            }
        }
    }

    private func buildWarnings() -> [String] {
        var w: [String] = []
        if store.draft.propertyAddress.isEmpty { w.append("No property address entered.") }
        if store.draft.roomScans.isEmpty { w.append("No rooms captured yet.") }
        if store.draft.photos.isEmpty { w.append("No evidence photos captured.") }
        let untranscribed = store.draft.voiceNotes.filter {
            $0.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
        if untranscribed > 0 { w.append("\(untranscribed) voice note(s) have no transcript.") }
        let unlabelled = store.draft.objectPins.filter {
            $0.type == .genericNote && $0.hasNoLabel
        }.count
        if unlabelled > 0 { w.append("\(unlabelled) note pin(s) have no label.") }
        return w
    }

    private func warningRow(_ text: String, isBlocking: Bool) -> some View {
        Label(text, systemImage: isBlocking ? "xmark.circle" : "exclamationmark.triangle")
            .font(.caption).foregroundStyle(isBlocking ? .red : .orange)
    }

    // MARK: - Export section

    private var exportSection: some View {
        let errors = CaptureSessionExporter.validate(store.draft)
        let isReady = errors.isEmpty

        return Section("Export") {
            if store.draft.exportState == .exported {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                    Text("Session exported to Atlas Recommendations")
                        .font(.caption.bold()).foregroundStyle(.green)
                }
            }

            Button {
                showingExportConfirm = true
            } label: {
                Label("Export to Atlas Recommendations", systemImage: "arrow.up.circle.fill")
                    .font(.body.bold()).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isReady || store.draft.exportState == .exported)
            .listRowBackground(Color.clear)

            Button {
                showingAtlasMindConfirm = true
            } label: {
                Label("Open in Atlas Mind", systemImage: "square.and.arrow.up.on.square")
                    .font(.body.bold()).frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!isReady)
            .listRowBackground(Color.clear)

            if let errMsg = exportError {
                Label(errMsg, systemImage: "xmark.circle")
                    .font(.caption).foregroundStyle(.red)
            }
        }
    }

    // MARK: - Export action

    private func performExport() {
        exportError = nil
        do {
            let result = try CaptureSessionExporter.export(store.draft)
            exportResult = result
            store.markExported()
            showingExportPreview = true
        } catch {
            exportError = "Export failed: \(error.localizedDescription)"
            store.markExportFailed()
        }
    }

    // MARK: - Open in Atlas Mind action

    private func performAtlasMindExport() {
        exportError = nil
        do {
            let result = try CaptureSessionExporter.export(store.draft)
            let package = try WorkspaceExporter.exportPackage(store.draft, jsonData: result.jsonData)
            atlasVisitURL = package.atlasVisitURL
            store.markExported()
            showingAtlasMindShare = true
        } catch {
            exportError = "Atlas Mind export failed: \(error.localizedDescription)"
            store.markExportFailed()
        }
    }

    // MARK: - Export preview sheet

    @ViewBuilder
    private func exportPreviewSheet(result: CaptureExportResult) -> some View {
        NavigationStack {
            ScrollView {
                Text(String(data: result.jsonData, encoding: .utf8) ?? "(empty)")
                    .font(.system(.caption2, design: .monospaced))
                    .padding()
            }
            .navigationTitle("Export Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        showingExportPreview = false
                        exportResult = nil
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    let json = String(data: result.jsonData, encoding: .utf8) ?? ""
                    ShareLink(
                        item: json,
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
    draft.propertyAddress = "12 Coronation Street, M1 1AA"
    draft.customerName = "John Smith"
    var scan = CapturedRoomScanDraft()
    scan.roomLabel = "Kitchen"
    scan.rawWidthM = 3.2
    scan.rawDepthM = 4.1
    draft.roomScans = [scan]
    draft.photos = [CapturedPhotoDraft(localFilename: "p1.jpg")]
    var note = CapturedVoiceNoteDraft()
    note.transcript = "Boiler in the utility room, Worcester Bosch 30i."
    draft.voiceNotes = [note]
    var pin = CapturedObjectPinDraft(type: .boiler)
    pin.label = "Worcester Bosch 30i"
    draft.objectPins = [pin]
    let store = CaptureSessionStore(draft: draft)
    return NavigationStack {
        ReviewVisitView(store: store)
    }
}
#endif
