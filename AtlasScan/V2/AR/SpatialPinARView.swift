/// SpatialPinARView — Lets the user tap a world-space point to place an appliance pin.

import SwiftUI
import ARKit
import RealityKit
import AtlasScanCore

struct SpatialPinARView: UIViewRepresentable {
    var roomId: UUID
    @Binding var pins: [SpatialPinV1]
    var pendingObjectType: PinnedObjectType = .boiler

    func makeCoordinator() -> SpatialPinManager {
        SpatialPinManager(roomId: roomId, pins: $pins, pendingType: pendingObjectType)
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        context.coordinator.setup(arView: arView)
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.pendingType = pendingObjectType
    }
}
