/// GhostBoxRenderer — Manages ghost-box entity creation and clearance conflict highlighting.

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
            let spec = pin.hardwareSpecId.flatMap { registry.spec(for: $0) }
            let envelope = spec?.clearanceEnvelope ?? ClearanceEnvelopeV1(
                widthM: 0.5, heightM: 0.8, depthM: 0.5,
                clearanceTopM: 0.2, clearanceBottomM: 0.0,
                clearanceFrontM: 0.3, clearanceBackM: 0.1,
                clearanceLeftM: 0.1, clearanceRightM: 0.1
            )
            let entity = ghostBoxEntity(for: pin, envelope: envelope)
            anchor.addChild(entity)
        }
    }

    private func ghostBoxEntity(for pin: SpatialPinV1, envelope: ClearanceEnvelopeV1) -> ModelEntity {
        let w = Float(envelope.widthM  + envelope.clearanceLeftM  + envelope.clearanceRightM)
        let h = Float(envelope.heightM + envelope.clearanceTopM   + envelope.clearanceBottomM)
        let d = Float(envelope.depthM  + envelope.clearanceFrontM + envelope.clearanceBackM)
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
    func spec(for id: UUID) -> HardwareSpecV1? {
        catalogue.first { $0.id == id }
    }
}
