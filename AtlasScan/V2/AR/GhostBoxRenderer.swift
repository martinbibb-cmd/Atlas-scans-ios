/// GhostBoxRenderer — Manages ghost-box entity creation and clearance conflict highlighting.

import Foundation
import RealityKit
import AtlasScanCore

final class GhostBoxRenderer: NSObject {
    weak var arView: ARView?
    private var rootAnchor: AnchorEntity?

    func buildScene(pins: [SpatialPinV1], registry: HardwareRegistryV1) {
        guard let arView else { return }
        rootAnchor?.removeFromParent()
        let anchor = AnchorEntity(world: .zero)
        arView.scene.addAnchor(anchor)
        rootAnchor = anchor

        for pin in pins {
            let spec = pin.hardwareSpecId.flatMap { id in
                registry.allSpecs().first { $0.id == id }
            }
            let entity = ghostBoxEntity(for: pin, spec: spec)
            anchor.addChild(entity)
        }
    }

    private func ghostBoxEntity(for pin: SpatialPinV1, spec: HardwareSpecV1?) -> ModelEntity {
        let w: Float
        let h: Float
        let d: Float
        if let spec {
            w = Float(spec.ghostBoxWidthM)
            h = Float(spec.ghostBoxHeightM)
            d = Float(spec.ghostBoxDepthM)
        } else {
            // Regulatory minimum fallback box
            let env = ClearanceEnvelopeV1.regulatoryMinimum
            w = Float(0.5 + env.leftM + env.rightM)
            h = Float(0.8 + env.topM  + env.bottomM)
            d = Float(0.5 + env.frontM + env.backM)
        }
        let mesh = MeshResource.generateBox(size: SIMD3(w, h, d))
        var material = SimpleMaterial()
        material.color = .init(tint: .cyan.withAlphaComponent(0.25))
        material.metallic = 0
        material.roughness = 1
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.position = SIMD3(Float(pin.positionX), Float(pin.positionY), Float(pin.positionZ))
        return entity
    }
}

extension HardwareRegistryV1 {
    func allSpecs() -> [HardwareSpecV1] {
        allSpecs(ofType: .boiler) + allSpecs(ofType: .heatPump)
            + allSpecs(ofType: .hotWaterCylinder) + allSpecs(ofType: .pressureVessel)
    }
}
