import SwiftUI

// MARK: - RoomScanListView
//
// Lists all room scans captured during the visit.
// Provides two capture modes:
//   • Scan with LiDAR  — fullscreen RoomPlan capture (hardware-dependent)
//   • Enter manually   — manual dimension entry sheet (always available)

struct RoomScanListView: View {

    @ObservedObject var store: CaptureSessionStore
    @State private var showingManualEntry = false
    @State private var showingLiDARCapture = false
    @State private var editingScan: CapturedRoomScanDraft?
    @State private var openFloorPlanForScan: CapturedRoomScanDraft?

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
        // Manual entry sheet
        .sheet(isPresented: $showingManualEntry) {
            RoomScanManualEntrySheet { scan in
                store.addRoomScan(scan)
                showingManualEntry = false
            }
        }
        // LiDAR capture fullscreen modal
        .fullScreenCover(isPresented: $showingLiDARCapture) {
            RoomPlanCaptureView(
                roomIndex: store.draft.roomScans.count + 1
            ) { scan, pins, snapshot in
                store.addRoomScan(scan)
                pins.forEach { store.addObjectPin($0) }
                store.addFloorPlanSnapshot(snapshot)
                showingLiDARCapture = false
                openFloorPlanForScan = scan
            } onCancel: {
                showingLiDARCapture = false
            }
        }
        // Floor plan editor opened after LiDAR accept
        .sheet(item: $openFloorPlanForScan) { scan in
            FloorPlanEditorView(
                scan: scan,
                onSnapshot: { snapshot in store.addFloorPlanSnapshot(snapshot) },
                onSave: { updated in
                    store.updateRoomScan(updated)
                    openFloorPlanForScan = nil
                }
            )
        }
        // Existing scan edit sheet
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
                Image(systemName: "cube.transparent")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("No room scans yet")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Add a room scan record to document each room's geometry.")
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
            scanThumbnail(source: scan.captureSource)
            VStack(alignment: .leading, spacing: 4) {
                Text(scan.roomLabel ?? "Unnamed Room")
                    .font(.body)
                HStack(spacing: 8) {
                    captureSourceBadge(scan.captureSource)
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

    private func scanThumbnail(source: RoomScanCaptureSource) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.accentColor.opacity(0.15))
            .frame(width: 44, height: 44)
            .overlay {
                Image(systemName: source == .lidar ? "lidar.scanner" : "cube.fill")
                    .foregroundStyle(Color.accentColor)
            }
    }

    private func captureSourceBadge(_ source: RoomScanCaptureSource) -> some View {
        let color: Color = source == .lidar ? .blue : .secondary
        return Label(source.displayName, systemImage: source.symbolName)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
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
                showingLiDARCapture = true
            } label: {
                Label("Scan with LiDAR", systemImage: "lidar.scanner")
                    .font(.body.bold())
            }

            Button {
                showingManualEntry = true
            } label: {
                Label("Enter Manually", systemImage: "pencil")
                    .font(.body)
            }
        } header: {
            Text("Add Room Scan")
        } footer: {
            Text("LiDAR scanning requires a device with a LiDAR sensor. Manual entry is always available.")
                .font(.caption2)
        }
    }
}

// MARK: - RoomScanManualEntrySheet
//
// Lets the engineer manually record a room scan artefact when
// LiDAR hardware capture is unavailable or not required.
// All fields are optional except the room label; engineers can fill
// in dimensions and confidence from their own measurement tools.

struct RoomScanManualEntrySheet: View {

    let onSave: (CapturedRoomScanDraft) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var roomLabel:   String = ""
    @State private var widthText:   String = ""
    @State private var depthText:   String = ""
    @State private var heightText:  String = ""
    @State private var confidence:  RoomScanConfidence = .medium

    private var canSave: Bool {
        !roomLabel.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Room Details") {
                    TextField("Room label (e.g. Kitchen)", text: $roomLabel)
                }

                Section {
                    TextField("Width (m)", text: $widthText)
                        .keyboardType(.decimalPad)
                    TextField("Depth (m)", text: $depthText)
                        .keyboardType(.decimalPad)
                    TextField("Ceiling height (m)", text: $heightText)
                        .keyboardType(.decimalPad)
                } header: {
                    Text("Dimensions (optional)")
                } footer: {
                    Text("Enter approximate room dimensions if known.")
                        .font(.caption2)
                }

                Section("Confidence") {
                    Picker("Confidence", selection: $confidence) {
                        ForEach(RoomScanConfidence.allCases, id: \.self) { c in
                            Text(c.displayName).tag(c)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Add Room Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveScan() }
                        .disabled(!canSave)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func saveScan() {
        var scan = CapturedRoomScanDraft()
        scan.roomLabel     = roomLabel.trimmingCharacters(in: .whitespaces)
        scan.rawWidthM     = Double(widthText.trimmingCharacters(in: .whitespaces))
        scan.rawDepthM     = Double(depthText.trimmingCharacters(in: .whitespaces))
        scan.rawHeightM    = Double(heightText.trimmingCharacters(in: .whitespaces))
        scan.confidence    = confidence
        scan.captureSource = .manual
        onSave(scan)
        dismiss()
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
