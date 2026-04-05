import SwiftUI

// MARK: - AddObjectSheet
//
// Full-screen modal for quickly tagging a service object in a room.
// Shows category tiles grouped by function, then a quick-entry form.

struct AddObjectSheet: View {

    let roomID: UUID
    let onAdd: (TaggedObject) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var selectedCategory: ServiceObjectCategory?
    @State private var label = ""
    @State private var notes = ""
    @State private var confidence: ConfidenceLevel = .medium
    @State private var quickValues: [String: String] = [:]
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            Group {
                if let category = selectedCategory {
                    quickEntryForm(for: category)
                } else {
                    categoryPicker
                }
            }
            .navigationTitle(selectedCategory == nil ? "Add Service Object" : selectedCategory!.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if selectedCategory != nil {
                        Button("Back") { selectedCategory = nil }
                    } else {
                        Button("Cancel") { dismiss() }
                    }
                }
                if selectedCategory != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") { addObject() }
                    }
                }
            }
        }
    }

    // MARK: - Category picker

    private var categoryPicker: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24, pinnedViews: .sectionHeaders) {
                ForEach(groupedCategories, id: \.0) { groupName, categories in
                    categoryGroup(name: groupName, categories: categories)
                }
            }
            .padding()
        }
        .searchable(text: $searchText, prompt: "Search objects…")
    }

    private func categoryGroup(name: String, categories: [ServiceObjectCategory]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(name)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            LazyVGrid(columns: gridColumns, spacing: 10) {
                ForEach(categories) { category in
                    CategoryTile(category: category) {
                        selectedCategory = category
                        label = category.displayName
                    }
                }
            }
        }
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 100, maximum: 140), spacing: 10)]
    }

    private var groupedCategories: [(String, [ServiceObjectCategory])] {
        let filtered = searchText.isEmpty
            ? ServiceObjectCategory.allCases
            : ServiceObjectCategory.allCases.filter {
                $0.displayName.localizedCaseInsensitiveContains(searchText)
                || $0.groupName.localizedCaseInsensitiveContains(searchText)
            }

        var groups: [(String, [ServiceObjectCategory])] = []
        var seen = Set<String>()

        for cat in filtered {
            let group = cat.groupName
            if !seen.contains(group) {
                seen.insert(group)
                groups.append((group, filtered.filter { $0.groupName == group }))
            }
        }
        return groups
    }

    // MARK: - Quick-entry form

    private func quickEntryForm(for category: ServiceObjectCategory) -> some View {
        Form {
            Section("Label") {
                TextField("Label", text: $label)
                    .autocorrectionDisabled()
            }

            if !category.quickFields.isEmpty {
                Section("Quick Details") {
                    ForEach(category.quickFields) { field in
                        QuickFieldRow(field: field, values: $quickValues)
                    }
                }
            }

            Section("Confidence") {
                Picker("Confidence", selection: $confidence) {
                    ForEach(ConfidenceLevel.allCases, id: \.self) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Notes") {
                TextField("Optional notes", text: $notes, axis: .vertical)
                    .lineLimit(2...4)
            }
        }
    }

    // MARK: - Add action

    private func addObject() {
        guard let category = selectedCategory else { return }
        let object = TaggedObject(
            roomID: roomID,
            category: category,
            label: label.trimmingCharacters(in: .whitespaces),
            quickFieldValues: quickValues,
            notes: notes,
            confidence: confidence
        )
        onAdd(object)
        dismiss()
    }
}

// MARK: - CategoryTile

struct CategoryTile: View {
    let category: ServiceObjectCategory
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: category.symbolName)
                    .font(.title2)
                    .frame(width: 44, height: 44)
                    .foregroundStyle(.white)
                    .background(tileColor)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                Text(category.displayName)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(.secondarySystemBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var tileColor: Color {
        switch category.groupName {
        case "Heat Source / Plant":     return .orange
        case "Emitters":                return .red
        case "Services / Utilities":    return .blue
        case "Controls":                return .purple
        case "Structural / Siting":     return .gray
        default:                        return Color(.systemGray3)
        }
    }
}

// MARK: - QuickFieldRow

struct QuickFieldRow: View {
    let field: QuickField
    @Binding var values: [String: String]

    private var binding: Binding<String> {
        Binding(
            get: { values[field.key] ?? "" },
            set: { values[field.key] = $0 }
        )
    }

    var body: some View {
        switch field.inputKind {
        case .text:
            HStack {
                Text(field.label)
                Spacer()
                TextField("Optional", text: binding)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 160)
                    .autocorrectionDisabled()
            }

        case .boolean:
            let boolBinding = Binding<Bool>(
                get: { values[field.key] == "true" },
                set: { values[field.key] = $0 ? "true" : "false" }
            )
            Toggle(field.label, isOn: boolBinding)

        case .choice(let options):
            Picker(field.label, selection: binding) {
                Text("Not set").tag("")
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
        }
    }
}

// MARK: - Extension for background

private extension Color {
    static var secondarySystemBackground: Color {
        Color(uiColor: .secondarySystemBackground)
    }
}

// MARK: - Previews

#if DEBUG
#Preview {
    AddObjectSheet(roomID: UUID()) { _ in }
}
#endif
