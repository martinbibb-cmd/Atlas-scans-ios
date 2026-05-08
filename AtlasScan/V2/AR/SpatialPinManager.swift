/// SpatialPinManager — Handles tap-to-place logic for appliance spatial pins.

import ARKit
import RealityKit
import SwiftUI
import AtlasScanCore

final class SpatialPinManager: NSObject {
    private let roomId: UUID
    private var pinsBinding: Binding<[SpatialPinV1]>
    var pendingType: PinnedObjectType
    private weak var arView: ARView?

    init(roomId: UUID, pins: Binding<[SpatialPinV1]>, pendingType: PinnedObjectType) {
        self.roomId = roomId
        self.pinsBinding = pins
        self.pendingType = pendingType
    }

    func setup(arView: ARView) {
        self.arView = arView
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        arView.addGestureRecognizer(tap)
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        arView.session.run(config)
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let arView else { return }
        let loc = gesture.location(in: arView)
        let results = arView.raycast(from: loc, allowing: .estimatedPlane, alignment: .any)
        guard let result = results.first else {
            let fallback = SpatialPinV1(
                roomId: roomId,
                positionX: 0,
                positionY: 0,
                positionZ: 0,
                screenPositionX: Double(loc.x / max(arView.bounds.width, 1)),
                screenPositionY: Double(loc.y / max(arView.bounds.height, 1)),
                objectType: pendingType,
                anchorConfidence: .screenOnly
            )
            DispatchQueue.main.async { [weak self] in
                self?.pinsBinding.wrappedValue.append(fallback)
            }
            return
        }
        let col = result.worldTransform.columns.3
        let confidence: SpatialPinAnchorConfidence
        switch result.target {
        case .estimatedPlane:
            confidence = .raycastEstimated
        case .existingPlaneGeometry, .existingPlaneInfinite:
            confidence = .high
        @unknown default:
            confidence = .raycastEstimated
        }
        let pin = SpatialPinV1(
            roomId: roomId,
            positionX: Double(col.x),
            positionY: Double(col.y),
            positionZ: Double(col.z),
            objectType: pendingType,
            anchorConfidence: confidence
        )
        DispatchQueue.main.async { [weak self] in
            self?.pinsBinding.wrappedValue.append(pin)
        }
        placeMarker(at: result.worldTransform, type: pendingType, in: arView)
    }

    private func placeMarker(
        at transform: simd_float4x4,
        type: PinnedObjectType,
        in arView: ARView
    ) {
        let mesh = MeshResource.generateSphere(radius: 0.05)
        var material = SimpleMaterial()
        material.color = .init(tint: colorForType(type))
        let entity = ModelEntity(mesh: mesh, materials: [material])
        let anchor = AnchorEntity(world: transform)
        anchor.addChild(entity)
        arView.scene.addAnchor(anchor)
    }

    private func colorForType(_ type: PinnedObjectType) -> UIColor {
        switch type {
        case .boiler, .heatPump:    return .orange
        case .flueTerminal:         return .red
        case .hotWaterCylinder:     return .systemBlue
        case .electricalPanel:      return .yellow
        case .gasmeter:             return .purple
        case .nearbyOpening:        return .green
        case .other:                return .lightGray
        }
    }
}
