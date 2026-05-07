/// V2RoomPlanCaptureView — Wraps RoomPlan's RoomCaptureView into SwiftUI
/// and bridges captured data into the v2 model types.

import SwiftUI
import RoomPlan
import AtlasScanCore

struct V2RoomPlanCaptureView: UIViewControllerRepresentable {
    @Binding var capturedRoom: RoomCaptureV2?
    /// Flip to `true` to request that the RoomPlan session stops (i.e. the
    /// user tapped "Finish").  The binding is intentionally one-directional;
    /// once the session is stopped the coordinator sets `isStopped` to prevent
    /// a second call from later SwiftUI updates.
    @Binding var shouldStop: Bool
    /// Pre-assigned UUID that will be used as the captured room's ID so that
    /// evidence (photos, pins, voice notes) recorded during scanning already
    /// reference the correct room UUID.
    var prospectiveRoomId: UUID?
    /// Called on the main thread with the current floor-polygon vertices each
    /// time RoomPlan publishes an incremental update.  Drive the live mini-map.
    var onLiveVertices: (([Vertex2D]) -> Void)?

    func makeCoordinator() -> RoomPlanCoordinator {
        RoomPlanCoordinator(capturedRoom: $capturedRoom)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        let captureView = RoomCaptureView(frame: vc.view.bounds)
        captureView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        vc.view.addSubview(captureView)
        context.coordinator.captureView = captureView
        context.coordinator.prospectiveRoomId = prospectiveRoomId
        context.coordinator.onLiveVertices = onLiveVertices
        context.coordinator.startSession()
        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        if shouldStop {
            context.coordinator.stopSession()
        }
    }
}
