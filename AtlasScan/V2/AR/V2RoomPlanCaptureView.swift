/// V2RoomPlanCaptureView — Wraps RoomPlan's RoomCaptureView into SwiftUI
/// and bridges captured data into the v2 model types.

import SwiftUI
import RoomPlan
import simd
import AtlasScanCore

struct V2RoomPlanCaptureView: UIViewControllerRepresentable {
    @Binding var capturedRoom: RoomCaptureV2?
    /// Flip to `true` to request that the RoomPlan session stops (i.e. the
    /// user tapped "Finish").  This binding is write-only from the parent's
    /// perspective — the parent sets it to `true` and never resets it.
    /// `RoomPlanCoordinator.isStopped` prevents duplicate stop calls when
    /// SwiftUI re-evaluates `updateUIViewController` after the flag is set.
    @Binding var shouldStop: Bool
    /// Pre-assigned UUID that will be used as the captured room's ID so that
    /// evidence (photos, pins, voice notes) recorded during scanning already
    /// reference the correct room UUID.
    var prospectiveRoomId: UUID?
    /// Called on the main thread with the current floor-polygon vertices each
    /// time RoomPlan publishes an incremental update.  Drive the live mini-map.
    var onLiveVertices: (([Vertex2D]) -> Void)?
    /// Called when RoomPlan ends but no room could be produced.
    var onCaptureEndedWithoutRoom: (() -> Void)?
    /// Exposes center-point probing so SwiftUI overlays can capture spatial
    /// points aligned with the RoomPlan camera view.
    var onCapturePointProbeReady: (((() -> LiveCapturePointProbeResultV1)?) -> Void)?
    /// Exposes frame-based world-to-screen projection for live spatial overlays.
    var onWorldPointProjectionReady: ((((SIMD3<Double>) -> CGPointCodable?)?) -> Void)?
    /// Exposes anchor-id based world-transform resolution for live status updates.
    var onAnchorTransformResolverReady: ((((UUID) -> WorldTransformV1?)?) -> Void)?

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
        context.coordinator.onCaptureEndedWithoutRoom = onCaptureEndedWithoutRoom
        onCapturePointProbeReady?({ context.coordinator.capturePointAtViewCenter() })
        onWorldPointProjectionReady?({ world in
            context.coordinator.projectNormalizedScreenPoint(for: world)
        })
        onAnchorTransformResolverReady?({ anchorId in
            context.coordinator.worldTransform(for: anchorId)
        })
        context.coordinator.startSession()
        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        if shouldStop {
            context.coordinator.stopSession()
        }
    }
}
