import SwiftUI

// MARK: - RoomScanListView
//
// Lists all room scans captured during the visit.
// Provides navigation to capture a new room scan.

struct RoomScanListView: View {

    @ObservedObject var store: CaptureSessionStore
    @State private var showingCapture = false
    @State private var editingScan: CapturedRoomScanDraft?

    var body: some View {
        List {
            if store.draft.roomScans.isEmpty {
                emptyState
            } else {
                scansSection
            }
            captureSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Room Scans")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingCapture) {
            RoomScanCaptureView { scan in
                store.addRoomScan(scan)
                showingCapture = false
            }
        }
        .sheet(item: $editingScan) { scan in
            RoomScanEditView(scan: scan) { updated in
                store.updateRoomScan(updated)
                editingScan = nil
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "lidar.scanner")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("No room scans yet")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Capture a LiDAR room scan to document each room's geometry.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    // MARK: - Scans list

    private var scansSection: some View {
        Section("Room Scans (\(store.draft.roomScans.count))") {
            ForEach(store.draft.roomScans) { scan in
                scanRow(scan)
                    .contentShape(Rectangle())
                    .onTapGesture { editingScan = scan }
            }
            .onDelete { indexSet in
                indexSet.forEach { i in
                    store.removeRoomScan(id: store.draft.roomScans[i].id)
                }
            }
        }
    }

    private func scanRow(_ scan: CapturedRoomScanDraft) -> some View {
        HStack(spacing: 12) {
            scanThumbnail
            VStack(alignment: .leading, spacing: 4) {
                Text(scan.roomLabel ?? "Unnamed Room")
                    .font(.body)
                HStack(spacing: 8) {
                    confidenceBadge(scan.confidence)
                    if let w = scan.rawWidthM, let d = scan.rawDepthM {
                        Text(String(format: "%.1f × %.1f m", w, d))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(scan.captureTimestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if !scan.warningCodes.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var scanThumbnail: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.accentColor.opacity(0.15))
            .frame(width: 44, height: 44)
            .overlay {
                Image(systemName: "cube.fill")
                    .foregroundStyle(.accentColor)
            }
    }

    private func confidenceBadge(_ confidence: RoomScanConfidence) -> some View {
        let color: Color
        switch confidence {
        case .high:   color = .green
        case .medium: color = .orange
        case .low:    color = .red
        }
        return Text(confidence.displayName)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    // MARK: - Capture section

    private var captureSection: some View {
        Section {
            Button {
                showingCapture = true
            } label: {
                Label("Capture Room Scan", systemImage: "lidar.scanner")
                    .font(.body.bold())
            }
        } header: {
            Text("Actions")
        } footer: {
            Text("LiDAR scan data is stored as raw evidence. No heat-loss or engineering calculations are run on scan assets.")
                .font(.caption2)
        }
    }
}

// MARK: - RoomScanEditView

struct RoomScanEditView: View {

    @State var scan: CapturedRoomScanDraft
    let onSave: (CapturedRoomScanDraft) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Room Details") {
                    TextField("Room label (optional)", text: Binding(
                        get: { scan.roomLabel ?? "" },
                        set: { scan.roomLabel = $0.isEmpty ? nil : $0 }
                    ))
                }
                Section("Captured") {
                    LabeledContent("Timestamp", value: scan.captureTimestamp.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Confidence", value: scan.confidence.displayName)
                    if let w = scan.rawWidthM {
                        LabeledContent("Width", value: String(format: "%.2f m", w))
                    }
                    if let d = scan.rawDepthM {
                        LabeledContent("Depth", value: String(format: "%.2f m", d))
                    }
                    if let h = scan.rawHeightM {
                        LabeledContent("Height", value: String(format: "%.2f m", h))
                    }
                }
                if !scan.warningCodes.isEmpty {
                    Section("Capture Warnings") {
                        ForEach(scan.warningCodes, id: \.self) { code in
                            Label(code, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .navigationTitle("Room Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(scan)
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    var draft = CaptureSessionDraft()
    draft.visitReference = "JOB-001"
    var scan = CapturedRoomScanDraft()
    scan.roomLabel = "Kitchen"
    scan.rawWidthM = 4.2
    scan.rawDepthM = 3.8
    scan.rawHeightM = 2.4
    scan.confidence = .high
    draft.roomScans = [scan]
    let store = CaptureSessionStore(draft: draft)
    return NavigationStack {
        RoomScanListView(store: store)
    }
}
#endif
