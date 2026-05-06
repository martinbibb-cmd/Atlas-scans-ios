/// RoomPlanCoordinator — Bridges RoomPlan delegate callbacks to v2 model types.

import RoomPlan
import simd
import AtlasScanCore

final class RoomPlanCoordinator: NSObject, RoomCaptureSessionDelegate {
    var captureView: RoomCaptureView?
    private var capturedRoomBinding: Binding<RoomCaptureV2?>

    init(capturedRoom: Binding<RoomCaptureV2?>) {
        self.capturedRoomBinding = capturedRoom
    }

    func startSession() {
        let config = RoomCaptureSession.Configuration()
        captureView?.captureSession.delegate = self
        captureView?.captureSession.run(configuration: config)
    }

    func stopSession() {
        captureView?.captureSession.stop()
    }

    // MARK: - RoomCaptureSessionDelegate

    func captureSession(
        _ session: RoomCaptureSession,
        didEndWith data: CapturedRoomData,
        error: (Error)?
    ) {
        Task { @MainActor in
            let processed = try? await RoomBuilder(options: []).capturedRoom(from: data)
            capturedRoomBinding.wrappedValue = processed.map { bridgeToV2($0) }
        }
    }

    private func bridgeToV2(_ room: CapturedRoom) -> RoomCaptureV2 {
        var v2 = RoomCaptureV2(displayName: "Room")
        // Map floor outline from CapturedRoom sections if available.
        for surface in room.floors {
            let transform = surface.transform
            let corners: [SIMD3<Float>] = [
                SIMD3(-0.5, 0,  0.5),
                SIMD3( 0.5, 0,  0.5),
                SIMD3( 0.5, 0, -0.5),
                SIMD3(-0.5, 0, -0.5)
            ]
            v2.polygonVertices = corners.map { local in
                let world = transform * SIMD4(local, 1)
                return Vertex2D(x: Double(world.x), z: Double(world.z))
            }
            v2.ceilingHeightM = Double(surface.dimensions.y)
            break
        }
        return v2
    }
}
