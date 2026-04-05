import SwiftUI

// MARK: - AddObjectSheet
//
// Full-screen modal for quickly tagging a service object in a room.
// Flow:
//   1. Category picker (grouped tiles with search)
//   2. Placement step — tap the room layout to position the object
//   3. Quick-entry form — label, category-specific fields, confidence, notes

struct AddObjectSheet: View {

    /// Full room object so we can offer the layout placement step.
    let room: ScannedRoom
    let onAdd: (TaggedObject) -> Void

    @Environment(\.dismiss) private var dismiss

    // Step tracking
    private enum Step { case categoryPick, placement, details }
    @State private var step: Step = .categoryPick

    @State private var selectedCategory: ServiceObjectCategory?
    @State private var label = ""
    @State private var notes = ""
    @State private var confidence: ConfidenceLevel = .medium
    @State private var quickValues: [String: String] = [:]
    @State private var searchText = ""

    // Placement state
    @State private var pendingPosition: NormalizedPoint2D? = nil
    @State private var pendingWallIndex: Int? = nil

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .categoryPick:
                    categoryPicker
                case .placement:
                    placementStep
                case .details:
                    quickEntryForm(for: selectedCategory!)
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    backButton
                }
                if step == .details {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") { addObject() }
                    }
                }
                if step == .placement {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Skip") { step = .details }
                    }
                }
            }
        }
    }

    private var navigationTitle: String {
        switch step {
        case .categoryPick: return "Add Service Object"
        case .placement:    return selectedCategory?.displayName ?? "Place Object"
        case .details:      return selectedCategory?.displayName ?? "Object Details"
        }
    }

    @ViewBuilder
    private var backButton: some View {
        switch step {
        case .categoryPick:
            Button("Cancel") { dismiss() }
        case .placement:
            Button("Back") {
                selectedCategory = nil
                pendingPosition = nil
                pendingWallIndex = nil
                step = .categoryPick
            }
        case .details:
            Button("Back") { step = .placement }
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
                        step = .placement
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

    // MARK: - Placement step

    private var placementStep: some View {
        VStack(spacing: 0) {
            if let category = selectedCategory {
                RoomLayoutPlacementView(room: room, category: category) { position, wallIdx in
                    pendingPosition = position
                    pendingWallIndex = wallIdx
                    step = .details
                }
            }
        }
    }

    // MARK: - Quick-entry form

    private func quickEntryForm(for category: ServiceObjectCategory) -> some View {
        Form {
            // Placement summary
            if let pos = pendingPosition {
                Section("Placement") {
                    LabeledContent("Mode", value: category.defaultPlacementMode.displayName)
                    LabeledContent("Position",
                        value: String(format: "x %.0f%%, y %.0f%%", pos.x * 100, pos.y * 100))
                    if let wallIdx = pendingWallIndex {
                        LabeledContent("Wall", value: ScannedWall.displayName(forIndex: wallIdx))
                    }
                }
            }

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
        var object = TaggedObject(
            roomID: room.id,
            category: category,
            label: label.trimmingCharacters(in: .whitespaces),
            wallIndex: pendingWallIndex,
            quickFieldValues: quickValues,
            notes: notes,
            confidence: confidence
        )
        if let pos = pendingPosition {
            PlacementService.place(object: &object, at: pos, in: room)
        }
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
    AddObjectSheet(room: MockData.livingRoom) { _ in }
}
#endif
