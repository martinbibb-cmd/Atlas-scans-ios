import SwiftUI

// MARK: - InstallMarkupViewModel
//
// Manages the engineer's drawing interaction state during install markup capture.
//
// Lifecycle:
//   1. Engineer opens the markup overlay on a room floor plan.
//   2. Picks a mode: place an object type, or draw a route kind.
//   3. Taps / draws on the canvas.
//   4. Commits completed objects and routes back to SessionCaptureViewModel.
//
// This view-model owns only the in-flight drawing state.
// Committed markup lives in SessionCaptureViewModel → PropertyScanSession.

@MainActor
final class InstallMarkupViewModel: ObservableObject {

    // MARK: - Drawing mode

    /// The current interaction mode on the markup canvas.
    enum DrawingMode: Equatable {
        /// No active drawing; engineer is in inspect/select mode.
        case idle
        /// Engineer is about to place an object of the given category type.
        case placingObject(categoryRawValue: String)
        /// Engineer is drawing a route of the given kind.
        case drawingRoute(kind: MarkupRouteKind)
    }

    // MARK: - Published state

    @Published var drawingMode: DrawingMode = .idle

    /// Layer toggle: are we marking up `existing` or `proposed` install?
    @Published var activeLayer: MarkupLayer = .proposed

    /// In-progress route waypoints (cleared on route commit or cancel).
    @Published var currentRoutePath: [NormalizedPoint2D] = []

    /// Default pipe diameter for newly drawn routes (mm).
    @Published var defaultDiameterMm: Double = 22

    /// Default mounting for newly drawn routes.
    @Published var defaultMounting: MarkupRouteMounting = .surface

    /// Toast message shown briefly after an action.
    @Published var confirmationMessage: String? = nil

    // MARK: - Private

    private let roomID: UUID?
    private var confirmationClearTask: Task<Void, Never>?

    // Callbacks to persist committed markup
    private let onAddObject: (InstallMarkupObject) -> Void
    private let onAddRoute: (InstallMarkupRoute) -> Void

    // MARK: - Init

    init(
        roomID: UUID?,
        onAddObject: @escaping (InstallMarkupObject) -> Void,
        onAddRoute: @escaping (InstallMarkupRoute) -> Void
    ) {
        self.roomID = roomID
        self.onAddObject = onAddObject
        self.onAddRoute = onAddRoute
    }

    // MARK: - Canvas tap handler

    /// Called when the engineer taps a point on the markup canvas.
    ///
    /// - Parameter point: The normalised canvas position (0…1 in both axes).
    func handleTap(at point: NormalizedPoint2D) {
        switch drawingMode {
        case .idle:
            break
        case .placingObject(let categoryRawValue):
            placeObject(categoryRawValue: categoryRawValue, at: point)
        case .drawingRoute:
            currentRoutePath.append(point)
        }
    }

    // MARK: - Object placement

    /// Places a new install object at the given canvas position and commits it.
    private func placeObject(categoryRawValue: String, at position: NormalizedPoint2D) {
        let obj = InstallMarkupObject(
            categoryRawValue: categoryRawValue,
            position: position,
            source: .manual,
            layer: activeLayer,
            roomID: roomID
        )
        onAddObject(obj)
        let label = ServiceObjectCategory(rawValue: categoryRawValue)?.displayName ?? categoryRawValue
        showConfirmation("\(label) placed")
    }

    // MARK: - Route drawing

    /// Finalises the current in-progress route and commits it.
    ///
    /// Requires at least two waypoints to form a valid segment.
    func finishRoute() {
        guard case .drawingRoute(let kind) = drawingMode,
              currentRoutePath.count >= 2
        else {
            cancelRoute()
            return
        }
        let route = InstallMarkupRoute(
            kind: kind,
            diameterMm: defaultDiameterMm,
            path: currentRoutePath,
            mounting: defaultMounting,
            confidence: .drawn,
            layer: activeLayer,
            roomID: roomID
        )
        onAddRoute(route)
        currentRoutePath = []
        showConfirmation("\(kind.displayName) route drawn")
    }

    /// Removes the last waypoint added to the current in-progress route.
    func undoLastWaypoint() {
        guard !currentRoutePath.isEmpty else { return }
        currentRoutePath.removeLast()
    }

    /// Discards the in-progress route without committing.
    func cancelRoute() {
        currentRoutePath = []
    }

    // MARK: - Mode helpers

    /// Switches to object-placement mode for the given category.
    func selectObjectPlacement(categoryRawValue: String) {
        cancelRoute()
        drawingMode = .placingObject(categoryRawValue: categoryRawValue)
    }

    /// Switches to route-drawing mode for the given kind.
    func selectRouteDrawing(kind: MarkupRouteKind) {
        cancelRoute()
        drawingMode = .drawingRoute(kind: kind)
    }

    /// Returns to idle / inspect mode.
    func selectIdle() {
        cancelRoute()
        drawingMode = .idle
    }

    // MARK: - Toast

    private func showConfirmation(_ message: String) {
        confirmationMessage = message
        confirmationClearTask?.cancel()
        confirmationClearTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            confirmationMessage = nil
        }
    }
}
