import SwiftUI

// MARK: - FabricCaptureView
//
// Fabric & perimeter capture UI.
//
// Lets the engineer record per-room boundary and opening evidence:
//   • Select / create a room-linked fabric record
//   • Add / edit boundaries (type, length, height, material)
//   • Add / edit openings (type, dimensions, material, linked boundary)
//
// Design rules:
//   • Raw observation only — no heat-loss calculation, no U-values.
//   • All items default to .confirmed (manually created).
//   • Readiness completion flags are NOT altered by this view.

struct FabricCaptureView: View {

    @ObservedObject var store: CaptureSessionStore

    @State private var showingAddRecord  = false
    @State private var editingRecord: CapturedFloorPlanFabricDraft?

    var body: some View {
        List {
            if store.draft.fabricRecords.isEmpty {
                Section {
                    Label("No fabric records yet. Tap + to add the first room.",
                          systemImage: "square.3.layers.3d")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } header: {
                    Text("Fabric & Perimeter")
                }
            } else {
                ForEach(store.draft.fabricRecords) { record in
                    fabricRecordSection(record)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Fabric & Perimeter")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    var newRecord = CapturedFloorPlanFabricDraft()
                    // Pre-fill room if there is exactly one unlinked room scan.
                    let unlinkedScans = store.draft.roomScans.filter { scan in
                        !store.draft.fabricRecords.contains { $0.roomId == scan.id }
                    }
                    if let only = unlinkedScans.first, unlinkedScans.count == 1 {
                        newRecord.roomId = only.id
                    }
                    store.addFabricRecord(newRecord)
                    editingRecord = newRecord
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $editingRecord) { record in
            FabricRecordEditView(store: store, record: record)
        }
    }

    // MARK: - Per-record section

    @ViewBuilder
    private func fabricRecordSection(_ record: CapturedFloorPlanFabricDraft) -> some View {
        let roomName = roomLabel(for: record.roomId) ?? "Unlinked room"
        Section {
            // Boundaries
            if record.boundaries.isEmpty && record.openings.isEmpty {
                Text("No boundaries or openings recorded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(record.boundaries) { b in
                    boundaryRow(b)
                }
                ForEach(record.openings) { o in
                    openingRow(o)
                }
            }

            Button {
                editingRecord = record
            } label: {
                Label("Edit / add boundaries & openings", systemImage: "pencil")
                    .font(.subheadline)
            }
        } header: {
            Text(roomName)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                store.removeFabricRecord(id: record.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func boundaryRow(_ boundary: CapturedBoundaryDraft) -> some View {
        HStack {
            Image(systemName: reviewStatusSymbol(boundary.reviewStatus))
                .foregroundStyle(reviewStatusColor(boundary.reviewStatus))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(boundary.boundaryType.displayName)
                    .font(.subheadline)
                if let len = boundary.lengthM {
                    Text(String(format: "%.1f m", len) + (boundary.heightM.map { String(format: " × %.1f m", $0) } ?? ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let mat = boundary.material, !mat.isEmpty {
                    Text(mat)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Image(systemName: "square.3.layers.3d")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private func openingRow(_ opening: CapturedOpeningDraft) -> some View {
        HStack {
            Image(systemName: reviewStatusSymbol(opening.reviewStatus))
                .foregroundStyle(reviewStatusColor(opening.reviewStatus))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(opening.openingType.displayName)
                    .font(.subheadline)
                if let w = opening.widthM {
                    Text(String(format: "%.2f m wide", w) + (opening.heightM.map { String(format: " × %.2f m", $0) } ?? ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let mat = opening.material, !mat.isEmpty {
                    Text(mat)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Image(systemName: opening.openingType.symbolName)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Helpers

    private func roomLabel(for roomId: UUID?) -> String? {
        guard let roomId else { return nil }
        return store.draft.roomScans.first(where: { $0.id == roomId })?.roomLabel
    }

    private func reviewStatusSymbol(_ status: EvidenceReviewStatus) -> String {
        status.symbolName
    }

    private func reviewStatusColor(_ status: EvidenceReviewStatus) -> Color {
        switch status {
        case .confirmed: return .green
        case .rejected:  return .red
        case .pending:   return .orange
        }
    }
}

// MARK: - FabricRecordEditView

/// Full-screen edit form for a single fabric record.
private struct FabricRecordEditView: View {

    @ObservedObject var store: CaptureSessionStore
    var record: CapturedFloorPlanFabricDraft

    @Environment(\.dismiss) private var dismiss

    @State private var localRecord: CapturedFloorPlanFabricDraft
    @State private var showingAddBoundary = false
    @State private var showingAddOpening  = false
    @State private var editingBoundary: CapturedBoundaryDraft?
    @State private var editingOpening: CapturedOpeningDraft?

    init(store: CaptureSessionStore, record: CapturedFloorPlanFabricDraft) {
        self.store = store
        self.record = record
        _localRecord = State(initialValue: record)
    }

    var body: some View {
        NavigationStack {
            Form {
                roomSection
                boundariesSection
                openingsSection
            }
            .navigationTitle("Fabric Record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.updateFabricRecord(localRecord)
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingAddBoundary) {
                BoundaryEditSheet(boundary: CapturedBoundaryDraft()) { saved in
                    localRecord.boundaries.append(saved)
                    showingAddBoundary = false
                }
            }
            .sheet(isPresented: $showingAddOpening) {
                OpeningEditSheet(
                    opening: CapturedOpeningDraft(),
                    availableBoundaries: localRecord.boundaries
                ) { saved in
                    localRecord.openings.append(saved)
                    showingAddOpening = false
                }
            }
            .sheet(item: $editingBoundary) { boundary in
                BoundaryEditSheet(boundary: boundary) { saved in
                    if let idx = localRecord.boundaries.firstIndex(where: { $0.id == saved.id }) {
                        localRecord.boundaries[idx] = saved
                    }
                    editingBoundary = nil
                }
            }
            .sheet(item: $editingOpening) { opening in
                OpeningEditSheet(
                    opening: opening,
                    availableBoundaries: localRecord.boundaries
                ) { saved in
                    if let idx = localRecord.openings.firstIndex(where: { $0.id == saved.id }) {
                        localRecord.openings[idx] = saved
                    }
                    editingOpening = nil
                }
            }
        }
    }

    // MARK: - Room section

    private var roomSection: some View {
        Section {
            Picker("Room", selection: $localRecord.roomId) {
                Text("None (unlinked)").tag(Optional<UUID>.none)
                ForEach(store.draft.roomScans) { scan in
                    Text(scan.roomLabel ?? "Unnamed Room").tag(Optional(scan.id))
                }
            }
        } header: {
            Text("Room")
        } footer: {
            Text("Link this fabric record to a scanned room to carry through the perimeter and height.")
                .font(.caption2)
        }
    }

    // MARK: - Boundaries section

    private var boundariesSection: some View {
        Section {
            ForEach(localRecord.boundaries) { boundary in
                Button {
                    editingBoundary = boundary
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(boundary.boundaryType.displayName)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            if let len = boundary.lengthM {
                                Text("\(len, specifier: "%.1f") m")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
            .onDelete { indexSet in
                localRecord.boundaries.remove(atOffsets: indexSet)
            }

            Button {
                showingAddBoundary = true
            } label: {
                Label("Add Boundary", systemImage: "plus.circle")
            }
        } header: {
            Text("Boundaries (\(localRecord.boundaries.count))")
        }
    }

    // MARK: - Openings section

    private var openingsSection: some View {
        Section {
            ForEach(localRecord.openings) { opening in
                Button {
                    editingOpening = opening
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(opening.openingType.displayName)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            if let w = opening.widthM {
                                Text("\(w, specifier: "%.2f") m wide")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
            .onDelete { indexSet in
                localRecord.openings.remove(atOffsets: indexSet)
            }

            Button {
                showingAddOpening = true
            } label: {
                Label("Add Opening", systemImage: "plus.circle")
            }
        } header: {
            Text("Openings (\(localRecord.openings.count))")
        }
    }
}

// MARK: - BoundaryEditSheet

private struct BoundaryEditSheet: View {

    @State private var boundary: CapturedBoundaryDraft
    let onSave: (CapturedBoundaryDraft) -> Void

    @State private var lengthText: String
    @State private var heightText: String

    init(boundary: CapturedBoundaryDraft, onSave: @escaping (CapturedBoundaryDraft) -> Void) {
        self.onSave = onSave
        _boundary = State(initialValue: boundary)
        _lengthText = State(initialValue: boundary.lengthM.map { "\($0)" } ?? "")
        _heightText = State(initialValue: boundary.heightM.map { "\($0)" } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $boundary.boundaryType) {
                        ForEach(BoundaryType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                } header: {
                    Text("Boundary Type")
                }

                Section {
                    HStack {
                        Text("Length (m)")
                        Spacer()
                        TextField("e.g. 3.5", text: $lengthText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Height (m)")
                        Spacer()
                        TextField("e.g. 2.4", text: $heightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("Dimensions")
                }

                Section {
                    TextField("e.g. solid brick, cavity wall", text: Binding(
                        get: { boundary.material ?? "" },
                        set: { boundary.material = $0.isEmpty ? nil : $0 }
                    ))
                } header: {
                    Text("Material")
                }

                Section {
                    Picker("Review Status", selection: $boundary.reviewStatus) {
                        ForEach(EvidenceReviewStatus.allCases, id: \.self) { status in
                            Text(status.displayName).tag(status)
                        }
                    }
                } header: {
                    Text("Review Status")
                }
            }
            .navigationTitle("Boundary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        boundary.lengthM = Double(lengthText)
                        boundary.heightM = Double(heightText)
                        onSave(boundary)
                    }
                }
            }
        }
    }
}

// MARK: - OpeningEditSheet

private struct OpeningEditSheet: View {

    @State private var opening: CapturedOpeningDraft
    let availableBoundaries: [CapturedBoundaryDraft]
    let onSave: (CapturedOpeningDraft) -> Void

    @State private var widthText:  String
    @State private var heightText: String

    init(
        opening: CapturedOpeningDraft,
        availableBoundaries: [CapturedBoundaryDraft],
        onSave: @escaping (CapturedOpeningDraft) -> Void
    ) {
        self.onSave = onSave
        self.availableBoundaries = availableBoundaries
        _opening = State(initialValue: opening)
        _widthText  = State(initialValue: opening.widthM.map  { "\($0)" } ?? "")
        _heightText = State(initialValue: opening.heightM.map { "\($0)" } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $opening.openingType) {
                        ForEach(OpeningType.allCases) { type in
                            Label(type.displayName, systemImage: type.symbolName).tag(type)
                        }
                    }
                } header: {
                    Text("Opening Type")
                }

                Section {
                    HStack {
                        Text("Width (m)")
                        Spacer()
                        TextField("e.g. 0.9", text: $widthText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Height (m)")
                        Spacer()
                        TextField("e.g. 2.0", text: $heightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("Dimensions")
                }

                Section {
                    TextField("e.g. double glazed uPVC", text: Binding(
                        get: { opening.material ?? "" },
                        set: { opening.material = $0.isEmpty ? nil : $0 }
                    ))
                } header: {
                    Text("Material / Glazing")
                }

                if !availableBoundaries.isEmpty {
                    Section {
                        Picker("Linked Boundary", selection: $opening.linkedBoundaryId) {
                            Text("None").tag(Optional<UUID>.none)
                            ForEach(availableBoundaries) { boundary in
                                Text(boundary.boundaryType.displayName).tag(Optional(boundary.id))
                            }
                        }
                    } header: {
                        Text("Linked Boundary")
                    } footer: {
                        Text("Optional — link this opening to the boundary it sits within.")
                            .font(.caption2)
                    }
                }

                Section {
                    Picker("Review Status", selection: $opening.reviewStatus) {
                        ForEach(EvidenceReviewStatus.allCases, id: \.self) { status in
                            Text(status.displayName).tag(status)
                        }
                    }
                } header: {
                    Text("Review Status")
                }
            }
            .navigationTitle("Opening")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        opening.widthM  = Double(widthText)
                        opening.heightM = Double(heightText)
                        onSave(opening)
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    let store = CaptureSessionStore(
        draft: CaptureSessionStore.newSession(visitReference: "PREVIEW-FAB-001")
    )
    NavigationStack {
        FabricCaptureView(store: store)
    }
}
#endif
