import SwiftUI
import UIKit
import ARKit
import simd

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
//      → A light haptic confirms placement; a brief "Radiator tagged" toast appears.
//   4. The bottom panel shows the selected object's name + action buttons:
//        • Camera — opens camera directly and attaches the captured photo to the object.
//        • Edit    — relabel / recategorise / change confidence.
//        • Trash   — remove the tag.
//   5. Tap × in the panel or tap empty space to deselect.
//   6. Continue walking; all pins remain visible for the session.
//   7. Tap × in the top-left corner to dismiss back to the session list.
//
// State is managed by LiveViewTaggingViewModel.  All object mutations pass through
// the wrapped SessionCaptureViewModel so autosave and Atlas sync remain intact.
//
// AR placement and reprojection:
//   On supported devices (A9+ chip) ARPlacementSession runs alongside the camera feed.
//   Taps forward both a NormalizedPoint2D and the raw CGPoint to the view model so
//   an ARKit estimatedPlane raycast can populate WorldAnchor3D with real world coords.
//   Each AR frame (~15 fps) publishes a timestamp update; the pin layer uses this to
//   reproject world-anchored pins back into the current camera view via
//   ARPlacementSession.projectToScreen().  Screen-only anchors continue to use the
//   stored screenX/screenY as before.

struct LiveViewTaggingView: View {

    @ObservedObject var viewModel: LiveViewTaggingViewModel
    @Environment(\.dismiss) private var dismiss

    // MARK: AR session

    /// Manages the ARKit session for world-space tap raycasting and live-view
    /// pin reprojection.  Created here and injected into the view model on appear.
    /// On unsupported devices (Simulator, pre-A9) this still exists but does nothing —
    /// ARPlacementSession.isSupported guards all ARKit calls internally.
    @StateObject private var arPlacement = ARPlacementSession()

    // MARK: Local sheet / overlay state

    /// Captured at the moment a tap triggers category selection so the position
    /// is stable for the duration of the sheet presentation.
    @State private var isPresentingCategoryPicker = false
    @State private var categoryPickerPosition = NormalizedPoint2D(x: 0.5, y: 0.5)

    /// Set when inline photo save fails so the user sees an error alert.
    @State private var showingPhotoSaveError = false

    /// Reused across placements to avoid repeated allocation. Prepared in onAppear
    /// and after each use so the Taptic Engine is ready for the next placement.
    @State private var feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)

    // MARK: - Body

    var body: some View {
        ZStack {
            // 1. Live camera background.
            // Use ARSCNView from ARPlacementSession when AR tracking is available
            // so the same session provides both the camera feed and raycasting.
            // Fall back to the AVFoundation preview on unsupported devices.
            if ARPlacementSession.isSupported {
                ARCameraFeedView(session: arPlacement)
                    .ignoresSafeArea()
            } else {
                CameraFeedView()
                    .ignoresSafeArea()
            }

            // 2. Tap surface + pin overlay — shares the full-screen geometry
            GeometryReader { geo in
                tapLayer(geo: geo)
                pinLayer(geo: geo)
            }
            .ignoresSafeArea()

            // 3. HUD (top bar + bottom panel) + placement toast
            VStack(spacing: 0) {
                topBar
                Spacer()
                placementToastLayer
                bottomPanel
            }
            .animation(.easeInOut(duration: 0.25), value: viewModel.placementConfirmationText)
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
        // Photo attachment sheet (full form with caption / key-evidence)
        .sheet(isPresented: $viewModel.showingPhotoSheet) {
            AddPhotoSheet(
                roomID: viewModel.selectedObject?.roomID,
                taggedObjectID: viewModel.selectedObject?.id
            ) { photo in
                viewModel.sessionViewModel.addPhoto(photo)
                viewModel.refreshPlacedObjects()
            }
        }
        // Direct inline camera capture: opens camera immediately and attaches
        // the photo to the selected object without any form steps.
        .sheet(isPresented: $viewModel.showingDirectCapture) {
            ImagePickerView(source: .camera) { image in
                attachInlinePhoto(image)
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
        // Prepare haptic engine on appear so the first placement fires without delay.
        // Also start the AR session and inject it into the view model.
        .onAppear {
            feedbackGenerator.prepare()
            if ARPlacementSession.isSupported {
                viewModel.arPlacementSession = arPlacement
                arPlacement.start()
            }
        }
        // Pause AR when the view disappears to release the camera and save battery.
        .onDisappear {
            arPlacement.pause()
        }
        // Haptic feedback when a new object is placed; prepare() pre-warms for the next one
        .onChange(of: viewModel.lastPlacedID) { _, newID in
            guard newID != nil else { return }
            feedbackGenerator.impactOccurred()
            feedbackGenerator.prepare()
        }
        // Alert when an inline photo save fails
        .alert("Could Not Save Photo", isPresented: $showingPhotoSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The photo could not be attached to the object. Please check available storage and try again.")
        }
    }

    // MARK: - Inline photo capture

    /// Saves the captured image and attaches it to the currently selected object,
    /// filing it under the most appropriate evidence kind for the category.
    /// Shows an error alert if the photo cannot be saved to disk.
    private func attachInlinePhoto(_ image: UIImage) {
        guard let obj = viewModel.selectedObject else { return }
        let photoID = UUID()
        let saved: (filename: String, thumbnailPath: String?)
        do {
            saved = try PhotoStore.shared.save(image, id: photoID)
        } catch {
            showingPhotoSaveError = true
            return
        }
        let photo = TaggedPhoto(
            id: photoID,
            roomID: obj.roomID,
            taggedObjectID: obj.id,
            filename: saved.filename,
            thumbnailPath: saved.thumbnailPath,
            kind: obj.category.defaultEvidenceKind
        )
        viewModel.sessionViewModel.addPhoto(photo)
        viewModel.refreshPlacedObjects()
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
                // Pass the raw screen point so the view model can perform an AR raycast.
                viewModel.handleTap(at: norm, screenPoint: location)
            }
    }

    // MARK: - Pin overlay

    private func pinLayer(geo: GeometryProxy) -> some View {
        // currentFrameTimestamp subscribes this view to AR frame updates so that
        // resolvedPinPosition is called with fresh camera data on each ~15 fps tick.
        // The value is forwarded to resolvedPinPosition as a readiness flag.
        let currentFrameTimestamp = arPlacement.frameTimestamp

        return ZStack {
            ForEach(viewModel.placedObjects) { obj in
                if let anchor = obj.worldAnchor {
                    let selected: Bool = {
                        if case .objectSelected(let id) = viewModel.phase { return id == obj.id }
                        return false
                    }()
                    let pinPos = resolvedPinPosition(for: anchor,
                                                     arFrameTimestamp: currentFrameTimestamp,
                                                     geo: geo)
                    LiveTagPin(
                        object: obj,
                        isSelected: selected,
                        isNew: obj.id == viewModel.lastPlacedID
                    ) {
                        viewModel.selectObject(obj.id)
                    }
                    .position(pinPos)
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.65),
                   value: viewModel.lastPlacedID)
        // Note: the container spring (0.35/0.65) is intentionally slightly more damped
        // than the pin entrance spring (0.4/0.55) in LiveTagPin, which has a bouncier
        // feel to emphasise the placement moment.
    }

    // MARK: - Pin position resolution

    /// Returns the screen-space CGPoint at which to draw a pin.
    ///
    /// For AR-grounded anchors (`.raycastEstimated` or `.worldLocked`) this
    /// reprojects the stored world position into the current camera view so the
    /// pin stays visually locked to the physical scene as the camera moves.
    ///
    /// `arFrameTimestamp` is passed in (rather than read directly) so that
    /// callers can forward the SwiftUI-observed timestamp value and guarantee
    /// this function is invoked on the same render pass that detected a frame change.
    ///
    /// When reprojection is unavailable (AR not running, no current frame, or the
    /// point is off-screen) it falls back to the stored `screenX`/`screenY`
    /// position that was captured at placement time.
    private func resolvedPinPosition(
        for anchor: WorldAnchor3D,
        arFrameTimestamp: Double,
        geo: GeometryProxy
    ) -> CGPoint {
        if anchor.anchorConfidence != .screenOnly, arFrameTimestamp > 0 {
            let worldPos = simd_float3(Float(anchor.x), Float(anchor.y), Float(anchor.z))
            if let projected = arPlacement.projectToScreen(
                worldPosition: worldPos,
                viewportSize: geo.size
            ) {
                // Clamp to within the visible area so the pin never renders entirely
                // off-screen — it slides to the nearest edge instead.
                let margin: CGFloat = 24
                return CGPoint(
                    x: min(max(projected.x, margin), geo.size.width  - margin),
                    y: min(max(projected.y, margin), geo.size.height - margin)
                )
            }
        }
        // Fallback: use stored screen-space coordinates from placement time.
        return CGPoint(
            x: CGFloat(anchor.screenX) * geo.size.width,
            y: CGFloat(anchor.screenY) * geo.size.height
        )
    }

    // MARK: - Placement toast

    @ViewBuilder
    private var placementToastLayer: some View {
        if let text = viewModel.placementConfirmationText {
            Text(text)
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.65))
                .clipShape(Capsule())
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
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
            } else {
                Text("Not assigned to a room yet")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
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
                // Photo button: opens camera directly and attaches the shot to this object.
                panelActionButton(symbol: "camera.fill", label: "Photo") {
                    viewModel.showingDirectCapture = true
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
                Label(photoCountDescription(obj.linkedPhotoIDs.count), systemImage: "photo.fill")
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

    private func photoCountDescription(_ count: Int) -> String {
        "\(count) photo\(count == 1 ? "" : "s") attached"
    }
}

// MARK: - LiveTagPin

/// Pin marker rendered over the camera feed for each placed tagged object.
///
/// The pin is centred on the object's world anchor screen position.
/// Selected objects use a blue accent; unselected objects use orange.
/// Newly placed pins (isNew = true) scale in with a spring entrance animation.
struct LiveTagPin: View {

    let object: TaggedObject
    let isSelected: Bool
    let isNew: Bool
    let onTap: () -> Void

    @State private var appeared = false

    // MARK: - Entrance animation helpers

    /// Scale for the pin. Newly placed pins start at 0.1 and spring to full size.
    private var entranceScale: CGFloat {
        if appeared { return 1.0 }
        return isNew ? 0.1 : 1.0
    }

    /// Opacity for the pin. Newly placed pins fade in alongside the scale.
    private var entranceOpacity: Double {
        if appeared { return 1.0 }
        return isNew ? 0.0 : 1.0
    }

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
        // Entrance animation for newly placed pins
        .scaleEffect(entranceScale)
        .opacity(entranceOpacity)
        .onAppear {
            if isNew {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.55)) {
                    appeared = true
                }
            } else {
                appeared = true
            }
        }
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
