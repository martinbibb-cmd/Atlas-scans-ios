import Foundation
import ARKit
import AVFoundation
import simd

// MARK: - LiDARClearanceSession
//
// ARKit-backed session that uses LiDAR scene reconstruction to measure
// real-world clearance distances from a tapped appliance position.
//
// Workflow:
//   1. Call start() — begins an ARWorldTrackingConfiguration with mesh scene reconstruction.
//   2. User taps the front face of the appliance; call handleTap(at:).
//   3. The session raycasts against the LiDAR mesh to find the tap position,
//      then casts rays in five directions and computes clearance distances.
//   4. Results are published via latestMeasurement; sessionState advances to .completed.
//   5. Call reset() to clear the placement and allow the user to re-tap.
//   6. Call pause() when the view disappears.
//
// Architecture: all ARKit types are confined to this file.

@MainActor
final class LiDARClearanceSession: NSObject, ObservableObject {

    // MARK: - Session state

    enum SessionState: Equatable {
        /// Device does not support LiDAR / scene reconstruction.
        case unavailable
        /// Camera permission was denied.
        case permissionDenied
        /// Waiting for the user to tap the appliance.
        case waitingForPlacement
        /// Measuring distances from the tapped position.
        case measuring
        /// Measurement completed; latestMeasurement contains the result.
        case completed
        case failed(String)
    }

    @Published private(set) var sessionState: SessionState = .waitingForPlacement
    @Published private(set) var latestMeasurement: LiDARClearanceMeasurement?

    // MARK: - Configuration

    @Published var selectedCategory: ServiceObjectCategory = .boiler {
        didSet { remeasure() }
    }
    @Published var selectedProfileID: String? {
        didSet { remeasure() }
    }

    // MARK: - AR view (UIView exposed for UIViewRepresentable bridging)

    private let _arView = ARSCNView(frame: .zero)
    var arView: UIView { _arView }

    private var applianceWorldPosition: simd_float3?
    private var applianceForwardDirection: simd_float3 = simd_float3(0, 0, -1)

    /// Maximum ray distance in metres.
    private let maxRayMetres: Float = 8.0

    // MARK: - Device capability

    static var isSupported: Bool {
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification)
    }

    // MARK: - Lifecycle

    func start() {
        guard Self.isSupported else {
            sessionState = .unavailable
            return
        }
        checkCameraPermission { [weak self] granted in
            guard let self else { return }
            Task { @MainActor in
                if granted {
                    self.runSession()
                } else {
                    self.sessionState = .permissionDenied
                }
            }
        }
    }

    func pause() {
        _arView.session.pause()
    }

    // MARK: - Tap to place

    func handleTap(at screenPoint: CGPoint) {
        guard sessionState == .waitingForPlacement else { return }

        guard let query = _arView.raycastQuery(
            from: screenPoint,
            allowing: .estimatedPlane,
            alignment: .any
        ) else { return }

        let results = _arView.session.raycast(query)
        guard let first = results.first else { return }

        let col = first.worldTransform.columns.3
        applianceWorldPosition = simd_float3(col.x, col.y, col.z)

        if let frame = _arView.session.currentFrame {
            let camFwd = simd_float3(
                -frame.camera.transform.columns.2.x,
                 0,
                -frame.camera.transform.columns.2.z
            )
            if simd_length(camFwd) > 0.001 {
                applianceForwardDirection = simd_normalize(camFwd)
            }
        }

        sessionState = .measuring
        measure()
    }

    // MARK: - Reset

    func reset() {
        applianceWorldPosition = nil
        latestMeasurement = nil
        sessionState = .waitingForPlacement
    }

    // MARK: - Private: run session

    private func runSession() {
        let config = ARWorldTrackingConfiguration()
        config.sceneReconstruction = .meshWithClassification
        config.environmentTexturing = .none
        _arView.automaticallyUpdatesLighting = false
        _arView.session.run(config, options: [.removeExistingAnchors, .resetTracking])
        sessionState = .waitingForPlacement
    }

    // MARK: - Private: measure

    private func measure() {
        guard let origin = applianceWorldPosition else { return }
        let rule = resolvedRule()

        let fwd   = simd_normalize(simd_float3(applianceForwardDirection.x, 0, applianceForwardDirection.z))
        let right = simd_cross(fwd, simd_float3(0, 1, 0))
        let up    = simd_float3(0, 1, 0)

        // Offset slightly above the tapped surface to avoid immediately hitting the floor.
        let o = simd_float3(origin.x, origin.y + 0.05, origin.z)

        let axes: [LiDARAxisMeasurement] = [
            LiDARAxisMeasurement(
                axis: .front,
                measuredMetres: castRay(from: o, direction: fwd),
                requiredMetres: rule.frontClearanceMetres + rule.footprintDepthMetres / 2
            ),
            LiDARAxisMeasurement(
                axis: .rear,
                measuredMetres: castRay(from: o, direction: -fwd),
                requiredMetres: rule.rearClearanceMetres + rule.footprintDepthMetres / 2
            ),
            LiDARAxisMeasurement(
                axis: .left,
                measuredMetres: castRay(from: o, direction: right),
                requiredMetres: rule.sideClearanceMetres + rule.footprintWidthMetres / 2
            ),
            LiDARAxisMeasurement(
                axis: .right,
                measuredMetres: castRay(from: o, direction: -right),
                requiredMetres: rule.sideClearanceMetres + rule.footprintWidthMetres / 2
            ),
            LiDARAxisMeasurement(
                axis: .ceiling,
                measuredMetres: castRay(from: o, direction: up),
                requiredMetres: rule.minCeilingHeightMetres
            ),
        ]

        let profile = selectedProfileID.flatMap { ApplianceProfileLibrary.profile(id: $0) }
        latestMeasurement = LiDARClearanceMeasurement(
            category: selectedCategory,
            profileName: profile?.displayName,
            axes: axes,
            capturedAt: Date()
        )
        sessionState = .completed
    }

    private func remeasure() {
        guard applianceWorldPosition != nil else { return }
        sessionState = .measuring
        measure()
    }

    private func resolvedRule() -> ClearanceRule {
        if let profileID = selectedProfileID,
           let profile = ApplianceProfileLibrary.profile(id: profileID) {
            return profile.rule
        }
        return ClearanceEngine.rule(for: selectedCategory) ?? ClearanceRule(
            footprintWidthMetres:   0.60,
            footprintDepthMetres:   0.50, installMinFrontMetres: 0.6,
            frontClearanceMetres:   0.60,
            sideClearanceMetres:    0.15,
            rearClearanceMetres:    0.05,
            minCeilingHeightMetres: 2.00
        )
    }

    // MARK: - Private: ray casting against LiDAR mesh

    private func castRay(from origin: simd_float3, direction: simd_float3) -> Double? {
        guard let anchors = _arView.session.currentFrame?.anchors else { return nil }
        let meshAnchors = anchors.compactMap { $0 as? ARMeshAnchor }
        guard !meshAnchors.isEmpty else { return nil }

        let dir = simd_normalize(direction)
        var nearestDist = maxRayMetres

        for anchor in meshAnchors {
            if let d = rayVsMesh(anchor: anchor, origin: origin, direction: dir, cap: nearestDist) {
                nearestDist = d
            }
        }

        return nearestDist < maxRayMetres ? Double(nearestDist) : nil
    }

    private func rayVsMesh(
        anchor: ARMeshAnchor,
        origin: simd_float3,
        direction: simd_float3,
        cap: Float
    ) -> Float? {
        let geom  = anchor.geometry
        let xform = anchor.transform
        let inv   = simd_inverse(xform)

        // Transform ray into mesh-local space.
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
            if let t = mollerTrumbore(o: lo, d: ld, v0: v0, v1: v1, v2: v2),
               t > 0.02, t < currentCap {
                best = t
            }
        }
        return best
    }

    // MARK: - Private: mesh buffer helpers

    private func faceIndices(faces: ARGeometryElement, at fi: Int) -> (Int, Int, Int) {
        let bpi = faces.bytesPerIndex
        let ptr = faces.buffer.contents()
        func idx(_ slot: Int) -> Int {
            let off = (fi * 3 + slot) * bpi
            if bpi == 2 {
                return Int(ptr.load(fromByteOffset: off, as: UInt16.self))
            } else {
                return Int(ptr.load(fromByteOffset: off, as: UInt32.self))
            }
        }
        return (idx(0), idx(1), idx(2))
    }

    private func vertex(source: ARGeometrySource, at i: Int) -> simd_float3 {
        let ptr = source.buffer.contents().advanced(by: source.offset + i * source.stride)
        let x = ptr.load(fromByteOffset: 0, as: Float.self)
        let y = ptr.load(fromByteOffset: 4, as: Float.self)
        let z = ptr.load(fromByteOffset: 8, as: Float.self)
        return simd_float3(x, y, z)
    }

    // MARK: - Private: Möller–Trumbore ray–triangle intersection

    /// Returns the parametric distance `t` (in mesh-local units) to the triangle,
    /// or `nil` when the ray misses.
    private func mollerTrumbore(
        o: simd_float3,
        d: simd_float3,
        v0: simd_float3,
        v1: simd_float3,
        v2: simd_float3
    ) -> Float? {
        let eps: Float = 1e-6
        let e1 = v1 - v0
        let e2 = v2 - v0
        let h  = simd_cross(d, e2)
        let a  = simd_dot(e1, h)
        guard abs(a) > eps else { return nil }
        let f = 1 / a
        let s = o - v0
        let u = f * simd_dot(s, h)
        guard u >= 0, u <= 1 else { return nil }
        let q = simd_cross(s, e1)
        let v = f * simd_dot(d, q)
        guard v >= 0, u + v <= 1 else { return nil }
        let t = f * simd_dot(e2, q)
        return t
    }

    // MARK: - Private: camera permission

    private func checkCameraPermission(completion: @Sendable @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video, completionHandler: completion)
        default:
            completion(false)
        }
    }
}

// MARK: - simd_float4 xyz helper

private extension simd_float4 {
    var xyz: simd_float3 { simd_float3(x, y, z) }
}
