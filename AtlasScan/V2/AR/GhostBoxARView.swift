/// GhostBoxARView — Displays clearance-envelope ghost boxes in the live AR scene.

import SwiftUI
import RealityKit
import AtlasScanCore

struct GhostBoxARView: UIViewRepresentable {
    var pins: [SpatialPinV1]
    var hardwareRegistry: HardwareRegistryV1 = .shared

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        context.coordinator.arView = arView
        context.coordinator.buildScene(pins: pins, registry: hardwareRegistry)
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.buildScene(pins: pins, registry: hardwareRegistry)
    }

    func makeCoordinator() -> GhostBoxRenderer {
        GhostBoxRenderer()
    }
}
