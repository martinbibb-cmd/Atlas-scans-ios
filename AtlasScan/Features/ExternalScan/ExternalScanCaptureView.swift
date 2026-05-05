import SwiftUI

// MARK: - ExternalScanCaptureView
//
// Capture form for a single external area scan.
//
// Sections:
//   Area Details  — label, review status
//   Object Pins   — flue terminal, openings, obstructions, etc.
//   Measurements  — distances between pins
//   Photos        — filename references (camera integration wired separately)
//
// Design rules:
//   • No clearance pass/fail — evidence collection only.
//   • Flue terminal pin is the key anchor; all other pins are contextual.
//   • Measurements link two existing pins by UUID.
//   • The completed draft is returned via the onSave callback; the caller
//     is responsible for appending/replacing it in CaptureSessionDraft.

struct ExternalScanCaptureView: View {

    // MARK: Init

    let existingDraft: ExternalAreaScanDraft?
    let visitId: UUID
    let onSave: (ExternalAreaScanDraft) -> Void

    // MARK: Form state

    @State private var draft: ExternalAreaScanDraft
    @State private var showingAddPin    = false
    @State private var showingAddMeasurement = false
    @State private var addPinType: ExternalObjectType = .flueTerminal
    @State private var addPinLabel: String = ""
    @State private var addMeasurementLabel: String = ""
    @State private var addMeasurementStartPinId: UUID?
    @State private var addMeasurementEndPinId: UUID?
    @State private var addMeasurementLengthText: String = ""

    @Environment(\.dismiss) private var dismiss

    // MARK: Init

    init(
        existingDraft: ExternalAreaScanDraft?,
        visitId: UUID,
        onSave: @escaping (ExternalAreaScanDraft) -> Void
    ) {
        self.existingDraft = existingDraft
        self.visitId = visitId
        self.onSave = onSave
        _draft = State(initialValue: existingDraft ?? {
            var d = ExternalAreaScanDraft()
            d.visitId = visitId
            return d
        }())
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            Form {
                areaDetailsSection
                objectPinsSection
                measurementsSection
            }
            .navigationTitle(existingDraft == nil ? "New External Scan" : "Edit External Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draft)
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showingAddPin) {
                addPinSheet
            }
            .sheet(isPresented: $showingAddMeasurement) {
                addMeasurementSheet
            }
        }
    }

    // MARK: - Area details section

    private var areaDetailsSection: some View {
        Section {
            TextField("Label (e.g. Rear elevation – flue exit)", text: $draft.label)

            Picker("Review Status", selection: $draft.reviewStatus) {
                ForEach(EvidenceReviewStatus.allCases, id: \.self) { status in
                    Text(status.displayName).tag(status)
                }
            }
        } header: {
            Text("Area Details")
        } footer: {
            Text("Mark as Confirmed once you have reviewed the evidence in this area.")
                .font(.caption2)
        }
    }

    // MARK: - Object pins section

    private var objectPinsSection: some View {
        Section {
            ForEach(draft.objectPins) { pin in
                HStack {
                    Image(systemName: ExternalObjectType(rawValue: pin.type.rawValue)?.symbolName ?? "mappin")
                        .foregroundStyle(.secondary)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pin.type.displayName)
                            .font(.body)
                        if let label = pin.label, !label.isEmpty {
                            Text(label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .onDelete { indexSet in
                draft.objectPins.remove(atOffsets: indexSet)
            }

            Button {
                addPinType = .flueTerminal
                addPinLabel = ""
                showingAddPin = true
            } label: {
                Label("Add Object Pin", systemImage: "plus.circle")
            }
        } header: {
            Text("Object Pins")
        } footer: {
            Text("Pin the flue terminal first, then add nearby openings and obstructions.")
                .font(.caption2)
        }
    }

    // MARK: - Measurements section

    private var measurementsSection: some View {
        Section {
            ForEach(draft.measurements) { measurement in
                HStack {
                    Image(systemName: "ruler")
                        .foregroundStyle(.secondary)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(measurement.label.isEmpty ? "Measurement" : measurement.label)
                            .font(.body)
                        if let lengthM = measurement.lengthM {
                            Text(String(format: "%.2f m", lengthM))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .onDelete { indexSet in
                draft.measurements.remove(atOffsets: indexSet)
            }

            Button {
                addMeasurementLabel = ""
                addMeasurementStartPinId = nil
                addMeasurementEndPinId = nil
                addMeasurementLengthText = ""
                showingAddMeasurement = true
            } label: {
                Label("Add Measurement", systemImage: "plus.circle")
            }
        } header: {
            Text("Measurements")
        } footer: {
            Text("Record distances between the flue terminal and nearby openings or boundaries.")
                .font(.caption2)
        }
    }

    // MARK: - Add pin sheet

    private var addPinSheet: some View {
        NavigationStack {
            Form {
                Section("Pin Type") {
                    Picker("Type", selection: $addPinType) {
                        ForEach(ExternalObjectType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.symbolName).tag(type)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }
                Section("Label (optional)") {
                    TextField("e.g. Kitchen window", text: $addPinLabel)
                }
            }
            .navigationTitle("Add Pin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingAddPin = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        var pin = ExternalObjectPinDraft()
                        pin.type = addPinType
                        pin.label = addPinLabel.isEmpty ? nil : addPinLabel
                        draft.objectPins.append(pin)
                        showingAddPin = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Add measurement sheet

    private var addMeasurementSheet: some View {
        NavigationStack {
            Form {
                Section("Label (optional)") {
                    TextField("e.g. Flue → window", text: $addMeasurementLabel)
                }

                Section("Start Pin") {
                    Picker("Start", selection: $addMeasurementStartPinId) {
                        Text("None").tag(UUID?.none)
                        ForEach(draft.objectPins) { pin in
                            Text(pin.type.displayName + (pin.label.map { " – \($0)" } ?? ""))
                                .tag(UUID?.some(pin.id))
                        }
                    }
                }

                Section("End Pin") {
                    Picker("End", selection: $addMeasurementEndPinId) {
                        Text("None").tag(UUID?.none)
                        ForEach(draft.objectPins) { pin in
                            Text(pin.type.displayName + (pin.label.map { " – \($0)" } ?? ""))
                                .tag(UUID?.some(pin.id))
                        }
                    }
                }

                Section("Distance (metres)") {
                    TextField("e.g. 1.5", text: $addMeasurementLengthText)
                        .keyboardType(.decimalPad)
                }
            }
            .navigationTitle("Add Measurement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingAddMeasurement = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        var m = ExternalMeasurementLineDraft()
                        m.label = addMeasurementLabel
                        m.startPinId = addMeasurementStartPinId
                        m.endPinId = addMeasurementEndPinId
                        m.lengthM = Double(addMeasurementLengthText)
                        draft.measurements.append(m)
                        showingAddMeasurement = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    ExternalScanCaptureView(
        existingDraft: nil,
        visitId: UUID()
    ) { _ in }
}
#endif
