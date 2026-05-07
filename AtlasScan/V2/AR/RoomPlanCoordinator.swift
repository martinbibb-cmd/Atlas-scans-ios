/// RoomPlanCoordinator — Bridges RoomPlan delegate callbacks to v2 model types.

import SwiftUI
import RoomPlan
import simd
import AtlasScanCore

final class RoomPlanCoordinator: NSObject, RoomCaptureSessionDelegate {
    var captureView: RoomCaptureView?
    private var capturedRoomBinding: Binding<RoomCaptureV2?>

    /// Optional pre-assigned room ID so photos/pins captured before Finish
    /// share the same UUID as the room that gets saved on completion.
    var prospectiveRoomId: UUID?

    /// Called on the main thread each time RoomPlan publishes an incremental
    /// update. Use this to drive the live mini-map polygon.
    var onLiveVertices: (([Vertex2D]) -> Void)?

    /// Set to true once stopSession() has been called so updateUIViewController
    /// does not fire a second stop.
    private(set) var isStopped = false

    init(capturedRoom: Binding<RoomCaptureV2?>) {
        self.capturedRoomBinding = capturedRoom
    }

    func startSession() {
        isStopped = false
        let config = RoomCaptureSession.Configuration()
        captureView?.captureSession.delegate = self
        captureView?.captureSession.run(configuration: config)
    }

    func stopSession() {
        guard !isStopped else { return }
        isStopped = true
        captureView?.captureSession.stop()
    }

    // MARK: - RoomCaptureSessionDelegate

    /// Live incremental update — extract the current floor polygon for the mini-map.
    func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
        let vertices = polygonVertices(from: room)
        DispatchQueue.main.async { [weak self] in
            self?.onLiveVertices?(vertices)
        }
    }

    func captureSession(
        _ session: RoomCaptureSession,
        didEndWith data: CapturedRoomData,
        error: (Error)?
    ) {
        Task { @MainActor in
            do {
                // Empty options: no post-processing overrides needed for the default capture.
                let processed = try await RoomBuilder(options: []).capturedRoom(from: data)
                capturedRoomBinding.wrappedValue = bridgeToV2(processed)
            } catch {
                print("[RoomPlanCoordinator] RoomBuilder failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Private helpers

    private func bridgeToV2(_ room: CapturedRoom) -> RoomCaptureV2 {
        var v2 = RoomCaptureV2(
            id: prospectiveRoomId ?? UUID(),
            displayName: "Room"
        )
        v2.polygonVertices = polygonVertices(from: room)
        if let surface = room.floors.first {
            v2.ceilingHeightM = Double(surface.dimensions.y)
        }
        return v2
    }

    /// Extracts an ordered floor-polygon from the first floor surface of a
    /// CapturedRoom.  Returns an empty array when no floor is present.
    private func polygonVertices(from room: CapturedRoom) -> [Vertex2D] {
        guard let surface = room.floors.first else { return [] }
        let transform = surface.transform
        // Build the four corners of the floor surface in local space, then
        // transform them into world space (X-Z horizontal plane).
        let corners: [SIMD3<Float>] = [
            SIMD3(-0.5, 0,  0.5),
            SIMD3( 0.5, 0,  0.5),
            SIMD3( 0.5, 0, -0.5),
            SIMD3(-0.5, 0, -0.5)
        ]
        return corners.map { local in
            let world = transform * SIMD4(local, 1)
            return Vertex2D(x: Double(world.x), z: Double(world.z))
        }
    }
}
