import SwiftUI
import SceneKit
import ARKit
import simd
import AtlasContracts

// MARK: - GhostBoxARView
//
// ARKit + SceneKit 3D "Ghost Box" visualisation for a placed appliance.
//
// Shows:
//   • A wireframe SCNBox matching the appliance's physical footprint.
//   • A semi-transparent SCNBox for the full service-access clearance zone.
//   • A semi-transparent SCNBox for the install-minimum clearance zone.
//
// Collision detection (Möller–Trumbore):
//   Rays are cast from the centre of the ghost box along the six cardinal
//   axes.  If any LiDAR mesh geometry is closer than the required clearance
//   distance the affected clearance box turns red and a collision flag is set.
//
// Coordinate convention: ARKit right-handed Y-up, metric metres.
//
// Usage:
//   GhostBoxARView(
//       definition: ApplianceProfileLibrary.definition(id: "combi_generic"),
//       fallbackRule: ClearanceEngine.rule(for: .boiler)
//   )

// MARK: - GhostBoxARView (UIViewRepresentable)

struct GhostBoxARView: UIViewRepresentable {

    // MARK: Input

    /// Shared appliance definition driving box dimensions.
    /// When `nil` the `fallbackRule` is used.
    let definition: ApplianceDefinitionV1?

    /// Fallback clearance rule used when no definition is provided.
    let fallbackRule: ClearanceRule?

    // MARK: State callbacks

    /// Called when the user taps to place the ghost box.
    var onPlaced: ((GhostBoxCollisionResult) -> Void)?

    // MARK: UIViewRepresentable

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.autoenablesDefaultLighting = true
        view.automaticallyUpdatesLighting = false

        let config = ARWorldTrackingConfiguration()
        config.sceneReconstruction = .meshWithClassification
        config.environmentTexturing = .none
        view.session.run(config, options: [.removeExistingAnchors, .resetTracking])

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)

        context.coordinator.arView = view
        context.coordinator.definition = definition
        context.coordinator.fallbackRule = fallbackRule
        context.coordinator.onPlaced = onPlaced
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        context.coordinator.definition = definition
        context.coordinator.fallbackRule = fallbackRule
        context.coordinator.onPlaced = onPlaced
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
}

// MARK: - Coordinator

extension GhostBoxARView {

    final class Coordinator: NSObject {

        // MARK: State

        weak var arView: ARSCNView?
        var definition: ApplianceDefinitionV1?
        var fallbackRule: ClearanceRule?
        var onPlaced: ((GhostBoxCollisionResult) -> Void)?

        private var ghostNode: SCNNode?

        // MARK: - Tap handling

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = arView else { return }
            let location = gesture.location(in: view)

            guard let query = view.raycastQuery(
                from: location,
                allowing: .estimatedPlane,
                alignment: .any
            ) else { return }

            let results = view.session.raycast(query)
            guard let hit = results.first else { return }

            let col = hit.worldTransform.columns.3
            let worldPos = simd_float3(col.x, col.y, col.z)

            placeGhostBox(at: worldPos, in: view)
        }

        // MARK: - Ghost box placement

        private func placeGhostBox(at position: simd_float3, in view: ARSCNView) {
            ghostNode?.removeFromParentNode()

            let dims  = resolvedDimensions()
            let clear = resolvedClearances()

            let container = SCNNode()
            container.position = SCNVector3(position.x, position.y, position.z)

            // Layer 1: Physical footprint (wireframe)
            let footprintBox = SCNBox(
                width:  dims.widthM,
                height: dims.heightM,
                length: dims.depthM,
                chamferRadius: 0
            )
            footprintBox.firstMaterial = Self.wireMaterial(color: .systemBlue)
            let footprintNode = SCNNode(geometry: footprintBox)
            footprintNode.position = SCNVector3(0, Float(dims.heightM / 2), 0)
            container.addChildNode(footprintNode)

            // Layer 2: Install-minimum clearance zone
            let installW = dims.widthM + clear.sideM * 2
            let installH = dims.heightM + clear.topM
            let installD = dims.depthM + clear.installMinFrontM + clear.rearM
            let installBox = SCNBox(width: installW, height: installH, length: installD, chamferRadius: 0)
            installBox.firstMaterial = Self.fillMaterial(color: UIColor.systemGreen.withAlphaComponent(0.12))
            let installNode = SCNNode(geometry: installBox)
            installNode.position = SCNVector3(
                0,
                Float(installH / 2),
                Float((clear.installMinFrontM - clear.rearM) / 2)
            )
            container.addChildNode(installNode)

            // Layer 3: Full service-access clearance zone
            let serviceW = dims.widthM + clear.sideM * 2
            let serviceH = dims.heightM + clear.topM
            let serviceD = dims.depthM + clear.frontM + clear.rearM
            let serviceBox = SCNBox(width: serviceW, height: serviceH, length: serviceD, chamferRadius: 0)
            serviceBox.firstMaterial = Self.fillMaterial(color: UIColor.systemCyan.withAlphaComponent(0.08))
            let serviceNode = SCNNode(geometry: serviceBox)
            serviceNode.position = SCNVector3(
                0,
                Float(serviceH / 2),
                Float((clear.frontM - clear.rearM) / 2)
            )
            container.addChildNode(serviceNode)

            view.scene.rootNode.addChildNode(container)
            ghostNode = container

            // Run collision detection against live LiDAR mesh
            let result = checkCollisions(
                at: position,
                dims: dims,
                clear: clear,
                session: view.session
            )

            // Recolour clearance boxes based on collision result
            let serviceColour: UIColor = result.hasConflict ? .systemRed.withAlphaComponent(0.18) : .systemCyan.withAlphaComponent(0.08)
            serviceBox.firstMaterial = Self.fillMaterial(color: serviceColour)

            onPlaced?(result)
        }

        // MARK: - Collision detection (Möller–Trumbore)

        private func checkCollisions(
            at origin: simd_float3,
            dims: ResolvedDimensions,
            clear: ResolvedClearances,
            session: ARSession
        ) -> GhostBoxCollisionResult {
            guard let anchors = session.currentFrame?.anchors else {
                return GhostBoxCollisionResult(axes: [])
            }
            let meshAnchors = anchors.compactMap { $0 as? ARMeshAnchor }

            // Offset to the centre of the appliance body
            let centre = simd_float3(
                origin.x,
                origin.y + Float(dims.heightM / 2),
                origin.z
            )

            // Forward direction: -Z (engineer faces appliance from front)
            let fwd   = simd_float3( 0, 0, -1)
            let right = simd_float3( 1, 0,  0)
            let up    = simd_float3( 0, 1,  0)

            let axisTests: [(GhostBoxAxis, simd_float3, Double)] = [
                (.front,   fwd,    dims.depthM / 2 + clear.frontM),
                (.rear,   -fwd,    dims.depthM / 2 + clear.rearM),
                (.left,  -right,   dims.widthM / 2 + clear.sideM),
                (.right,  right,   dims.widthM / 2 + clear.sideM),
                (.top,    up,      dims.heightM + clear.topM),
            ]

            var axisResults: [GhostBoxAxisResult] = []
            for (axis, direction, required) in axisTests {
                let measured = nearestHit(
                    from: centre,
                    direction: direction,
                    anchors: meshAnchors
                )
                axisResults.append(GhostBoxAxisResult(
                    axis: axis,
                    measuredMetres: measured,
                    requiredMetres: required
                ))
            }

            return GhostBoxCollisionResult(axes: axisResults)
        }

        // MARK: - Mesh ray casting (Möller–Trumbore)

        /// Maximum ray cast distance in metres.
        ///
        /// 8 m is large enough to cover a typical domestic room (≤ 6 m) while
        /// bounding the per-face iteration and keeping frame-rate impact low.
        private let maxRay: Float = 8.0

        private func nearestHit(
            from origin: simd_float3,
            direction: simd_float3,
            anchors: [ARMeshAnchor]
        ) -> Double? {
            let dir = simd_normalize(direction)
            var nearest: Float = maxRay

            for anchor in anchors {
                guard let d = rayVsMeshAnchor(anchor: anchor, origin: origin, direction: dir, cap: nearest) else { continue }
                nearest = d
            }

            return nearest < maxRay ? Double(nearest) : nil
        }

        /// Minimum hit distance in metres to discard intersections that are effectively
        /// on the ray origin's own surface (self-intersection due to floating-point precision).
        private let minimumHitDistanceM: Float = 0.02

        private func rayVsMeshAnchor(
            anchor: ARMeshAnchor,
            origin: simd_float3,
            direction: simd_float3,
            cap: Float
        ) -> Float? {
            let geom  = anchor.geometry
            let xform = anchor.transform
            let inv   = simd_inverse(xform)

            let lo = (inv * simd_float4(origin,    1)).xyz
            let ld = simd_normalize((inv * simd_float4(direction, 0)).xyz)

            let verts = geom.vertices
            let faces = geom.faces
            var best: Float?

            for fi in 0 ..< faces.count {
                let (i0, i1, i2) = faceIndices(faces: faces, at: fi)
                let v0 = vertex(source: verts, at: i0)
                let v1 = vertex(source: verts, at: i1)
                let v2 = vertex(source: verts, at: i2)

                let currentCap = best ?? cap
                if let t = MollerTrumboreIntersection.intersect(
                    rayOrigin: lo, rayDirection: ld, v0: v0, v1: v1, v2: v2
                ), t > minimumHitDistanceM, t < currentCap {
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

        private func vertex(source: ARGeometrySource, at i: Int) -> simd_float3 {
            let ptr = source.buffer.contents().advanced(by: source.offset + i * source.stride)
            return simd_float3(
                ptr.load(fromByteOffset: 0, as: Float.self),
                ptr.load(fromByteOffset: 4, as: Float.self),
                ptr.load(fromByteOffset: 8, as: Float.self)
            )
        }

        // MARK: - Dimension resolution

        private struct ResolvedDimensions {
            let widthM, depthM, heightM: Double
        }

        private struct ResolvedClearances {
            let installMinFrontM, frontM, sideM, rearM, topM: Double
        }

        private func resolvedDimensions() -> ResolvedDimensions {
            if let def = definition {
                return ResolvedDimensions(
                    widthM: def.dimensions.widthM,
                    depthM: def.dimensions.depthM,
                    heightM: def.dimensions.heightM
                )
            }
            let rule = fallbackRule ?? defaultRule
            return ResolvedDimensions(
                widthM: rule.footprintWidthMetres,
                depthM: rule.footprintDepthMetres,
                heightM: rule.minCeilingHeightMetres * 0.5   // approx unit height
            )
        }

        private func resolvedClearances() -> ResolvedClearances {
            if let def = definition {
                return ResolvedClearances(
                    installMinFrontM: def.clearanceRules.installMinFrontM,
                    frontM: def.clearanceRules.frontM,
                    sideM:  def.clearanceRules.sideM,
                    rearM:  def.clearanceRules.rearM,
                    topM:   def.clearanceRules.topM
                )
            }
            let rule = fallbackRule ?? defaultRule
            return ResolvedClearances(
                installMinFrontM: rule.installMinFrontMetres,
                frontM: rule.frontClearanceMetres,
                sideM:  rule.sideClearanceMetres,
                rearM:  rule.rearClearanceMetres,
                topM:   0.20   // reasonable default for ceiling clearance
            )
        }

        private let defaultRule = ClearanceRule(
            footprintWidthMetres:   0.60,
            footprintDepthMetres:   0.50,
            installMinFrontMetres:  0.30,
            frontClearanceMetres:   0.60,
            sideClearanceMetres:    0.15,
            rearClearanceMetres:    0.05,
            minCeilingHeightMetres: 2.00
        )

        // MARK: - SceneKit material helpers

        private static func wireMaterial(color: UIColor) -> SCNMaterial {
            let mat = SCNMaterial()
            mat.diffuse.contents = color
            mat.isDoubleSided = true
            mat.fillMode = .lines
            mat.transparency = 0.85
            return mat
        }

        private static func fillMaterial(color: UIColor) -> SCNMaterial {
            let mat = SCNMaterial()
            mat.diffuse.contents = color
            mat.isDoubleSided = true
            mat.fillMode = .fill
            mat.blendMode = .alpha
            return mat
        }
    }
}

// MARK: - simd_float4 xyz helper (local to this file)

private extension simd_float4 {
    var xyz: simd_float3 { simd_float3(x, y, z) }
}

// MARK: - GhostBoxAxis

/// Directional axis for a ghost box clearance test.
enum GhostBoxAxis: String, Sendable {
    case front, rear, left, right, top
}

// MARK: - GhostBoxAxisResult

/// A single axis clearance measurement from the ghost box collision test.
struct GhostBoxAxisResult: Sendable {
    /// Which axis was tested.
    let axis: GhostBoxAxis
    /// Actual LiDAR-measured distance to the nearest obstacle, or `nil` (open space).
    let measuredMetres: Double?
    /// Minimum required clearance for this axis.
    let requiredMetres: Double

    /// `true` when the measured distance is less than the required clearance.
    var isBlocked: Bool {
        guard let m = measuredMetres else { return false }
        return m < requiredMetres
    }
}

// MARK: - GhostBoxCollisionResult

/// Aggregated result from a ghost box LiDAR collision check.
struct GhostBoxCollisionResult: Sendable {
    let axes: [GhostBoxAxisResult]

    /// `true` when one or more axes are blocked.
    var hasConflict: Bool { axes.contains { $0.isBlocked } }

    /// Blocked axes, if any.
    var blockedAxes: [GhostBoxAxisResult] { axes.filter { $0.isBlocked } }
}

// MARK: - Preview

#if DEBUG
struct GhostBoxARView_Preview: View {
    // Use the well-known "combi_generic" entry from MasterHardwareRegistry.
    // If the registry is ever trimmed and this ID removed, the preview gracefully
    // falls back to the ClearanceEngine generic rule via `fallbackRule`.
    private let previewDefinition = MasterHardwareRegistry.registry.definition(for: "combi_generic")
    private let previewFallback   = ClearanceEngine.rule(for: .boiler)

    var body: some View {
        VStack(spacing: 0) {
            GhostBoxARView(
                definition: previewDefinition,
                fallbackRule: previewFallback
            )
            .frame(height: 400)

            Text("Tap the appliance face to place ghost box")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding()
        }
    }
}

#Preview {
    GhostBoxARView_Preview()
}
#endif
