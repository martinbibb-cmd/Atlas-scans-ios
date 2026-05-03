import SwiftUI

// MARK: - HazardCaptureView
//
// Hazard observation capture UI.
//
// Lets the engineer record site hazard observations:
//   • Category (asbestos, structural, electrical, gas, water, slip/trip, other)
//   • Severity (low, medium, high, critical)
//   • Title and description
//   • Optional links to photos or object pins
//   • Action required flag
//
// Design rules:
//   • Raw observation only — no risk-assessment score, no action plan.
//   • All items default to .confirmed (manually created).
//   • Completion flags are NOT altered by this view.

struct HazardCaptureView: View {

    @ObservedObject var store: CaptureSessionStore

    @State private var editingHazard: CapturedHazardObservationDraft?
    @State private var showingAddHazard = false

    var body: some View {
        List {
            if store.draft.hazardObservations.isEmpty {
                Section {
                    Label("No hazards recorded. Tap + to add an observation.",
                          systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                }
            } else {
                ForEach(store.draft.hazardObservations) { hazard in
                    hazardRow(hazard)
                }
                .onDelete { indexSet in
                    for idx in indexSet {
                        store.removeHazardObservation(id: store.draft.hazardObservations[idx].id)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Hazard Observations")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddHazard = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddHazard) {
            HazardEditSheet(hazard: CapturedHazardObservationDraft(),
                            availablePhotos: store.draft.photos,
                            availablePins: store.draft.objectPins) { saved in
                store.addHazardObservation(saved)
                showingAddHazard = false
            }
        }
        .sheet(item: $editingHazard) { hazard in
            HazardEditSheet(hazard: hazard,
                            availablePhotos: store.draft.photos,
                            availablePins: store.draft.objectPins) { saved in
                store.updateHazardObservation(saved)
                editingHazard = nil
            }
        }
    }

    // MARK: - Hazard row

    private func hazardRow(_ hazard: CapturedHazardObservationDraft) -> some View {
        Button {
            editingHazard = hazard
        } label: {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: hazard.reviewStatus.symbolName)
                    .foregroundStyle(statusColor(hazard.reviewStatus))
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(hazard.title.isEmpty ? hazard.category.displayName : hazard.title)
                        .font(.subheadline)
                        .foregroundStyle(.primary)

                    HStack(spacing: 6) {
                        Text(hazard.category.displayName)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        severityBadge(hazard.severity)
                    }

                    if hazard.actionRequired {
                        Label("Action required", systemImage: "exclamationmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }

                Spacer()

                Image(systemName: hazard.category.symbolName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                store.removeHazardObservation(id: hazard.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func severityBadge(_ severity: HazardSeverity) -> some View {
        Text(severity.displayName)
            .font(.caption2.bold())
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(severityColor(severity).opacity(0.15))
            .foregroundStyle(severityColor(severity))
            .clipShape(Capsule())
    }

    private func severityColor(_ severity: HazardSeverity) -> Color {
        switch severity {
        case .low:      return .green
        case .medium:   return .yellow
        case .high:     return .orange
        case .critical: return .red
        }
    }

    private func statusColor(_ status: EvidenceReviewStatus) -> Color {
        switch status {
        case .confirmed: return .green
        case .rejected:  return .red
        case .pending:   return .orange
        }
    }
}

// MARK: - HazardEditSheet

private struct HazardEditSheet: View {

    @State private var hazard: CapturedHazardObservationDraft
    let availablePhotos: [CapturedPhotoDraft]
    let availablePins:   [CapturedObjectPinDraft]
    let onSave: (CapturedHazardObservationDraft) -> Void

    init(
        hazard: CapturedHazardObservationDraft,
        availablePhotos: [CapturedPhotoDraft],
        availablePins: [CapturedObjectPinDraft],
        onSave: @escaping (CapturedHazardObservationDraft) -> Void
    ) {
        _hazard = State(initialValue: hazard)
        self.availablePhotos = availablePhotos
        self.availablePins   = availablePins
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                classificationSection
                detailSection
                linksSection
                reviewSection
            }
            .navigationTitle("Hazard Observation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(hazard) }
                        .disabled(hazard.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    // MARK: - Classification

    private var classificationSection: some View {
        Section {
            Picker("Category", selection: $hazard.category) {
                ForEach(HazardCategory.allCases) { cat in
                    Label(cat.displayName, systemImage: cat.symbolName).tag(cat)
                }
            }
            Picker("Severity", selection: $hazard.severity) {
                ForEach(HazardSeverity.allCases) { sev in
                    Text(sev.displayName).tag(sev)
                }
            }
        } header: {
            Text("Classification")
        }
    }

    // MARK: - Detail

    private var detailSection: some View {
        Section {
            TextField("Short title", text: $hazard.title)
            TextField("Description (optional)", text: $hazard.descriptionText, axis: .vertical)
                .lineLimit(3...6)
            Toggle("Action Required", isOn: $hazard.actionRequired)
        } header: {
            Text("Detail")
        } footer: {
            Text("Describe the hazard as observed on site. No risk scoring or remediation advice here.")
                .font(.caption2)
        }
    }

    // MARK: - Links

    private var linksSection: some View {
        Section {
            if availablePhotos.isEmpty {
                Text("No photos captured yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(availablePhotos) { photo in
                    let isLinked = hazard.linkedPhotoIds.contains(photo.id)
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
            Text("Linked Photos (\(hazard.linkedPhotoIds.count))")
        }
    }

    // MARK: - Review

    private var reviewSection: some View {
        Section {
            Picker("Review Status", selection: $hazard.reviewStatus) {
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
        if let idx = hazard.linkedPhotoIds.firstIndex(of: id) {
            hazard.linkedPhotoIds.remove(at: idx)
        } else {
            hazard.linkedPhotoIds.append(id)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    let store = CaptureSessionStore(
        draft: CaptureSessionStore.newSession(visitReference: "PREVIEW-HAZ-001")
    )
    NavigationStack {
        HazardCaptureView(store: store)
    }
}
#endif
