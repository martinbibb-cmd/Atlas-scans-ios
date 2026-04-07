import SwiftUI

// MARK: - LiveViewTaggingView
//
// Full-screen camera view that lets engineers place spatial object tags
// directly in the live camera feed — the "scan rooms, tap radiators" experience.
//
// Workflow:
//   1. Engineer walks into a room; the camera feed fills the screen.
//   2. Tap anywhere on the screen where an object is visible.
//      → LiveCategoryPickerSheet appears (mid-height).
//   3. Select the object type (radiator, boiler, cylinder, flue, other…).
//      → A pin appears at the tap position.  Phase advances to .objectSelected.
//   4. The bottom panel shows the selected object's name + action buttons:
//        • Camera — attach a photo directly to this object.
//        • Edit    — relabel / recategorise / change confidence.
//        • Trash   — remove the tag.
//   5. Tap × in the panel or tap empty space to deselect.
//   6. Continue walking; all pins remain visible for the session.
//   7. Tap × in the top-left corner to dismiss back to the session list.
//
// State is managed by LiveViewTaggingViewModel.  All object mutations pass through
// the wrapped SessionCaptureViewModel so autosave and Atlas sync remain intact.

struct LiveViewTaggingView: View {

    @ObservedObject var viewModel: LiveViewTaggingViewModel
    @Environment(\.dismiss) private var dismiss

    // MARK: Local sheet / overlay state

    /// Captured at the moment a tap triggers category selection so the position
    /// is stable for the duration of the sheet presentation.
    @State private var isPresentingCategoryPicker = false
    @State private var categoryPickerPosition = NormalizedPoint2D(x: 0.5, y: 0.5)

    // MARK: - Body

    var body: some View {
        ZStack {
            // 1. Live camera background
            CameraFeedView()
                .ignoresSafeArea()

            // 2. Tap surface + pin overlay — shares the full-screen geometry
            GeometryReader { geo in
                tapLayer(geo: geo)
                pinLayer(geo: geo)
            }
            .ignoresSafeArea()

            // 3. HUD (top bar + bottom panel)
            VStack(spacing: 0) {
                topBar
                Spacer()
                bottomPanel
            }
        }
        // Category picker sheet
        .sheet(isPresented: $isPresentingCategoryPicker, onDismiss: {
            viewModel.cancelCategoryPick()
        }) {
            LiveCategoryPickerSheet { category in
                viewModel.placeObject(category: category, at: categoryPickerPosition)
                isPresentingCategoryPicker = false
            } onCancel: {
                viewModel.cancelCategoryPick()
                isPresentingCategoryPicker = false
            }
            .presentationDetents([.medium, .large])
        }
        // Photo attachment sheet
        .sheet(isPresented: $viewModel.showingPhotoSheet) {
            AddPhotoSheet(
                roomID: viewModel.selectedObject?.roomID,
                taggedObjectID: viewModel.selectedObject?.id
            ) { photo in
                viewModel.sessionViewModel.addPhoto(photo)
                viewModel.refreshPlacedObjects()
            }
        }
        // Object edit sheet
        .sheet(isPresented: $viewModel.showingEditSheet) {
            if let obj = viewModel.selectedObject {
                LiveTagEditSheet(object: obj) { updated in
                    viewModel.updateObject(updated)
                    viewModel.showingEditSheet = false
                }
            }
        }
        // Drive sheet presentation from phase changes
        .onChange(of: viewModel.phase) { _, newPhase in
            if case .pickingCategory(let pos) = newPhase {
                categoryPickerPosition = pos
                isPresentingCategoryPicker = true
            }
        }
    }

    // MARK: - Tap layer

    private func tapLayer(geo: GeometryProxy) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture { location in
                let norm = NormalizedPoint2D(
                    x: location.x / geo.size.width,
                    y: location.y / geo.size.height
                )
                viewModel.handleTap(at: norm)
            }
    }

    // MARK: - Pin overlay

    private func pinLayer(geo: GeometryProxy) -> some View {
        ZStack {
            ForEach(viewModel.placedObjects) { obj in
                if let anchor = obj.worldAnchor {
                    let selected: Bool = {
                        if case .objectSelected(let id) = viewModel.phase { return id == obj.id }
                        return false
                    }()
                    LiveTagPin(object: obj, isSelected: selected) {
                        viewModel.selectObject(obj.id)
                    }
                    .position(
                        x: CGFloat(anchor.screenX) * geo.size.width,
                        y: CGFloat(anchor.screenY) * geo.size.height
                    )
                }
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }

            Spacer()

            if let room = viewModel.sessionViewModel.selectedRoom {
                Text(room.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
            }

            Spacer()

            Text("\(viewModel.liveTagCount) tagged")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Bottom panel

    @ViewBuilder
    private var bottomPanel: some View {
        switch viewModel.phase {
        case .idle:
            placementPrompt
        case .pickingCategory:
            EmptyView()
        case .objectSelected:
            if let obj = viewModel.selectedObject {
                selectedObjectPanel(for: obj)
            }
        }
    }

    private var placementPrompt: some View {
        VStack(spacing: 10) {
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.9))
            Text("Tap to place a tag")
                .font(.subheadline.bold())
                .foregroundStyle(.white)
            Text("Point at a radiator, boiler, or other object and tap to tag it.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .padding(.bottom, 32)
    }

    private func selectedObjectPanel(for obj: TaggedObject) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Object identity row
            HStack(spacing: 10) {
                Image(systemName: obj.category.symbolName)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.orange.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 1) {
                    Text(obj.displayLabel)
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                    Text(obj.category.groupName)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                }

                Spacer()

                Button {
                    viewModel.deselectObject()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }

            // Action buttons row
            HStack(spacing: 10) {
                panelActionButton(symbol: "camera.fill", label: "Photo") {
                    viewModel.showingPhotoSheet = true
                }
                panelActionButton(symbol: "pencil", label: "Edit") {
                    viewModel.showingEditSheet = true
                }
                Spacer()
                panelActionButton(symbol: "trash", label: "Delete", isDestructive: true) {
                    viewModel.deleteSelectedObject()
                }
            }

            // Photo count badge
            if !obj.linkedPhotoIDs.isEmpty {
                Label(
                    "\(obj.linkedPhotoIDs.count) photo\(obj.linkedPhotoIDs.count == 1 ? "" : "s") attached",
                    systemImage: "photo.fill"
                )
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .padding(.bottom, 32)
    }

    private func panelActionButton(
        symbol: String,
        label: String,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.subheadline)
                Text(label)
                    .font(.caption2)
            }
            .frame(minWidth: 60)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                isDestructive
                    ? Color.red.opacity(0.25)
                    : Color.white.opacity(0.15)
            )
            .foregroundStyle(isDestructive ? .red : .white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

// MARK: - LiveTagPin

/// Pin marker rendered over the camera feed for each placed tagged object.
///
/// The pin is centred on the object's world anchor screen position.
/// Selected objects use a blue accent; unselected objects use orange.
struct LiveTagPin: View {

    let object: TaggedObject
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                // Icon circle
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.blue : Color.orange)
                        .frame(
                            width: isSelected ? 44 : 36,
                            height: isSelected ? 44 : 36
                        )
                    Image(systemName: object.category.symbolName)
                        .font(isSelected ? .callout.bold() : .caption.bold())
                        .foregroundStyle(.white)
                }

                // Label chip
                Text(object.displayLabel)
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())

                // Stem
                Rectangle()
                    .fill(isSelected ? Color.blue : Color.orange)
                    .frame(width: 2, height: 8)
            }
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.4), radius: 3, x: 0, y: 2)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - LiveCategoryPickerSheet

/// Quick-pick sheet for choosing the object type when placing a live-view tag.
///
/// First-pass object types (radiator, boiler, cylinder, flue, other) appear at
/// the top for fast one-tap placement; the full category list follows below.
struct LiveCategoryPickerSheet: View {

    let onSelect: (ServiceObjectCategory) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    private let firstPassCategories: [ServiceObjectCategory] = [
        .radiator, .boiler, .cylinder, .flue, .other
    ]

    var body: some View {
        NavigationStack {
            List {
                Section("Quick Pick") {
                    ForEach(firstPassCategories, id: \.rawValue) { cat in
                        categoryRow(cat)
                    }
                }

                Section("All Types") {
                    ForEach(ServiceObjectCategory.allCases, id: \.rawValue) { cat in
                        categoryRow(cat)
                    }
                }
            }
            .navigationTitle("What is this?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
            }
        }
    }

    private func categoryRow(_ category: ServiceObjectCategory) -> some View {
        Button {
            onSelect(category)
            dismiss()
        } label: {
            Label(category.displayName, systemImage: category.symbolName)
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - LiveTagEditSheet

/// Edit sheet for relabelling or recategorising a placed live-view tag.
struct LiveTagEditSheet: View {

    let object: TaggedObject
    let onSave: (TaggedObject) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var label: String
    @State private var category: ServiceObjectCategory
    @State private var confidence: ConfidenceLevel
    @State private var notes: String

    init(object: TaggedObject, onSave: @escaping (TaggedObject) -> Void) {
        self.object = object
        self.onSave = onSave
        _label      = State(initialValue: object.label)
        _category   = State(initialValue: object.category)
        _confidence = State(initialValue: object.confidence)
        _notes      = State(initialValue: object.notes)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Label") {
                    TextField("Label", text: $label)
                        .autocorrectionDisabled()
                }

                Section("Category") {
                    Picker("Category", selection: $category) {
                        ForEach(ServiceObjectCategory.allCases, id: \.rawValue) { cat in
                            Label(cat.displayName, systemImage: cat.symbolName).tag(cat)
                        }
                    }
                    .pickerStyle(.navigationLink)
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
            .navigationTitle("Edit Tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { commitEdit() }
                }
            }
        }
    }

    private func commitEdit() {
        var updated = object
        updated.label      = label.trimmingCharacters(in: .whitespaces).isEmpty
            ? object.category.displayName
            : label.trimmingCharacters(in: .whitespaces)
        updated.category   = category
        updated.confidence = confidence
        updated.notes      = notes
        updated.touch()
        onSave(updated)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Live View Tagging") {
    LiveViewTaggingView(
        viewModel: LiveViewTaggingViewModel(
            sessionViewModel: SessionCaptureViewModel(
                session: PropertyScanSession(
                    jobReference: "DEMO-001",
                    propertyAddress: "42 Survey Lane",
                    engineerName: "Jane Engineer"
                ),
                store: ScanSessionStore(),
                atlasSync: AtlasSync()
            )
        )
    )
}

#Preview("Category Picker") {
    LiveCategoryPickerSheet(
        onSelect: { _ in },
        onCancel: {}
    )
}

#Preview("Edit Sheet") {
    LiveTagEditSheet(
        object: TaggedObject(
            roomID: UUID(),
            category: .radiator,
            worldAnchor: WorldAnchor3D(screenX: 0.5, screenY: 0.4)
        ),
        onSave: { _ in }
    )
}
#endif
