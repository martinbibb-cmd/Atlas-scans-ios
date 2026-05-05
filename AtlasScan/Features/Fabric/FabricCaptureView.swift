import SwiftUI

// MARK: - FabricCaptureView
//
// Fabric & perimeter review UI.
//
// Design: "confirm what the scan found; add only what is missing."
//
//   • Opening this screen for a scanned room shows detected walls automatically.
//   • Non-internal walls default to external.
//   • Engineer reviews and confirms each wall, sets construction type, and can
//     mark an external wall as party where applicable.
//   • Openings detected from the scan appear without pressing Add Opening.
//   • The primary manual action is "Add missed opening" — not "Add Opening".
//
// Rules:
//   • Raw observation only — no heat-loss calculation, no U-values.
//   • Readiness completion flags are NOT altered by this view.

struct FabricCaptureView: View {

    @ObservedObject var store: CaptureSessionStore

    @State private var showingAddRecord = false
    @State private var reviewingRecord: CapturedFloorPlanFabricDraft?

    var body: some View {
        List {
            if store.draft.fabricRecords.isEmpty {
                emptyState
            } else {
                ForEach(store.draft.fabricRecords) { record in
                    fabricRecordSection(record)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Fabric Review")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    addFabricRecord()
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $reviewingRecord) { record in
            FabricWallReviewView(store: store, record: record)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        Section {
            VStack(spacing: 8) {
                Image(systemName: "square.3.layers.3d")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text("No fabric review records")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Tap + to add a room. Walls will be derived from the scan automatically.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    // MARK: - Per-record section

    @ViewBuilder
    private func fabricRecordSection(_ record: CapturedFloorPlanFabricDraft) -> some View {
        let roomName = roomLabel(for: record.roomId) ?? "Unlinked room"
        let pendingCount = record.boundaries.filter { $0.reviewStatus == .pending }.count
        let openingCount = record.openings.count

        Section {
            Button {
                reviewingRecord = record
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("\(record.boundaries.count) wall\(record.boundaries.count == 1 ? "" : "s")")
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            if pendingCount > 0 {
                                Text("\(pendingCount) pending")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 5).padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.15))
                                    .foregroundStyle(.orange)
                                    .clipShape(Capsule())
                            }
                        }
                        Text("\(openingCount) opening\(openingCount == 1 ? "" : "s") recorded")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label("Review walls", systemImage: "chevron.right")
                        .font(.caption)
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
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

    // MARK: - Helpers

    private func roomLabel(for roomId: UUID?) -> String? {
        guard let roomId else { return nil }
        return store.draft.roomScans.first(where: { $0.id == roomId })?.roomLabel
    }

    /// Creates a new fabric record and auto-populates walls from the scan.
    private func addFabricRecord() {
        var newRecord = CapturedFloorPlanFabricDraft()

        // Pre-link to the first unlinked room scan.
        let unlinkedScans = store.draft.roomScans.filter { scan in
            !store.draft.fabricRecords.contains { $0.roomId == scan.id }
        }
        if let firstUnlinked = unlinkedScans.first {
            newRecord.roomId = firstUnlinked.id
            newRecord.applyDerivedWalls(from: firstUnlinked)
        }

        store.addFabricRecord(newRecord)
        reviewingRecord = newRecord
    }
}

// MARK: - FabricWallReviewView

/// Wall-by-wall review of fabric evidence for a single scanned room.
///
/// Replaces the old blank-form "add boundary" approach with a review-first
/// workflow: scan-derived walls are shown immediately; the engineer confirms,
/// edits types/materials, or marks party walls.
private struct FabricWallReviewView: View {

    @ObservedObject var store: CaptureSessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var localRecord: CapturedFloorPlanFabricDraft
    @State private var editingBoundary: CapturedBoundaryDraft?
    @State private var showingAddOpening = false
    @State private var editingOpening: CapturedOpeningDraft?

    init(store: CaptureSessionStore, record: CapturedFloorPlanFabricDraft) {
        self.store = store
        _localRecord = State(initialValue: record)
    }

    private var roomScan: CapturedRoomScanDraft? {
        guard let id = localRecord.roomId else { return nil }
        return store.draft.roomScans.first(where: { $0.id == id })
    }

    private var screenTitle: String {
        let name = roomScan?.roomLabel ?? "Room"
        return "\(name) Fabric Review"
    }

    var body: some View {
        NavigationStack {
            List {
                roomSummarySection
                wallsSection
                openingsSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle(screenTitle)
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
            .sheet(item: $editingBoundary) { boundary in
                BoundaryEditSheet(boundary: boundary) { saved in
                    if let idx = localRecord.boundaries.firstIndex(where: { $0.id == saved.id }) {
                        localRecord.boundaries[idx] = saved
                    }
                    editingBoundary = nil
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

    // MARK: - Room summary

    private var roomSummarySection: some View {
        Section {
            if let scan = roomScan {
                if let w = scan.rawWidthM, let d = scan.rawDepthM {
                    HStack {
                        Text("Dimensions")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.1f × %.1f m", w, d))
                    }
                }
                if let h = scan.rawHeightM {
                    HStack {
                        Text("Ceiling height")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.2f m", h))
                    }
                }
            }

            Picker("Room", selection: $localRecord.roomId) {
                Text("None").tag(Optional<UUID>.none)
                ForEach(store.draft.roomScans) { scan in
                    Text(scan.roomLabel ?? "Unnamed Room").tag(Optional(scan.id))
                }
            }
            .onChange(of: localRecord.roomId) { _, newId in
                applyDerivedWallsIfNeeded(for: newId)
            }
        } header: {
            Text("Room")
        } footer: {
            if localRecord.boundaries.isEmpty && localRecord.roomId == nil {
                Text("Link a room to auto-derive walls from the scan geometry.")
                    .font(.caption2)
            }
        }
    }

    /// Derives walls from the newly selected room scan when no walls exist yet.
    private func applyDerivedWallsIfNeeded(for roomId: UUID?) {
        guard let id = roomId,
              let scan = store.draft.roomScans.first(where: { $0.id == id }) else { return }
        localRecord.applyDerivedWalls(from: scan)
    }

    // MARK: - Walls section

    private var wallsSection: some View {
        Section {
            if localRecord.boundaries.isEmpty {
                Text("No walls derived yet. Link a scanned room above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach($localRecord.boundaries) { $boundary in
                    wallCard(boundary: $boundary)
                }
                .onDelete { indexSet in
                    localRecord.boundaries.remove(atOffsets: indexSet)
                }
            }
        } header: {
            Text("Walls (\(localRecord.boundaries.count))")
        } footer: {
            Text("All non-internal walls default to external. Review each wall and confirm its type.")
                .font(.caption2)
        }
    }

    @ViewBuilder
    private func wallCard(boundary: Binding<CapturedBoundaryDraft>) -> some View {
        let b = boundary.wrappedValue
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Wall label
                Text(b.wallDisplayLabel)
                    .font(.subheadline.bold())
                Spacer()
                // Source badge
                if b.source == .scanDerived {
                    Text("scan")
                        .font(.caption2)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color.blue.opacity(0.12))
                        .foregroundStyle(.blue)
                        .clipShape(Capsule())
                }
                // Review status
                Image(systemName: b.reviewStatus.symbolName)
                    .foregroundStyle(reviewStatusColor(b.reviewStatus))
            }

            // Type row with quick-change buttons
            HStack(spacing: 6) {
                typeBadge(b.boundaryType)
                Spacer()
                if b.boundaryType != .internal {
                    Button {
                        boundary.wrappedValue.boundaryType = .party
                        boundary.wrappedValue.reviewStatus = .confirmed
                    } label: {
                        Text("Party")
                            .font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(b.boundaryType == .party ? Color.purple : Color.secondary.opacity(0.15))
                            .foregroundStyle(b.boundaryType == .party ? Color.white : Color.secondary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    boundary.wrappedValue.boundaryType = .internal
                    boundary.wrappedValue.reviewStatus = .confirmed
                } label: {
                    Text("Internal")
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(b.boundaryType == .internal ? Color.teal : Color.secondary.opacity(0.15))
                        .foregroundStyle(b.boundaryType == .internal ? Color.white : Color.secondary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            // Construction type + dimensions
            HStack(spacing: 12) {
                if b.constructionType != .unknown {
                    Label(b.constructionType.displayName, systemImage: "building.2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let len = b.lengthM {
                    Text(String(format: "%.1f m", len))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let h = b.heightM {
                    Text(String(format: "× %.2f m", h))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Openings on this wall
            let wallOpenings = localRecord.openings.filter { $0.linkedBoundaryId == b.id }
            if !wallOpenings.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "window.casement")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(wallOpenings.count) opening\(wallOpenings.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Action row
            HStack(spacing: 10) {
                if b.reviewStatus == .pending {
                    Button {
                        boundary.wrappedValue.reviewStatus = .confirmed
                    } label: {
                        Label("Confirm", systemImage: "checkmark.circle")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                }

                Button {
                    editingBoundary = b
                } label: {
                    Label("Edit", systemImage: "pencil")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Spacer()
            }
        }
        .padding(.vertical, 4)
    }

    private func typeBadge(_ type: BoundaryType) -> some View {
        Label(type.displayName, systemImage: type.symbolName)
            .font(.caption2.bold())
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(typeColor(type).opacity(0.15))
            .foregroundStyle(typeColor(type))
            .clipShape(Capsule())
    }

    private func typeColor(_ type: BoundaryType) -> Color {
        switch type {
        case .external: return .orange
        case .internal: return .teal
        case .party:    return .purple
        case .unknown:  return .secondary
        }
    }

    // MARK: - Openings section

    private var openingsSection: some View {
        Section {
            if localRecord.openings.isEmpty {
                Text("No openings recorded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(localRecord.openings) { opening in
                    Button {
                        editingOpening = opening
                    } label: {
                        openingRow(opening)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { indexSet in
                    localRecord.openings.remove(atOffsets: indexSet)
                }
            }

            Button {
                showingAddOpening = true
            } label: {
                Label("Add missed opening", systemImage: "plus.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Openings (\(localRecord.openings.count))")
        } footer: {
            Text("Openings detected by the scan appear here automatically. Use \"Add missed opening\" only when the scan failed to detect one.")
                .font(.caption2)
        }
    }

    private func openingRow(_ opening: CapturedOpeningDraft) -> some View {
        HStack {
            Image(systemName: reviewStatusSymbol(opening.reviewStatus))
                .foregroundStyle(reviewStatusColor(opening.reviewStatus))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(opening.openingType.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                HStack(spacing: 8) {
                    if let w = opening.widthM {
                        Text(String(format: "%.2f m wide", w))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if opening.source == .scanDerived {
                        Text("scan")
                            .font(.caption2)
                            .padding(.horizontal, 4).padding(.vertical, 2)
                            .background(Color.blue.opacity(0.12))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                    if let wallId = opening.linkedBoundaryId,
                       let wall = localRecord.boundaries.first(where: { $0.id == wallId }) {
                        Text(wall.wallDisplayLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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

    private func reviewStatusSymbol(_ status: EvidenceReviewStatus) -> String { status.symbolName }

    private func reviewStatusColor(_ status: EvidenceReviewStatus) -> Color {
        switch status {
        case .confirmed: return .green
        case .rejected:  return .red
        case .pending:   return .orange
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
                    Picker("Boundary Type", selection: $boundary.boundaryType) {
                        ForEach(BoundaryType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                } header: {
                    Text("Boundary Type")
                }

                Section {
                    Picker("Construction / Fabric", selection: $boundary.constructionType) {
                        ForEach(WallConstructionType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    TextField("Free-text material note", text: Binding(
                        get: { boundary.material ?? "" },
                        set: { boundary.material = $0.isEmpty ? nil : $0 }
                    ))
                } header: {
                    Text("Construction Type")
                } footer: {
                    Text("Select the closest construction type. Add a free-text note only if more detail is needed.")
                        .font(.caption2)
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
                    Picker("Review Status", selection: $boundary.reviewStatus) {
                        ForEach(EvidenceReviewStatus.allCases, id: \.self) { status in
                            Text(status.displayName).tag(status)
                        }
                    }
                } header: {
                    Text("Review Status")
                }
            }
            .navigationTitle("Edit Wall")
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

                Section {
                    Picker("Wall", selection: $opening.linkedBoundaryId) {
                        Text("None").tag(Optional<UUID>.none)
                        ForEach(availableBoundaries) { boundary in
                            Text(boundary.wallDisplayLabel).tag(Optional(boundary.id))
                        }
                    }
                } header: {
                    Text("Linked Wall")
                } footer: {
                    Text("Link this opening to the wall it sits within.")
                        .font(.caption2)
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
