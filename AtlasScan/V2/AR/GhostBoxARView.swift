/// GhostBoxARView — Displays clearance-envelope ghost boxes in the live AR scene.
///
/// Starts an ARWorldTracking session with LiDAR scene reconstruction so that
/// GhostBoxRenderer can cast rays against the live mesh for collision detection.

import SwiftUI
import RealityKit
import ARKit
import AtlasScanCore

struct GhostBoxARView: UIViewRepresentable {
    var pins: [SpatialPinV1]
    var hardwareRegistry: HardwareRegistryV1 = .shared

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        context.coordinator.arView = arView

        // Start a LiDAR-backed session so GhostBoxRenderer can perform mesh-based
        // collision detection. Falls back gracefully on devices without LiDAR.
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            let config = ARWorldTrackingConfiguration()
            config.sceneReconstruction = .meshWithClassification
            config.environmentTexturing = .none
            arView.session.run(config, options: [.removeExistingAnchors, .resetTracking])
        }

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
