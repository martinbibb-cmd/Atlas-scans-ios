import SwiftUI

// MARK: - QuotePlannerCaptureView
//
// Quote-planner anchor capture UI.
//
// Lets the engineer tag candidate install/service locations during a visit:
//   • Kind (existing_boiler, proposed_boiler, gas_meter, …)
//   • Optional free-text label
//   • Optional links to photos or object pins
//   • Provenance (how the anchor was placed)
//
// Design rules:
//   • Raw observation only — no pricing, no scope, no recommendations.
//   • All items default to .confirmed (manually created).
//   • Completion flags are NOT altered by this view.
//   • Atlas Mind owns all interpretation downstream.

struct QuotePlannerCaptureView: View {

    @ObservedObject var store: CaptureSessionStore

    @State private var editingAnchor: CapturedQuotePlannerAnchorDraft?
    @State private var showingAddAnchor = false

    var body: some View {
        List {
            if store.draft.quotePlannerAnchors.isEmpty {
                Section {
                    Label("No quote points recorded. Tap + to add an anchor.",
                          systemImage: "mappin.and.ellipse")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                }
            } else {
                ForEach(store.draft.quotePlannerAnchors) { anchor in
                    anchorRow(anchor)
                }
                .onDelete { indexSet in
                    for idx in indexSet {
                        store.removeQuotePlannerAnchor(id: store.draft.quotePlannerAnchors[idx].id)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Quote Points")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddAnchor = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddAnchor) {
            QuotePlannerAnchorEditSheet(
                anchor: CapturedQuotePlannerAnchorDraft(),
                availablePhotos: store.draft.photos,
                availablePins: store.draft.objectPins
            ) { saved in
                store.addQuotePlannerAnchor(saved)
                showingAddAnchor = false
            }
        }
        .sheet(item: $editingAnchor) { anchor in
            QuotePlannerAnchorEditSheet(
                anchor: anchor,
                availablePhotos: store.draft.photos,
                availablePins: store.draft.objectPins
            ) { saved in
                store.updateQuotePlannerAnchor(saved)
                editingAnchor = nil
            }
        }
    }

    // MARK: - Anchor row

    private func anchorRow(_ anchor: CapturedQuotePlannerAnchorDraft) -> some View {
        Button {
            editingAnchor = anchor
        } label: {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: anchor.reviewStatus.symbolName)
                    .foregroundStyle(statusColor(anchor.reviewStatus))
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(anchor.label ?? anchor.kind.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.primary)

                    HStack(spacing: 6) {
                        Text(anchor.kind.displayName)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        provenanceBadge(anchor.provenance)
                    }
                }

                Spacer()

                Image(systemName: anchor.kind.symbolName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                store.removeQuotePlannerAnchor(id: anchor.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func provenanceBadge(_ provenance: QuoteAnchorProvenance) -> some View {
        Text(provenance.displayName)
            .font(.caption2.bold())
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.12))
            .foregroundStyle(Color.accentColor)
            .clipShape(Capsule())
    }

    private func statusColor(_ status: EvidenceReviewStatus) -> Color {
        switch status {
        case .confirmed: return .green
        case .rejected:  return .red
        case .pending:   return .orange
        }
    }
}

// MARK: - QuotePlannerAnchorEditSheet

private struct QuotePlannerAnchorEditSheet: View {

    @Environment(\.dismiss) private var dismiss
    @State private var anchor: CapturedQuotePlannerAnchorDraft
    let availablePhotos: [CapturedPhotoDraft]
    let availablePins:   [CapturedObjectPinDraft]
    let onSave: (CapturedQuotePlannerAnchorDraft) -> Void

    init(
        anchor: CapturedQuotePlannerAnchorDraft,
        availablePhotos: [CapturedPhotoDraft],
        availablePins: [CapturedObjectPinDraft],
        onSave: @escaping (CapturedQuotePlannerAnchorDraft) -> Void
    ) {
        _anchor = State(initialValue: anchor)
        self.availablePhotos = availablePhotos
        self.availablePins   = availablePins
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                kindSection
                detailSection
                provenanceSection
                photoLinksSection
                pinLinksSection
                reviewSection
            }
            .navigationTitle("Quote Point")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(anchor) }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Kind

    private var kindSection: some View {
        Section {
            Picker("Kind", selection: $anchor.kind) {
                ForEach(QuoteAnchorKind.allCases) { kind in
                    Label(kind.displayName, systemImage: kind.symbolName).tag(kind)
                }
            }
        } header: {
            Text("Anchor Type")
        }
    }

    // MARK: - Detail

    private var detailSection: some View {
        Section {
            TextField("Label (optional)", text: Binding(
                get: { anchor.label ?? "" },
                set: { anchor.label = $0.isEmpty ? nil : $0 }
            ))
        } header: {
            Text("Label")
        } footer: {
            Text("Optionally describe this specific location (e.g. \"Kitchen boiler\").")
                .font(.caption2)
        }
    }

    // MARK: - Provenance

    private var provenanceSection: some View {
        Section {
            Picker("Placed via", selection: $anchor.provenance) {
                ForEach(QuoteAnchorProvenance.allCases) { provenance in
                    Text(provenance.displayName).tag(provenance)
                }
            }
        } header: {
            Text("Provenance")
        } footer: {
            Text("How this anchor was placed determines its default confidence for Atlas Mind.")
                .font(.caption2)
        }
    }

    // MARK: - Photo links

    private var photoLinksSection: some View {
        Section {
            if availablePhotos.isEmpty {
                Text("No photos captured yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(availablePhotos) { photo in
                    let isLinked = anchor.linkedPhotoIds.contains(photo.id)
                    Button {
                        togglePhotoLink(photo.id)
                    } label: {
                        HStack {
                            Text(photo.kind.displayName)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            Spacer()
                            if isLinked {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text("Linked Photos (\(anchor.linkedPhotoIds.count))")
        }
    }

    // MARK: - Pin links

    private var pinLinksSection: some View {
        Section {
            if availablePins.isEmpty {
                Text("No object pins captured yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(availablePins) { pin in
                    let isLinked = anchor.linkedObjectPinIds.contains(pin.id)
                    Button {
                        togglePinLink(pin.id)
                    } label: {
                        HStack {
                            Label(pin.label ?? pin.type.displayName,
                                  systemImage: pin.type.symbolName)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            Spacer()
                            if isLinked {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text("Linked Object Pins (\(anchor.linkedObjectPinIds.count))")
        }
    }

    // MARK: - Review

    private var reviewSection: some View {
        Section {
            Picker("Review Status", selection: $anchor.reviewStatus) {
                ForEach(EvidenceReviewStatus.allCases, id: \.self) { status in
                    Text(status.displayName).tag(status)
                }
            }
        } header: {
            Text("Review Status")
        }
    }

    // MARK: - Helpers

    private func togglePhotoLink(_ id: UUID) {
        if let idx = anchor.linkedPhotoIds.firstIndex(of: id) {
            anchor.linkedPhotoIds.remove(at: idx)
        } else {
            anchor.linkedPhotoIds.append(id)
        }
    }

    private func togglePinLink(_ id: UUID) {
        if let idx = anchor.linkedObjectPinIds.firstIndex(of: id) {
            anchor.linkedObjectPinIds.remove(at: idx)
        } else {
            anchor.linkedObjectPinIds.append(id)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    let store = CaptureSessionStore(
        draft: CaptureSessionStore.newSession(visitReference: "PREVIEW-QP-001")
    )
    NavigationStack {
        QuotePlannerCaptureView(store: store)
    }
}
#endif
