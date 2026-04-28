import SwiftUI

// MARK: - EditObjectSheet
//
// Full-screen modal for reviewing and editing an existing tagged service object.

struct EditObjectSheet: View {

    @State private var object: TaggedObject
    let onSave: (TaggedObject) -> Void

    @Environment(\.dismiss) private var dismiss

    // MARK: Local dimension state — kept as Strings for keyboard editing
    @State private var widthText: String = ""
    @State private var depthText: String = ""

    init(object: TaggedObject, onSave: @escaping (TaggedObject) -> Void) {
        _object = State(initialValue: object)
        // Pre-populate dimension strings from existing boundingSize.
        let w = object.boundingSize.map { String(format: "%.2f", $0.widthMetres) } ?? ""
        let d = object.boundingSize.map { String(format: "%.2f", $0.depthMetres) } ?? ""
        _widthText = State(initialValue: w)
        _depthText = State(initialValue: d)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Object") {
                    LabeledContent("Category", value: object.category.displayName)
                    TextField("Label", text: $object.label)
                        .autocorrectionDisabled()
                }

                if !object.category.quickFields.isEmpty {
                    Section("Details") {
                        ForEach(object.category.quickFields) { field in
                            QuickFieldRow(field: field, values: $object.quickFieldValues)
                        }
                    }
                }

                // MARK: Manual dimensions
                Section {
                    HStack {
                        Text("Width")
                        Spacer()
                        TextField("e.g. 0.60", text: $widthText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 100)
                        Text("m")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Depth")
                        Spacer()
                        TextField("e.g. 0.50", text: $depthText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 100)
                        Text("m")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Dimensions")
                } footer: {
                    Text("Physical footprint in metres. Used to draw a correctly-sized object on the layout and refine clearance checks.")
                        .font(.caption2)
                }

                let profiles = ApplianceProfileLibrary.profiles(for: object.category)
                if !profiles.isEmpty {
                    Section {
                        Picker("Profile", selection: Binding(
                            get: { object.applianceProfileID ?? "" },
                            set: { object.applianceProfileID = $0.isEmpty ? nil : $0 }
                        )) {
                            Text("Generic defaults").tag("")
                            ForEach(profiles) { profile in
                                Text(profile.displayName).tag(profile.id)
                            }
                        }
                        .pickerStyle(.menu)

                        if let profileID = object.applianceProfileID,
                           let note = ApplianceProfileLibrary.profile(id: profileID)?.guidanceNote {
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Appliance Profile")
                    } footer: {
                        Text("Profile dimensions refine clearance guidance. Generic defaults apply when no profile is selected.")
                            .font(.caption2)
                    }
                }

                Section("Confidence") {
                    Picker("Confidence", selection: $object.confidence) {
                        ForEach(TaggedObjectConfidenceLevel.allCases, id: \.self) { level in
                            Text(level.displayName).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Toggle("Confirmed", isOn: $object.isConfirmed)
                }

                Section("Notes") {
                    TextField("Optional notes", text: $object.notes, axis: .vertical)
                        .lineLimit(2...6)
                }

                if let pos = object.normalizedPosition {
                    Section("Placement") {
                        Picker("Mode", selection: $object.placementMode) {
                            ForEach(PlacementMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        LabeledContent("Position",
                            value: String(format: "x %.0f%%, y %.0f%%", pos.x * 100, pos.y * 100))
                        if let wallIdx = object.wallIndex {
                            LabeledContent("Wall", value: ScannedWall.displayName(forIndex: wallIdx))
                        }
                    }
                }
            }
            .navigationTitle("Edit Object")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var updated = object
                        // Parse and persist manual dimensions.
                        updated.boundingSize = parsedBoundingSize()
                        updated.touch()
                        onSave(updated)
                    }
                }
            }
        }
    }

    // MARK: - Dimension parsing

    private func parsedBoundingSize() -> PlacementSize? {
        let w = Double(widthText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
        let d = Double(depthText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
        guard let wv = w, wv > 0 else { return nil }
        let dv = d ?? 0
        return PlacementSize(widthMetres: wv, depthMetres: max(0, dv))
    }
}

// MARK: - Previews

#if DEBUG
#Preview {
    EditObjectSheet(object: MockData.livingRoom.taggedObjects[0]) { _ in }
}
#endif
