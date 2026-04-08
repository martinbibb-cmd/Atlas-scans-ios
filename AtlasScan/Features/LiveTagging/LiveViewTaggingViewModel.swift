import Foundation

// MARK: - LiveViewTaggingViewModel
//
// Coordinator ViewModel for the live-view spatial object tagging surface.
//
// Wraps SessionCaptureViewModel to add the live-view interaction layer:
//   • screen tap → category picker → object placement
//   • pin overlay position tracking via WorldAnchor3D.screenX/Y
//   • selected-object edit / photo-attach / delete actions
//
// All mutations are routed through SessionCaptureViewModel so autosave,
// Atlas sync state, and PropertyScanSession integrity are always maintained.
//
// Lifecycle:
//   1. Engineer opens LiveViewTaggingView — phase starts at .idle.
//   2. Tap on empty screen area → phase becomes .pickingCategory(at:).
//   3. LiveCategoryPickerSheet appears; engineer picks a type.
//   4. placeObject(category:at:) creates the TaggedObject with worldAnchor set.
//      Phase advances to .objectSelected(id).
//   5. Tap on an existing pin → phase becomes .objectSelected(id).
//   6. From the selected-object panel: attach photo, edit label/category,
//      or delete the tag.
//   7. deselectObject() returns phase to .idle.

@MainActor
final class LiveViewTaggingViewModel: ObservableObject {

    // MARK: - Tagging phase

    enum TaggingPhase: Equatable {
        /// Walking through the property; no pending action.
        case idle
        /// A screen tap was recorded at this normalised position; waiting for category selection.
        case pickingCategory(at: NormalizedPoint2D)
        /// An existing placed object is focused for editing/photo attachment.
        case objectSelected(UUID)
    }

    // MARK: - Published

    @Published private(set) var phase: TaggingPhase = .idle

    /// All tagged objects across the session that have a live-view world anchor.
    /// Session-level objects without an anchor are also included so they remain
    /// visible if they were added via the list view and later linked to a room.
    @Published private(set) var placedObjects: [TaggedObject] = []

    @Published var showingPhotoSheet: Bool = false
    @Published var showingEditSheet: Bool = false

    /// Set to true to present the direct-capture camera sheet from LiveViewTaggingView.
    /// Taking a photo attaches it immediately to the selected object and returns to live view.
    @Published var showingDirectCapture: Bool = false

    // MARK: - Constants

    /// Duration for which the placement confirmation toast remains visible.
    private static let confirmationDisplayDuration: UInt64 = 2_000_000_000  // 2 seconds

    // MARK: - Placement feedback

    /// Short confirmation message shown after a successful tag placement (e.g. "Radiator tagged").
    /// Automatically cleared after 2 seconds.
    @Published private(set) var placementConfirmationText: String? = nil

    /// ID of the most recently placed object, used to trigger entrance animation on the new pin.
    @Published private(set) var lastPlacedID: UUID? = nil

    /// Retained so it can be cancelled when a new placement fires before the timer expires.
    /// Explicit `deinit` cleanup is intentionally omitted — matching the `autosaveTask`
    /// pattern in SessionCaptureViewModel — because the closure captures `[weak self]`,
    /// so if the ViewModel is deallocated the body becomes a no-op, and the max
    /// outstanding duration is only 2 seconds.
    private var confirmationClearTask: Task<Void, Never>?

    // MARK: - Dependencies

    /// The owning session-capture coordinator.  Mutations pass through this so
    /// autosave and sync state are handled in one place.
    let sessionViewModel: SessionCaptureViewModel

    // MARK: - Init

    init(sessionViewModel: SessionCaptureViewModel) {
        self.sessionViewModel = sessionViewModel
        self.placedObjects = sessionViewModel.session.allTaggedObjects
    }

    // MARK: - Tap handling

    /// Called when the engineer taps the camera view.
    /// `normalizedPoint` is in 0…1 space (x = left→right, y = top→bottom).
    func handleTap(at normalizedPoint: NormalizedPoint2D) {
        if let existing = objectNear(normalizedPoint) {
            selectObject(existing.id)
        } else {
            phase = .pickingCategory(at: normalizedPoint)
        }
    }

    // MARK: - Placement

    /// Creates and registers a new TaggedObject at the tapped screen position.
    /// The object is added to the currently focused room (if any) or session-level.
    func placeObject(category: ServiceObjectCategory, at position: NormalizedPoint2D) {
        let roomID = sessionViewModel.selectedRoomID ?? sessionViewModel.session.id
        var obj = TaggedObject(roomID: roomID, category: category)
        // World-space coordinates are approximate placeholders for the camera-only path.
        // x and z are derived from the screen position (treating the view as a top-down
        // unit floor plan); y is 0 (floor plane).  A future ARKit integration would
        // replace these with raycasted world coordinates from the LiDAR mesh.
        obj.worldAnchor = WorldAnchor3D(
            x: Double(position.x),
            y: 0.0,
            z: Double(position.y),
            screenX: Double(position.x),
            screenY: Double(position.y)
        )
        sessionViewModel.addObject(obj)
        refreshPlacedObjects()
        selectObject(obj.id)

        // Placement feedback: show confirmation toast and mark the new pin for entrance animation.
        let displayName = category.displayName
        placementConfirmationText = "\(displayName) tagged"
        lastPlacedID = obj.id
        confirmationClearTask?.cancel()
        confirmationClearTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: Self.confirmationDisplayDuration)
            } catch {
                // Task was cancelled (a new placement fired before timeout) — nothing to clean up.
                return
            }
            self?.placementConfirmationText = nil
        }
    }

    func cancelCategoryPick() {
        phase = .idle
    }

    // MARK: - Object selection

    func selectObject(_ id: UUID) {
        sessionViewModel.selectObject(id)
        phase = .objectSelected(id)
    }

    func deselectObject() {
        sessionViewModel.selectObject(nil)
        phase = .idle
    }

    // MARK: - Object mutation

    /// Propagates label / category / confidence changes to the session.
    func updateObject(_ updated: TaggedObject) {
        sessionViewModel.updateObject(updated)
        refreshPlacedObjects()
    }

    /// Removes the currently selected object from the session.
    func deleteSelectedObject() {
        guard case .objectSelected(let id) = phase else { return }
        sessionViewModel.removeObject(id: id)
        phase = .idle
        refreshPlacedObjects()
    }

    // MARK: - Computed

    var selectedObject: TaggedObject? {
        guard case .objectSelected(let id) = phase else { return nil }
        return placedObjects.first { $0.id == id }
    }

    /// Count of objects that carry a live-view world anchor.
    var liveTagCount: Int {
        placedObjects.filter { $0.worldAnchor != nil }.count
    }

    // MARK: - Refresh

    /// Re-reads the current object list from the session.
    /// Call after any mutation that may change the collection.
    func refreshPlacedObjects() {
        placedObjects = sessionViewModel.session.allTaggedObjects
    }

    // MARK: - Proximity detection

    /// Returns the first object whose world anchor is within `threshold` normalised
    /// units of `point`.  Used to detect "tap-on-existing-pin" gestures.
    private func objectNear(_ point: NormalizedPoint2D, threshold: Double = 0.07) -> TaggedObject? {
        placedObjects.first { obj in
            guard let anchor = obj.worldAnchor else { return false }
            let dx = anchor.screenX - Double(point.x)
            let dy = anchor.screenY - Double(point.y)
            return (dx * dx + dy * dy).squareRoot() < threshold
        }
    }
}
