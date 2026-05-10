/// V2GhostAROverlayView — Renders a world-space 3D ghost appliance body and
/// clearance envelope by sharing the live RoomPlan ARSession.
///
/// The ARSCNView uses a fully transparent background so the RoomPlan camera
/// feed underneath remains visible. User interaction is disabled so all touches
/// pass through to the scanning session below.
///
/// Coordinate convention: ARKit right-handed Y-up, units in metres.
///
/// Wall placement orientation:
///   • Local +Z  = outward from wall (face direction / plane normal)
///   • Local +Y  = world up
///   • Local ±X  = wall tangent
///
/// Floor placement: no rotation applied; the box sits upright in world space.

import SwiftUI
import ARKit
import SceneKit
import simd
import AtlasScanCore

// MARK: - V2GhostRenderSpec

/// Lightweight rendering descriptor used by V2GhostAROverlayView.
/// Populated from GhostAppliancePreview inside LiveSpatialCaptureView.
struct V2GhostRenderSpec {
    let worldPositionX: Double
    let worldPositionY: Double
    let worldPositionZ: Double
    let planeNormalX: Double
    let planeNormalY: Double
    let planeNormalZ: Double
    let placementPlane: GhostPlacementPlaneV1
    /// Appliance body dimensions in metres.
    let widthM: Float
    let heightM: Float
    let depthM: Float
    /// Clearance envelope offsets in metres.
    let clearanceLeftM: Float
    let clearanceRightM: Float
    let clearanceTopM: Float
    let clearanceBottomM: Float
    let clearanceFrontM: Float
    let clearanceBackM: Float

    var isTransformValid: Bool {
        let n = SIMD3<Double>(planeNormalX, planeNormalY, planeNormalZ)
        return simd_length(n) > 0.001
    }
}

// MARK: - V2GhostAROverlayView

struct V2GhostAROverlayView: UIViewRepresentable {

    /// Existing RoomPlan ARSession — shared so the ghost appears in the same
    /// world coordinate frame as the room mesh.
    let arSession: ARSession

    /// When non-nil the ghost body + clearance envelope are rendered.
    /// Setting to nil removes any existing nodes from the scene.
    let spec: V2GhostRenderSpec?

    /// Plane type used to constrain drag raycasts: wall → vertical, floor → horizontal.
    var dragPlane: GhostPlacementPlaneV1 = .wall

    /// Called on the main thread each time the user drags, with the raw
    /// AR-surface hit position and outward surface normal (both in metres).
    /// The caller is responsible for applying the appliance half-depth/height
    /// offset before updating the ghostPreview world position.
    var onGhostDragged: ((SIMD3<Double>, SIMD3<Double>) -> Void)?

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)

        // Share the live RoomPlan session — no new session is started.
        view.session = arSession
        view.scene = SCNScene()

        // Transparent background: the RoomPlan camera feed shows through the
        // underlying UIView layer.
        view.scene.background.contents = UIColor.clear
        view.backgroundColor = .clear
        view.isOpaque = false

        // Lighting is provided by the shared session; we add one fill light so
        // the translucent ghost geometry is visible in dim environments.
        view.autoenablesDefaultLighting = false
        let omni = SCNLight()
        omni.type = .omni
        omni.intensity = 800
        let lightNode = SCNNode()
        lightNode.light = omni
        lightNode.position = SCNVector3(0, 3, 0)
        view.scene.rootNode.addChildNode(lightNode)

        // Interaction enabled only while a ghost is active so that all other
        // touches pass through to the RoomPlan session underneath.
        view.isUserInteractionEnabled = spec != nil

        // Pan gesture drives drag-to-move; the coordinator raycasts at the
        // touch location and fires onGhostDragged on every frame.
        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(V2GhostARCoordinator.handlePan(_:))
        )
        view.addGestureRecognizer(pan)

        context.coordinator.sceneView = view
        context.coordinator.dragPlane = dragPlane
        context.coordinator.onGhostDragged = onGhostDragged
        context.coordinator.update(spec: spec)
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        // Sync interaction state and drag settings before updating nodes so
        // that a newly placed ghost immediately accepts drag input.
        uiView.isUserInteractionEnabled = spec != nil
        context.coordinator.dragPlane = dragPlane
        context.coordinator.onGhostDragged = onGhostDragged
        context.coordinator.update(spec: spec)
    }

    func makeCoordinator() -> V2GhostARCoordinator {
        V2GhostARCoordinator()
    }
}

// MARK: - V2GhostARCoordinator

final class V2GhostARCoordinator: NSObject {

    weak var sceneView: ARSCNView?
    private var containerNode: SCNNode?

    /// Current placement plane, used to select raycast target alignment during drag.
    var dragPlane: GhostPlacementPlaneV1 = .wall
    /// Called on every pan gesture frame with (rawHitPosition, planeNormal).
    var onGhostDragged: ((SIMD3<Double>, SIMD3<Double>) -> Void)?

    // MARK: - Update

    func update(spec: V2GhostRenderSpec?) {
        guard let spec else {
            containerNode?.removeFromParentNode()
            containerNode = nil
            #if DEBUG
            print("[V2GhostAR] ghostTransform valid=— renderer=idle nodes=0")
            #endif
            return
        }

        guard let sceneView else { return }

        // If nodes already exist, reposition without rebuilding geometry.
        // This keeps drag updates smooth by skipping node allocation overhead.
        if let container = containerNode {
            container.position = SCNVector3(
                Float(spec.worldPositionX),
                Float(spec.worldPositionY),
                Float(spec.worldPositionZ)
            )
            container.orientation = worldOrientation(for: spec)
            return
        }

        // First placement: build nodes from scratch.
        let node = makeGhostContainerNode(spec: spec)
        sceneView.scene.rootNode.addChildNode(node)
        containerNode = node

        #if DEBUG
        let nodeCount = sceneView.scene.rootNode.childNodes.count
        let dims = String(
            format: "%.3f×%.3f×%.3f m",
            spec.widthM, spec.heightM, spec.depthM
        )
        print(
            "[V2GhostAR] ghostTransform valid=\(spec.isTransformValid) dims=\(dims)"
                + " renderer=active nodes=\(nodeCount)"
        )
        #endif
    }

    // MARK: - Drag gesture

    /// Raycasts at the pan location, preferring the plane alignment that matches
    /// `dragPlane` (vertical for wall, horizontal for floor/worktop/ceiling),
    /// then falls back to any alignment if no aligned surface is found.
    @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard gesture.state == .began || gesture.state == .changed,
              let sceneView else { return }

        let location = gesture.location(in: sceneView)
        let preferredAlignment: ARRaycastQuery.TargetAlignment = dragPlane == .floor
            ? .horizontal
            : .vertical

        let targets: [ARRaycastQuery.Target] = [
            .existingPlaneGeometry,
            .existingPlaneInfinite,
            .estimatedPlane,
        ]

        // Preferred-alignment pass.
        for target in targets {
            if let query = sceneView.raycastQuery(from: location, allowing: target, alignment: preferredAlignment),
               let result = sceneView.session.raycast(query).first {
                fireCallback(from: result)
                return
            }
        }

        // Fallback: any alignment so the ghost tracks even in sparse scenes.
        for target in targets {
            if let query = sceneView.raycastQuery(from: location, allowing: target, alignment: .any),
               let result = sceneView.session.raycast(query).first {
                fireCallback(from: result)
                return
            }
        }
    }

    private func fireCallback(from result: ARRaycastResult) {
        let col3 = result.worldTransform.columns.3
        let forward = result.worldTransform.columns.2
        let position = SIMD3<Double>(Double(col3.x), Double(col3.y), Double(col3.z))
        // ARKit forward (columns.2) points away from the surface into the room;
        // negate it to get the outward wall/floor normal used by moveGhostPreview.
        let normal = SIMD3<Double>(Double(-forward.x), Double(-forward.y), Double(-forward.z))
        DispatchQueue.main.async { [weak self] in
            self?.onGhostDragged?(position, normal)
        }
    }

    // MARK: - Node construction

    private func makeGhostContainerNode(spec: V2GhostRenderSpec) -> SCNNode {
        let container = SCNNode()
        container.position = SCNVector3(
            Float(spec.worldPositionX),
            Float(spec.worldPositionY),
            Float(spec.worldPositionZ)
        )
        container.orientation = worldOrientation(for: spec)

        // Layer 1: Appliance body — wireframe box matching the physical footprint.
        addBodyNode(to: container, spec: spec)

        // Layer 2: Clearance envelope — translucent box sized for regulatory offsets.
        addClearanceNode(to: container, spec: spec)

        return container
    }

    private func addBodyNode(to container: SCNNode, spec: V2GhostRenderSpec) {
        let box = SCNBox(
            width:  CGFloat(spec.widthM),
            height: CGFloat(spec.heightM),
            length: CGFloat(spec.depthM),
            chamferRadius: 0
        )
        box.firstMaterial = wireMaterial(color: .systemBlue)
        container.addChildNode(SCNNode(geometry: box))
    }

    private func addClearanceNode(to container: SCNNode, spec: V2GhostRenderSpec) {
        let envW = spec.widthM  + spec.clearanceLeftM  + spec.clearanceRightM
        let envH = spec.heightM + spec.clearanceTopM   + spec.clearanceBottomM
        let envD = spec.depthM  + spec.clearanceFrontM + spec.clearanceBackM

        let envBox = SCNBox(
            width:  CGFloat(envW),
            height: CGFloat(envH),
            length: CGFloat(envD),
            chamferRadius: 0
        )
        envBox.firstMaterial = fillMaterial(color: UIColor.systemCyan.withAlphaComponent(0.13))

        // Offset the envelope centre relative to the body centre so asymmetric
        // clearances (e.g. larger front than rear) sit correctly in world space.
        //
        // Convention (local frame):
        //   +Z = outward from wall / forward face of appliance
        //   +Y = up
        //   +X = wall tangent (right of engineer facing appliance)
        let offsetX = (spec.clearanceLeftM  - spec.clearanceRightM)  / 2
        let offsetY = (spec.clearanceTopM   - spec.clearanceBottomM) / 2
        let offsetZ = (spec.clearanceFrontM - spec.clearanceBackM)   / 2

        let envNode = SCNNode(geometry: envBox)
        envNode.position = SCNVector3(offsetX, offsetY, offsetZ)
        container.addChildNode(envNode)
    }

    // MARK: - Orientation

    /// Computes the SCNNode orientation so that local +Z aligns with the outward
    /// wall/placement normal, local +Y stays vertical.
    private func worldOrientation(for spec: V2GhostRenderSpec) -> SCNQuaternion {
        switch spec.placementPlane {

        case .wall:
            // Project normal into the XZ horizontal plane (walls are vertical).
            let flat = simd_float3(
                Float(spec.planeNormalX),
                0,
                Float(spec.planeNormalZ)
            )
            let len = simd_length(flat)
            guard len > 0.001 else { return SCNQuaternion(0, 0, 0, 1) }
            let target = flat / len
            // Rotate the default forward (0, 0, 1) to the outward wall normal.
            let q = simd_quatf(from: SIMD3<Float>(0, 0, 1), to: target)
            return SCNVector4(q.vector.x, q.vector.y, q.vector.z, q.vector.w)

        case .floor, .worktop:
            // No rotation: box sits upright, +Y is already up.
            return SCNQuaternion(0, 0, 0, 1)

        case .ceiling:
            // Flip 180° around Z: +Y points down.
            let q = simd_quatf(angle: .pi, axis: SIMD3<Float>(0, 0, 1))
            return SCNVector4(q.vector.x, q.vector.y, q.vector.z, q.vector.w)

        case .unknown:
            return SCNQuaternion(0, 0, 0, 1)
        }
    }

    // MARK: - Materials

    private func wireMaterial(color: UIColor) -> SCNMaterial {
        let mat = SCNMaterial()
        // Use alpha on the diffuse colour rather than the deprecated `transparency`
        // property to ensure consistent rendering across SceneKit versions.
        mat.diffuse.contents = color.withAlphaComponent(0.80)
        mat.isDoubleSided = true
        mat.fillMode = .lines
        return mat
    }

    private func fillMaterial(color: UIColor) -> SCNMaterial {
        let mat = SCNMaterial()
        mat.diffuse.contents = color
        mat.isDoubleSided = true
        mat.fillMode = .fill
        mat.blendMode = .alpha
        return mat
    }
}
