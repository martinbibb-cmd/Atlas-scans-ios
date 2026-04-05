import SwiftUI

// MARK: - EditObjectSheet
//
// Full-screen modal for reviewing and editing an existing tagged service object.

struct EditObjectSheet: View {

    @State private var object: TaggedObject
    let onSave: (TaggedObject) -> Void

    @Environment(\.dismiss) private var dismiss

    init(object: TaggedObject, onSave: @escaping (TaggedObject) -> Void) {
        _object = State(initialValue: object)
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

                Section("Confidence") {
                    Picker("Confidence", selection: $object.confidence) {
                        ForEach(ConfidenceLevel.allCases, id: \.self) { level in
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
                            LabeledContent("Attached wall", value: "Wall \(wallIdx + 1)")
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
                        updated.touch()
                        onSave(updated)
                    }
                }
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview {
    EditObjectSheet(object: MockData.livingRoom.taggedObjects[0]) { _ in }
}
#endif
