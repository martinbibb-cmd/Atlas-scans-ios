import ARKit
import Foundation
import simd

// MARK: - ARPlacementSession
//
// Lightweight ARKit session that backs live-view tag placement and pin reprojection.
//
// Workflow:
//   1. Call start() when the live-view appears.
//      On supported devices an ARWorldTrackingConfiguration with plane detection runs.
//   2. On tap, call raycast(from:) to obtain a world-space hit transform.
//      Returns nil when no plane was found — caller falls back to screen-only placement.
//   3. Each AR frame publishes an updated frameTimestamp; views observe this to
//      reproject world-anchored pins back into the current camera view via
//      projectToScreen(worldPosition:viewportSize:).
//   4. Call pause() when the live-view disappears.
//
// Architecture:
//   • All ARKit types are confined to this file.
//   • The underlying ARSCNView is exposed as a plain UIView so the SwiftUI layer
//     can display it without importing ARKit or SceneKit.
//   • Frame updates are throttled to ~15 fps so pin reprojection does not force
//     a full SwiftUI re-render at the device's native frame rate.

@MainActor
final class ARPlacementSession: NSObject, ObservableObject {

    // MARK: - Published state

    /// True once the AR session is running and receiving frames.
    @Published private(set) var isRunning: Bool = false

    /// Advances on each throttled AR frame (~15 fps).
    /// Views observe this to trigger live-view pin reprojection.
    @Published private(set) var frameTimestamp: Double = 0

    // MARK: - AR internals

    private let _arView = ARSCNView(frame: .zero)

    /// The AR session's camera preview view, suitable for use as the full-screen
    /// camera background in `LiveViewTaggingView`.
    var arView: UIView { _arView }

    // MARK: - Device capability

    /// True on any device that supports ARWorldTracking (A9+ chip / iPhone 6s+).
    /// Returns false on Simulator — callers should fall back to screen-only placement.
    static var isSupported: Bool {
        ARWorldTrackingConfiguration.isSupported
    }

    // MARK: - Init

    override init() {
        super.init()
        _arView.session.delegate = self
        _arView.automaticallyUpdatesLighting = false
        // No SceneKit scene content — the view is used purely as a camera feed.
        _arView.scene = SCNScene()
    }

    // MARK: - Lifecycle

    /// Starts the AR world-tracking session with horizontal and vertical plane detection.
    /// No-op on unsupported devices.
    func start() {
        guard Self.isSupported else { return }
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        _arView.session.run(config, options: [])
        isRunning = true
    }

    /// Pauses the AR session. Call when the view disappears to save battery.
    func pause() {
        _arView.session.pause()
        isRunning = false
    }

    // MARK: - Placement

    /// Raycasts from an absolute screen point into the AR scene against estimated planes.
    ///
    /// - Parameter screenPoint: Absolute pixel position within the AR view's coordinate space.
    /// - Returns: The world-space 4x4 transform at the hit location, or nil if no plane was hit.
    func raycast(from screenPoint: CGPoint) -> simd_float4x4? {
        guard let query = _arView.raycastQuery(
            from: screenPoint,
            allowing: .estimatedPlane,
            alignment: .any
        ) else { return nil }
        return _arView.session.raycast(query).first?.worldTransform
    }

    // MARK: - Reprojection

    /// Projects a world-space position back into the view's screen-space pixel coordinates.
    ///
    /// - Parameters:
    ///   - worldPosition: The 3D point in ARKit world space (metres, session origin).
    ///   - viewportSize: The current size of the AR view in points.
    /// - Returns: Screen-space pixel position, or nil if the frame is unavailable or
    ///            the point is not visible in the current camera frustum.
    func projectToScreen(worldPosition: simd_float3, viewportSize: CGSize) -> CGPoint? {
        guard let frame = _arView.session.currentFrame,
              viewportSize.width > 0, viewportSize.height > 0
        else { return nil }

        let projected = frame.camera.projectPoint(
            worldPosition,
            orientation: .portrait,
            viewportSize: viewportSize
        )

        // Reject points behind the camera (non-finite values) or far outside the viewport.
        guard projected.x.isFinite, projected.y.isFinite else { return nil }

        // Allow a generous off-screen margin so the pin can slide back in as the camera turns.
        let margin: CGFloat = viewportSize.width
        guard projected.x > -margin, projected.x < viewportSize.width  + margin,
              projected.y > -margin, projected.y < viewportSize.height + margin
        else { return nil }

        return projected
    }
}

// MARK: - ARSessionDelegate

extension ARPlacementSession: ARSessionDelegate {

    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let ts = frame.timestamp
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Throttle to ~15 fps: only publish if ~66 ms have elapsed since last update.
            guard ts - self.frameTimestamp > 0.066 else { return }
            self.frameTimestamp = ts
        }
    }
}
