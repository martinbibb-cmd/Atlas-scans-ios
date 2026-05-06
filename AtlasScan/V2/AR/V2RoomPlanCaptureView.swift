/// V2RoomPlanCaptureView — Wraps RoomPlan's RoomCaptureView into SwiftUI
/// and bridges captured data into the v2 model types.

import SwiftUI
import RoomPlan
import AtlasScanCore

struct V2RoomPlanCaptureView: UIViewControllerRepresentable {
    @Binding var capturedRoom: RoomCaptureV2?

    func makeCoordinator() -> RoomPlanCoordinator {
        RoomPlanCoordinator(capturedRoom: $capturedRoom)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        let captureView = RoomCaptureView(frame: vc.view.bounds)
        captureView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        vc.view.addSubview(captureView)
        context.coordinator.captureView = captureView
        context.coordinator.startSession()
        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
