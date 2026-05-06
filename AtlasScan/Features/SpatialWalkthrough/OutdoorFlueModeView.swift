import SwiftUI

// MARK: - AreaIndex

private struct AreaIndex: Identifiable {
    let value: Int
    var id: Int { value }
}

// MARK: - OutdoorFlueModeView
//
// Dedicated capture flow for external flue terminal clearance evidence.
//
// Workflow:
//   1. The engineer selects or creates the "Outdoor Flue Area" scan record.
//   2. They pin the "Flue Terminal" on the elevation.
//   3. They pin "Nearby Features" (windows, doors, air bricks, etc.).
//   4. The app calculates the 3-D distance from the flue terminal to each
//      nearby feature using the normalised coordinate positions of the pins.
//   5. A distance table is shown; any measurement below the regulatory
//      minimum (600 mm for most gas boilers) raises a QAFlag.
//
// Data model:
//   Captures evidence into ExternalAreaScanDraft (existing contract).
//   Distance calculations are advisory — Atlas Mind owns clearance rules.

struct OutdoorFlueModeView: View {

    // MARK: - Dependencies

    @ObservedObject var store: CaptureSessionStore
    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    @State private var label: String = "Flue Terminal Exit"
    @State private var showingCaptureSheet = false
    @State private var editingAreaIndex: AreaIndex?
    @State private var showingAddFeature   = false
    @State private var newFeatureLabel     = ""
    @State private var selectedAreaIndex: AreaIndex?

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                modeIntroSection
                areaListSection
                addAreaSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Outdoor Flue Mode")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showingCaptureSheet) {
                ExternalScanCaptureView(
                    existingDraft: nil,
                    visitId: store.draft.id
                ) { newArea in
                    store.update { $0.externalAreaScans.append(newArea) }
                    showingCaptureSheet = false
                }
            }
            .sheet(item: $editingAreaIndex) { areaIndex in
                ExternalScanCaptureView(
                    existingDraft: store.draft.externalAreaScans[areaIndex.value],
                    visitId: store.draft.id
                ) { updated in
                    store.update { $0.externalAreaScans[areaIndex.value] = updated }
                    editingAreaIndex = nil
                }
            }
            .sheet(item: $selectedAreaIndex) { areaIndex in
                flueDistanceSheet(for: areaIndex.value)
            }
        }
    }

    // MARK: - Mode intro

    private var modeIntroSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "arrow.up.to.line.circle.fill")
                    .font(.title)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Outdoor Flue Mode")
                        .font(.headline)
                    Text("Pin the flue terminal exit and nearby windows, doors, and openings. The app measures 3-D distances automatically using pinned positions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Area list

    private var areaListSection: some View {
        Section {
            if store.draft.externalAreaScans.isEmpty {
                ContentUnavailableView(
                    "No Flue Areas Recorded",
                    systemImage: "binoculars",
                    description: Text("Tap 'Add Flue Area' below to start recording the exterior elevation.")
                )
            } else {
                ForEach(store.draft.externalAreaScans.indices, id: \.self) { index in
                    areaRow(store.draft.externalAreaScans[index], at: index)
                }
                .onDelete { indexSet in
                    store.update { $0.externalAreaScans.remove(atOffsets: indexSet) }
                }
            }
        } header: {
            Text("Recorded Flue Areas")
        }
    }

    private func areaRow(_ area: ExternalAreaScanDraft, at index: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "binoculars")
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(area.label.isEmpty ? "Unlabelled Area" : area.label)
                    .font(.body)
                Text("\(area.objectPins.count) pin(s) · \(area.measurements.count) measurement(s)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                Button {
                    selectedAreaIndex = AreaIndex(value: index)
                } label: {
                    Image(systemName: "ruler")
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)

                Button {
                    editingAreaIndex = AreaIndex(value: index)
                } label: {
                    Image(systemName: "pencil.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Add area section

    private var addAreaSection: some View {
        Section {
            Button {
                showingCaptureSheet = true
            } label: {
                Label("Add Flue Area", systemImage: "plus.circle")
                    .fontWeight(.semibold)
            }
        } footer: {
            Text("Record each exterior elevation separately. Typical: rear elevation for condensate/flue exit, front elevation for gas meter.")
                .font(.caption2)
        }
    }

    // MARK: - Flue distance sheet

    private func flueDistanceSheet(for index: Int) -> some View {
        let area = store.draft.externalAreaScans[index]
        return NavigationStack {
            FlueDistanceReportView(area: area)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { selectedAreaIndex = nil }
                    }
                }
        }
    }
}

// MARK: - FlueDistanceReportView
//
// Shows calculated distances from the Flue Terminal pin to each
// Nearby Feature pin within an ExternalAreaScanDraft.

struct FlueDistanceReportView: View {

    let area: ExternalAreaScanDraft

    /// Regulatory minimum clearance from flue terminal to an opening (mm).
    static let minimumClearanceMM: Double = 600

    var body: some View {
        List {
            headerSection
            if distances.isEmpty {
                Section {
                    Text("Pin the Flue Terminal and at least one Nearby Feature to see distance calculations.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                distancesSection
            }
            disclaimerSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Flue Distances")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "arrow.up.to.line.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(area.label.isEmpty ? "Flue Area" : area.label)
                        .font(.headline)
                    Text("\(area.objectPins.count) pin(s) recorded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var distancesSection: some View {
        Section("Calculated Distances") {
            ForEach(distances, id: \.id) { row in
                HStack(spacing: 12) {
                    Image(systemName: row.pass
                          ? "checkmark.circle.fill"
                          : "exclamationmark.triangle.fill")
                        .foregroundStyle(row.pass ? .green : .red)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Flue → \(row.featureLabel)")
                            .font(.subheadline)
                        if row.pass {
                            Text("Appears clear (≥ 600 mm)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("May be too close (< 600 mm) — verify on site")
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                    }
                    Spacer()
                    Text(String(format: "%.0f mm", row.distanceMM))
                        .font(.body.monospacedDigit().bold())
                        .foregroundStyle(row.pass ? .primary : .red)
                }
            }
        }
    }

    private var disclaimerSection: some View {
        Section {
            Text("Distances are estimated from pin positions captured during the visit. Verify all clearances against the manufacturer's installation instructions and current Gas Safe / MCS guidance.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Distance calculation

    private struct DistanceRow: Identifiable {
        let id: UUID
        let featureLabel: String
        let distanceMM: Double
        let pass: Bool
    }

    private var distances: [DistanceRow] {
        guard let fluePin = area.objectPins.first(where: { $0.type == .flueTerminal })
        else { return [] }

        return area.objectPins
            .filter { $0.type != .flueTerminal }
            .compactMap { feature -> DistanceRow? in
                guard let fx = fluePin.approximatePositionX,
                      let fy = fluePin.approximatePositionY,
                      let fz = fluePin.approximatePositionZ,
                      let ex = feature.approximatePositionX,
                      let ey = feature.approximatePositionY,
                      let ez = feature.approximatePositionZ
                else { return nil }

                let dx = fx - ex
                let dy = fy - ey
                let dz = fz - ez
                let distM = sqrt(dx * dx + dy * dy + dz * dz)
                let distMM = distM * 1000
                return DistanceRow(
                    id: UUID(),
                    featureLabel: feature.label ?? "Nearby Feature",
                    distanceMM: distMM,
                    pass: distMM >= FlueDistanceReportView.minimumClearanceMM
                )
            }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    let store = CaptureSessionStore(
        draft: CaptureSessionStore.newSession(visitReference: "PREVIEW-FLUE"),
        persistence: .shared
    )
    return OutdoorFlueModeView(store: store)
}
#endif
