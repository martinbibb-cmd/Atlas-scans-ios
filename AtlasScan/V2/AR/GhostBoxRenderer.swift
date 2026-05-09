/// GhostBoxRenderer — Manages ghost-box entity creation and clearance conflict highlighting.
///
/// Ghost boxes are rendered with a low-opacity cyan material so they don't obscure the
/// underlying room geometry. After placement, each box is checked against the live LiDAR
/// mesh using Möller–Trumbore ray casting; boxes that intersect nearby surfaces are
/// recoloured red so the engineer immediately sees a clearance conflict.

import Foundation
import RealityKit
import ARKit
import simd
import AtlasScanCore

final class GhostBoxRenderer: NSObject {
    weak var arView: ARView?
    private var rootAnchor: AnchorEntity?

    /// Maximum ray-cast distance in metres (covers typical domestic room with margin).
    private let maxRayM: Float = 8.0

    /// Minimum hit distance to discard self-intersection artefacts.
    private let minHitDistM: Float = 0.02

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
            checkCollisions(for: entity, in: arView)
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
        // Lowered opacity so the box doesn't obscure the underlying room geometry.
        material.color = .init(tint: .cyan.withAlphaComponent(0.15))
        material.metallic = 0
        material.roughness = 1
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.position = SIMD3(Float(pin.positionX), Float(pin.positionY), Float(pin.positionZ))
        return entity
    }

    // MARK: - Collision detection (Möller–Trumbore)

    /// Casts rays along the six cardinal axes from the entity centre against the live
    /// LiDAR mesh.  Recolours the entity red when any axis is blocked closer than the
    /// box half-extent in that direction (i.e. the box intersects nearby geometry).
    private func checkCollisions(for entity: ModelEntity, in arView: ARView) {
        guard let frame = arView.session.currentFrame else { return }
        let meshAnchors = frame.anchors.compactMap { $0 as? ARMeshAnchor }
        guard !meshAnchors.isEmpty else { return }

        let centre = entity.position(relativeTo: nil)
        let extents = entity.model?.mesh.bounds.extents ?? SIMD3<Float>(0.6, 0.8, 0.5)
        let halfW = extents.x / 2
        let halfH = extents.y / 2
        let halfD = extents.z / 2

        // Six cardinal directions with the corresponding half-extent clearance required.
        let axisTests: [(SIMD3<Float>, Float)] = [
            (SIMD3( 1, 0, 0), halfW),
            (SIMD3(-1, 0, 0), halfW),
            (SIMD3( 0, 1, 0), halfH),
            (SIMD3( 0,-1, 0), halfH),
            (SIMD3( 0, 0, 1), halfD),
            (SIMD3( 0, 0,-1), halfD),
        ]

        var hasConflict = false
        for (direction, required) in axisTests {
            if let dist = nearestMeshHit(from: centre, direction: direction, anchors: meshAnchors),
               dist < required {
                hasConflict = true
                break
            }
        }

        if hasConflict {
            var redMaterial = SimpleMaterial()
            redMaterial.color = .init(tint: .red.withAlphaComponent(0.35))
            redMaterial.metallic = 0
            redMaterial.roughness = 1
            entity.model?.materials = [redMaterial]
        }
    }

    private func nearestMeshHit(
        from origin: SIMD3<Float>,
        direction: SIMD3<Float>,
        anchors: [ARMeshAnchor]
    ) -> Float? {
        let dir = simd_normalize(direction)
        var nearest = maxRayM
        for anchor in anchors {
            if let d = rayVsMeshAnchor(anchor: anchor, origin: origin, direction: dir, cap: nearest) {
                nearest = d
            }
        }
        return nearest < maxRayM ? nearest : nil
    }

    private func rayVsMeshAnchor(
        anchor: ARMeshAnchor,
        origin: SIMD3<Float>,
        direction: SIMD3<Float>,
        cap: Float
    ) -> Float? {
        let inv = simd_inverse(anchor.transform)
        // Transform ray into mesh-local space.
        let lo = (inv * SIMD4<Float>(origin, 1)).xyz
        let ld = simd_normalize((inv * SIMD4<Float>(direction, 0)).xyz)

        let verts = anchor.geometry.vertices
        let faces = anchor.geometry.faces
        var best: Float?

        for fi in 0 ..< faces.count {
            let (i0, i1, i2) = faceIndices(faces: faces, at: fi)
            let v0 = meshVertex(source: verts, at: i0)
            let v1 = meshVertex(source: verts, at: i1)
            let v2 = meshVertex(source: verts, at: i2)
            let currentCap = best ?? cap
            if let t = MollerTrumboreIntersection.intersect(
                rayOrigin: lo, rayDirection: ld, v0: v0, v1: v1, v2: v2
            ), t > minHitDistM, t < currentCap {
                best = t
            }
        }
        return best
    }

    // MARK: - ARMeshGeometry buffer helpers

    private func faceIndices(faces: ARGeometryElement, at fi: Int) -> (Int, Int, Int) {
        let bpi = faces.bytesPerIndex
        let ptr = faces.buffer.contents()
        func idx(_ slot: Int) -> Int {
            let off = (fi * 3 + slot) * bpi
            return bpi == 2
                ? Int(ptr.load(fromByteOffset: off, as: UInt16.self))
                : Int(ptr.load(fromByteOffset: off, as: UInt32.self))
        }
        return (idx(0), idx(1), idx(2))
    }

    private func meshVertex(source: ARGeometrySource, at i: Int) -> SIMD3<Float> {
        let ptr = source.buffer.contents().advanced(by: source.offset + i * source.stride)
        return SIMD3<Float>(
            ptr.load(fromByteOffset: 0, as: Float.self),
            ptr.load(fromByteOffset: 4, as: Float.self),
            ptr.load(fromByteOffset: 8, as: Float.self)
        )
    }
}

// MARK: - SIMD4 helper

private extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> { SIMD3(x, y, z) }
}

// MARK: - HardwareRegistryV1 convenience

extension HardwareRegistryV1 {
    func allSpecs() -> [HardwareSpecV1] {
        allSpecs(ofType: .boiler) + allSpecs(ofType: .heatPump)
            + allSpecs(ofType: .hotWaterCylinder) + allSpecs(ofType: .pressureVessel)
    }
}
