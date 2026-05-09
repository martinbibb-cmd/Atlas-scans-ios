/// RoomPlanCoordinator — Bridges RoomPlan delegate callbacks to v2 model types.

import SwiftUI
import RoomPlan
import ARKit
import simd
import UIKit
import AtlasScanCore

final class RoomPlanCoordinator: NSObject, RoomCaptureSessionDelegate {
    var captureView: RoomCaptureView?
    private var capturedRoomBinding: Binding<RoomCaptureV2?>

    /// Optional pre-assigned room ID so photos/pins captured before Finish
    /// share the same UUID as the room that gets saved on completion.
    var prospectiveRoomId: UUID?

    /// Called on the main thread each time RoomPlan publishes an incremental
    /// update. Use this to drive the live mini-map polygon.
    var onLiveVertices: (([Vertex2D]) -> Void)?
    /// Called when capture ends but RoomPlan did not produce a usable room.
    var onCaptureEndedWithoutRoom: (() -> Void)?

    /// Set to true once stopSession() has been called so updateUIViewController
    /// does not fire a second stop.
    private(set) var isStopped = false
    private var latestCapturedRoom: CapturedRoom?

    init(capturedRoom: Binding<RoomCaptureV2?>) {
        self.capturedRoomBinding = capturedRoom
    }

    func startSession() {
        isStopped = false
        let config = RoomCaptureSession.Configuration()
        captureView?.captureSession.delegate = self
        captureView?.captureSession.run(configuration: config)
    }

    func stopSession() {
        guard !isStopped else { return }
        isStopped = true
        captureView?.captureSession.stop()
    }

    func capturePointAtViewCenter() -> LiveCapturePointProbeResultV1 {
        guard let captureView else {
            return LiveCapturePointProbeResultV1(
                screenPoint: CGPointCodable(x: 0.5, y: 0.5),
                worldPosition: nil,
                anchorConfidence: .screenOnly,
                hitNormal: nil,
                anchorId: nil,
                worldTransform: nil,
                debugDiagnostics: CaptureProbeDiagnosticsV1(
                    raycastAttempted: false,
                    resultType: .failed,
                    hitDistanceM: nil,
                    planeAlignment: "none",
                    trackingState: "viewUnavailable"
                )
            )
        }

        let bounds = captureView.bounds
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let normalizedPoint = CGPointCodable(
            x: bounds.width > 0 ? center.x / bounds.width : 0.5,
            y: bounds.height > 0 ? center.y / bounds.height : 0.5
        )

        guard let frame = captureView.captureSession.arSession.currentFrame else {
            return LiveCapturePointProbeResultV1(
                screenPoint: normalizedPoint,
                worldPosition: nil,
                anchorConfidence: .screenOnly,
                hitNormal: nil,
                anchorId: nil,
                worldTransform: nil,
                debugDiagnostics: CaptureProbeDiagnosticsV1(
                    raycastAttempted: false,
                    resultType: .failed,
                    hitDistanceM: nil,
                    planeAlignment: "none",
                    trackingState: "frameUnavailable"
                )
            )
        }
        let samplePoints = reticleSamplePoints(around: center, in: bounds)
        var candidates: [ProbeHitCandidate] = []
        for samplePoint in samplePoints {
            if let raycastCandidate = raycastCandidate(
                from: samplePoint,
                frame: frame,
                captureView: captureView
            ) {
                candidates.append(raycastCandidate)
            }
            if let query = frame.raycastQuery(from: samplePoint, allowing: .estimatedPlane, alignment: .any) {
                if let featurePointCandidate = featurePointCandidate(from: query, frame: frame) {
                    candidates.append(featurePointCandidate)
                }
                if let roomMeshCandidate = roomMeshCandidate(from: query) {
                    candidates.append(roomMeshCandidate)
                }
            }
        }

        guard let best = selectPreferredCandidate(from: candidates) else {
            return LiveCapturePointProbeResultV1(
                screenPoint: normalizedPoint,
                worldPosition: nil,
                anchorConfidence: .screenOnly,
                hitNormal: nil,
                anchorId: nil,
                worldTransform: nil,
                debugDiagnostics: CaptureProbeDiagnosticsV1(
                    raycastAttempted: !samplePoints.isEmpty,
                    resultType: .failed,
                    hitDistanceM: nil,
                    planeAlignment: "none",
                    trackingState: trackingStateDescription(frame.camera.trackingState)
                )
            )
        }

        let anchor = ARAnchor(transform: best.worldTransform)
        captureView.captureSession.arSession.add(anchor: anchor)
        let position = best.worldTransform.columns.3
        let forward = best.worldTransform.columns.2
        let normal = SIMD3(
            Double(-forward.x),
            Double(-forward.y),
            Double(-forward.z)
        )
        let confidence: SpatialPinAnchorConfidence = .worldLocked

        return LiveCapturePointProbeResultV1(
            screenPoint: normalizedPoint,
            worldPosition: SIMD3(Double(position.x), Double(position.y), Double(position.z)),
            anchorConfidence: confidence,
            hitNormal: normal,
            anchorId: anchor.identifier,
            worldTransform: worldTransform(from: best.worldTransform),
            debugDiagnostics: CaptureProbeDiagnosticsV1(
                raycastAttempted: true,
                resultType: best.resultType,
                hitDistanceM: Double(best.distanceMeters),
                planeAlignment: planeAlignmentDescription(best.planeAlignment),
                trackingState: trackingStateDescription(frame.camera.trackingState)
            )
        )
    }

    func worldTransform(for anchorId: UUID) -> WorldTransformV1? {
        guard
            let frame = captureView?.captureSession.arSession.currentFrame,
            let anchor = frame.anchors.first(where: { $0.identifier == anchorId })
        else {
            return nil
        }
        return worldTransform(from: anchor.transform)
    }

    func projectNormalizedScreenPoint(for worldPosition: SIMD3<Double>) -> CGPointCodable? {
        guard
            let captureView,
            let frame = captureView.captureSession.arSession.currentFrame
        else {
            return nil
        }

        let viewportSize = captureView.bounds.size
        guard viewportSize.width > 0, viewportSize.height > 0 else { return nil }

        let projected = frame.camera.projectPoint(
            SIMD3<Float>(Float(worldPosition.x), Float(worldPosition.y), Float(worldPosition.z)),
            orientation: .portrait,
            viewportSize: viewportSize
        )
        let worldPoint = SIMD4<Float>(Float(worldPosition.x), Float(worldPosition.y), Float(worldPosition.z), 1)
        let cameraSpacePoint = simd_inverse(frame.camera.transform) * worldPoint
        guard cameraSpacePoint.z < 0 else { return nil }
        let reciprocalWidth = 1.0 / viewportSize.width
        let reciprocalHeight = 1.0 / viewportSize.height

        return CGPointCodable(
            x: Double(projected.x * reciprocalWidth),
            y: Double(projected.y * reciprocalHeight)
        )
    }

    // MARK: - RoomCaptureSessionDelegate

    /// Live incremental update — extract the current floor polygon for the mini-map.
    func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
        latestCapturedRoom = room
        let vertices = polygonVertices(from: room)
        DispatchQueue.main.async { [weak self] in
            self?.onLiveVertices?(vertices)
        }
    }

    func captureSession(
        _ session: RoomCaptureSession,
        didEndWith data: CapturedRoomData,
        error: (Error)?
    ) {
        Task { @MainActor in
            if let error {
                print("[RoomPlanCoordinator] Capture ended with error: \(error.localizedDescription)")
                onCaptureEndedWithoutRoom?()
                return
            }
            do {
                // Empty options: no post-processing overrides needed for the default capture.
                let processed = try await RoomBuilder(options: []).capturedRoom(from: data)
                capturedRoomBinding.wrappedValue = bridgeToV2(processed)
            } catch {
                print("[RoomPlanCoordinator] RoomBuilder failed: \(error.localizedDescription)")
                onCaptureEndedWithoutRoom?()
            }
        }
    }

    // MARK: - Private helpers

    private let minimumWallLengthMeters: Float = 0.01
    private let polygonToleranceMin: Float = 0.01
    private let polygonToleranceFraction: Float = 0.10
    private let polygonToleranceMax: Float = 0.25
    private let minimumAreaM2 = 0.05
    private let reticleToleranceRadiusPixels: CGFloat = 18
    private let featurePointToleranceMeters: Float = 0.08
    private let roomSurfaceToleranceMeters: Float = 0.06
    private let featurePointToleranceDistanceMultiplier: Float = 0.04
    private let featurePointLateralTieBreakThreshold: Float = 0.005
    private let rayDirectionEpsilon: Float = 1e-4
    private let normalLengthEpsilon: Float = 1e-4
    private let parallelNormalThreshold: Float = 0.95
    private let horizontalAlignmentThreshold: Float = 0.75
    private let reticleSamplePattern: [CGPoint] = [
        CGPoint(x: 0, y: 0),
        CGPoint(x: 1, y: 0),
        CGPoint(x: -1, y: 0),
        CGPoint(x: 0, y: 1),
        CGPoint(x: 0, y: -1),
        CGPoint(x: 0.7071, y: 0.7071),
        CGPoint(x: -0.7071, y: 0.7071),
        CGPoint(x: 0.7071, y: -0.7071),
        CGPoint(x: -0.7071, y: -0.7071),
    ]

    private struct ProbeHitCandidate {
        let worldTransform: simd_float4x4
        let distanceMeters: Float
        let resultType: CaptureProbeResultTypeV1
        let planeAlignment: ARRaycastQuery.TargetAlignment
        let confidenceRank: Int
    }

    /// Samples a small 9-point screen-space pattern around the reticle center
    /// (center, cardinal, diagonals) to avoid requiring a pixel-perfect hit.
    private func reticleSamplePoints(around center: CGPoint, in bounds: CGRect) -> [CGPoint] {
        return reticleSamplePattern.map { offset in
            CGPoint(
                x: min(max(center.x + (offset.x * reticleToleranceRadiusPixels), bounds.minX), bounds.maxX),
                y: min(max(center.y + (offset.y * reticleToleranceRadiusPixels), bounds.minY), bounds.maxY)
            )
        }
    }

    /// Layered ARKit raycast strategy: prefer confirmed plane geometry, then
    /// infinite planes, and finally estimated planes as lowest confidence.
    private func raycastCandidate(
        from point: CGPoint,
        frame: ARFrame,
        captureView: RoomCaptureView
    ) -> ProbeHitCandidate? {
        let plans: [(ARRaycastQuery.Target, CaptureProbeResultTypeV1, Int)] = [
            (.existingPlaneGeometry, .existingPlaneGeometry, 5),
            (.existingPlaneInfinite, .existingPlaneInfinite, 4),
            (.estimatedPlane, .estimatedPlane, 2),
        ]
        let cameraPosition = SIMD3<Float>(
            frame.camera.transform.columns.3.x,
            frame.camera.transform.columns.3.y,
            frame.camera.transform.columns.3.z
        )

        for (target, type, rank) in plans {
            guard let query = frame.raycastQuery(from: point, allowing: target, alignment: .any) else { continue }
            guard let result = captureView.captureSession.arSession.raycast(query).first else { continue }
            let hit = SIMD3<Float>(
                result.worldTransform.columns.3.x,
                result.worldTransform.columns.3.y,
                result.worldTransform.columns.3.z
            )
            return ProbeHitCandidate(
                worldTransform: result.worldTransform,
                distanceMeters: simd_distance(cameraPosition, hit),
                resultType: type,
                planeAlignment: result.targetAlignment,
                confidenceRank: rank
            )
        }
        return nil
    }

    /// Finds a feature-point-backed hit by projecting the query ray through raw
    /// AR feature points, applying lateral tolerance, then tie-breaking by
    /// nearest lateral distance and then depth along ray.
    private func featurePointCandidate(from query: ARRaycastQuery, frame: ARFrame) -> ProbeHitCandidate? {
        guard let points = frame.rawFeaturePoints?.points, !points.isEmpty else { return nil }
        let origin = query.origin
        let direction = simd_normalize(query.direction)
        var best: (point: SIMD3<Float>, along: Float, lateral: Float)?

        for point in points {
            let delta = point - origin
            let along = simd_dot(delta, direction)
            guard along > 0 else { continue }
            let lateral = simd_length(simd_cross(delta, direction))
            let maxTolerance = max(featurePointToleranceMeters, along * featurePointToleranceDistanceMultiplier)
            guard lateral <= maxTolerance else { continue }
            if let current = best {
                if shouldReplaceFeatureCandidate(
                    newLateral: lateral,
                    newAlong: along,
                    currentLateral: current.lateral,
                    currentAlong: current.along
                ) {
                    best = (point, along, lateral)
                }
            } else {
                best = (point, along, lateral)
            }
        }

        guard let best else { return nil }
        let normal = simd_normalize(-direction)
        let transform = worldTransform(position: best.point, normal: normal)
        return ProbeHitCandidate(
            worldTransform: transform,
            distanceMeters: best.along,
            resultType: .featurePoint,
            planeAlignment: alignment(from: normal),
            confidenceRank: 3
        )
    }

    /// Fallback that intersects the reticle ray with latest RoomPlan-rendered
    /// wall/floor surfaces so visible room geometry can be used for anchoring.
    private func roomMeshCandidate(from query: ARRaycastQuery) -> ProbeHitCandidate? {
        guard let room = latestCapturedRoom else { return nil }
        let surfaces = room.walls + room.floors
        let origin = query.origin
        let direction = simd_normalize(query.direction)
        var best: (point: SIMD3<Float>, normal: SIMD3<Float>, distance: Float)?

        for surface in surfaces {
            guard let hit = intersectRay(origin: origin, direction: direction, with: surface) else { continue }
            if let current = best {
                if hit.distance < current.distance {
                    best = hit
                }
            } else {
                best = hit
            }
        }

        guard let best else { return nil }
        return ProbeHitCandidate(
            worldTransform: worldTransform(position: best.point, normal: best.normal),
            distanceMeters: best.distance,
            resultType: .roomMesh,
            planeAlignment: alignment(from: best.normal),
            confidenceRank: 3
        )
    }

    /// Intersects the ray in surface-local space using the smallest-dimension
    /// axis as thickness/plane normal, then checks in-plane extents with a
    /// tolerance expansion to be robust near edges.
    private func intersectRay(
        origin: SIMD3<Float>,
        direction: SIMD3<Float>,
        with surface: CapturedRoom.Surface
    ) -> (point: SIMD3<Float>, normal: SIMD3<Float>, distance: Float)? {
        let worldToLocal = simd_inverse(surface.transform)
        let localOrigin = transformPoint(origin, with: worldToLocal)
        let localDirection = transformDirection(direction, with: worldToLocal)

        let thicknessAxis = thicknessAxis(for: surface)
        let axisA: Int
        let axisB: Int
        let halfA: Float
        let halfB: Float
        switch thicknessAxis {
        case 0:
            axisA = 1
            axisB = 2
            halfA = surface.dimensions.y / 2 + roomSurfaceToleranceMeters
            halfB = surface.dimensions.z / 2 + roomSurfaceToleranceMeters
        case 1:
            axisA = 0
            axisB = 2
            halfA = surface.dimensions.x / 2 + roomSurfaceToleranceMeters
            halfB = surface.dimensions.z / 2 + roomSurfaceToleranceMeters
        default:
            axisA = 0
            axisB = 1
            halfA = surface.dimensions.x / 2 + roomSurfaceToleranceMeters
            halfB = surface.dimensions.y / 2 + roomSurfaceToleranceMeters
        }

        let directionThickness = localDirection[thicknessAxis]
        guard abs(directionThickness) > rayDirectionEpsilon else { return nil }
        // Solve the ray/plane equation in local space to find distance t.
        let t = -localOrigin[thicknessAxis] / directionThickness
        guard t > 0 else { return nil }

        let localHit = localOrigin + localDirection * t
        guard abs(localHit[axisA]) <= halfA, abs(localHit[axisB]) <= halfB else { return nil }

        var localNormal = SIMD3<Float>(0, 0, 0)
        localNormal[thicknessAxis] = directionThickness > 0 ? -1 : 1

        let worldPoint = transformPoint(localHit, with: surface.transform)
        let worldNormal = simd_normalize(transformDirection(localNormal, with: surface.transform))
        let distance = simd_distance(origin, worldPoint)
        return (worldPoint, worldNormal, distance)
    }

    /// Builds a stable world transform from hit position + surface normal by
    /// constructing an orthonormal basis with an alternate up vector fallback
    /// when the normal is nearly parallel to world-up.
    private func worldTransform(position: SIMD3<Float>, normal: SIMD3<Float>) -> simd_float4x4 {
        let safeNormal = simd_length(normal) > normalLengthEpsilon ? simd_normalize(normal) : SIMD3<Float>(0, 1, 0)
        var up = SIMD3<Float>(0, 1, 0)
        if abs(simd_dot(up, safeNormal)) > parallelNormalThreshold {
            up = SIMD3<Float>(0, 0, 1)
        }
        let right = simd_normalize(simd_cross(up, safeNormal))
        let adjustedUp = simd_normalize(simd_cross(safeNormal, right))
        let forward = -safeNormal
        return simd_float4x4(
            SIMD4<Float>(right.x, right.y, right.z, 0),
            SIMD4<Float>(adjustedUp.x, adjustedUp.y, adjustedUp.z, 0),
            SIMD4<Float>(forward.x, forward.y, forward.z, 0),
            SIMD4<Float>(position.x, position.y, position.z, 1)
        )
    }

    private func alignment(from normal: SIMD3<Float>) -> ARRaycastQuery.TargetAlignment {
        abs(normal.y) >= horizontalAlignmentThreshold ? .horizontal : .vertical
    }

    private func shouldReplaceFeatureCandidate(
        newLateral: Float,
        newAlong: Float,
        currentLateral: Float,
        currentAlong: Float
    ) -> Bool {
        if newLateral < currentLateral {
            return true
        }
        if abs(newLateral - currentLateral) >= featurePointLateralTieBreakThreshold {
            return false
        }
        return newAlong < currentAlong
    }

    private func thicknessAxis(for surface: CapturedRoom.Surface) -> Int {
        let x = surface.dimensions.x
        let y = surface.dimensions.y
        let z = surface.dimensions.z
        if x <= y && x <= z { return 0 }
        if y <= x && y <= z { return 1 }
        return 2
    }

    private func transformPoint(_ point: SIMD3<Float>, with matrix: simd_float4x4) -> SIMD3<Float> {
        let transformed = matrix * SIMD4<Float>(point.x, point.y, point.z, 1)
        return SIMD3<Float>(transformed.x, transformed.y, transformed.z)
    }

    private func transformDirection(_ direction: SIMD3<Float>, with matrix: simd_float4x4) -> SIMD3<Float> {
        let transformed = matrix * SIMD4<Float>(direction.x, direction.y, direction.z, 0)
        return SIMD3<Float>(transformed.x, transformed.y, transformed.z)
    }

    /// Selects the preferred hit candidate by confidence rank first, then distance.
    private func selectPreferredCandidate(from candidates: [ProbeHitCandidate]) -> ProbeHitCandidate? {
        candidates.max { lhs, rhs in
            if lhs.confidenceRank != rhs.confidenceRank {
                return lhs.confidenceRank < rhs.confidenceRank
            }
            return lhs.distanceMeters > rhs.distanceMeters
        }
    }

    private func planeAlignmentDescription(_ alignment: ARRaycastQuery.TargetAlignment) -> String {
        switch alignment {
        case .horizontal:
            return "horizontal"
        case .vertical:
            return "vertical"
        case .any:
            return "any"
        @unknown default:
            return "unknown"
        }
    }

    private func trackingStateDescription(_ state: ARCamera.TrackingState) -> String {
        switch state {
        case .normal:
            return "normal"
        case .notAvailable:
            return "notAvailable"
        case .limited(let reason):
            switch reason {
            case .initializing: return "limited.initializing"
            case .relocalizing: return "limited.relocalizing"
            case .excessiveMotion: return "limited.excessiveMotion"
            case .insufficientFeatures: return "limited.insufficientFeatures"
            @unknown default: return "limited.unknown"
            }
        }
    }

    private func worldTransform(from matrix: simd_float4x4) -> WorldTransformV1 {
        WorldTransformV1(
            elements: [
                Double(matrix.columns.0.x), Double(matrix.columns.0.y), Double(matrix.columns.0.z), Double(matrix.columns.0.w),
                Double(matrix.columns.1.x), Double(matrix.columns.1.y), Double(matrix.columns.1.z), Double(matrix.columns.1.w),
                Double(matrix.columns.2.x), Double(matrix.columns.2.y), Double(matrix.columns.2.z), Double(matrix.columns.2.w),
                Double(matrix.columns.3.x), Double(matrix.columns.3.y), Double(matrix.columns.3.z), Double(matrix.columns.3.w)
            ]
        )
    }

    private func bridgeToV2(_ room: CapturedRoom) -> RoomCaptureV2 {
        let vertices = polygonVertices(from: room)
        let rawHeight = rawCeilingHeight(from: room)
        var v2 = RoomCaptureV2(
            id: prospectiveRoomId ?? UUID(),
            displayName: "Room"
        )
        v2.polygonVertices = vertices
        v2.floorLevelY = Double(room.floors.first?.transform.columns.3.y ?? 0)
        v2.rawCapturedCeilingHeightM = rawHeight
        v2.ceilingHeightM = displayedCeilingHeight(from: rawHeight)
        return v2
    }

    private func rawCeilingHeight(from room: CapturedRoom) -> Double? {
        let wallHeights = room.walls
            .map { Double($0.dimensions.y) }
            .filter { $0 > 0.1 }
            .sorted()
        if !wallHeights.isEmpty {
            return wallHeights[wallHeights.count / 2]
        }
        if let floor = room.floors.first {
            let floorHeight = Double(floor.dimensions.y)
            return floorHeight > 0.1 ? floorHeight : nil
        }
        return nil
    }

    private func displayedCeilingHeight(from rawHeight: Double?) -> Double {
        guard let rawHeight else { return 2.4 }
        let domesticMin = 1.9
        let domesticMax = 3.5
        if rawHeight >= domesticMin && rawHeight <= domesticMax {
            return rawHeight
        }
        let halved = rawHeight / 2.0
        if halved >= domesticMin && halved <= domesticMax {
            return halved
        }
        return rawHeight
    }

    /// Extracts an ordered floor-polygon from captured wall segments first and
    /// falls back to floor-surface geometry if wall chaining fails.
    private func polygonVertices(from room: CapturedRoom) -> [Vertex2D] {
        let fromWalls = polygonVerticesFromWalls(room.walls)
        if fromWalls.count >= 3, RoomPolygon(vertices: fromWalls).area >= minimumAreaM2 {
            return fromWalls
        }
        guard let floor = room.floors.first else { return [] }
        return rectangularVertices(from: floor)
    }

    private func rectangularVertices(from floor: CapturedRoom.Surface) -> [Vertex2D] {
        let transform = floor.transform
        let halfW = floor.dimensions.x / 2
        let halfD = floor.dimensions.z / 2
        let corners: [SIMD4<Float>] = [
            SIMD4(-halfW, 0,  halfD, 1),
            SIMD4( halfW, 0,  halfD, 1),
            SIMD4( halfW, 0, -halfD, 1),
            SIMD4(-halfW, 0, -halfD, 1),
        ]
        return corners.map { local in
            let world = transform * local
            return Vertex2D(x: Double(world.x), z: Double(world.z))
        }
    }

    private func polygonVerticesFromWalls(_ walls: [CapturedRoom.Surface]) -> [Vertex2D] {
        typealias Pt = SIMD2<Float>
        var segments: [(a: Pt, b: Pt)] = []

        for wall in walls {
            let cx = wall.transform.columns.3.x
            let cz = wall.transform.columns.3.z
            let axisX = wall.transform.columns.0.x
            let axisZ = wall.transform.columns.0.z
            let norm = sqrt(axisX * axisX + axisZ * axisZ)
            guard norm > 1e-4 else { continue }
            let ux = axisX / norm
            let uz = axisZ / norm
            let halfLen = wall.dimensions.x / 2.0
            guard halfLen > minimumWallLengthMeters else { continue }
            segments.append((
                a: Pt(cx + halfLen * ux, cz + halfLen * uz),
                b: Pt(cx - halfLen * ux, cz - halfLen * uz)
            ))
        }

        guard segments.count >= 3 else { return [] }

        let xs = segments.flatMap { [$0.a.x, $0.b.x] }
        let zs = segments.flatMap { [$0.a.y, $0.b.y] }
        guard let minX = xs.min(), let maxX = xs.max(), let minZ = zs.min(), let maxZ = zs.max() else {
            return []
        }
        let tolerance = max(
            polygonToleranceMin,
            min(min(maxX - minX, maxZ - minZ) * polygonToleranceFraction, polygonToleranceMax)
        )

        var orderedPts: [Pt] = [segments[0].a, segments[0].b]
        var remaining = Array(segments.dropFirst())

        while !remaining.isEmpty {
            let last = orderedPts[orderedPts.count - 1]
            var bestIdx = -1
            var bestDist = Float.greatestFiniteMagnitude
            var useEndA = true

            for (i, seg) in remaining.enumerated() {
                let dA = simd_distance(last, seg.a)
                let dB = simd_distance(last, seg.b)
                if dA < bestDist { bestDist = dA; bestIdx = i; useEndA = true }
                if dB < bestDist { bestDist = dB; bestIdx = i; useEndA = false }
            }

            guard bestIdx >= 0, bestDist < tolerance else { break }
            let seg = remaining.remove(at: bestIdx)
            orderedPts.append(useEndA ? seg.b : seg.a)
        }

        guard orderedPts.count >= 3 else { return [] }
        if let first = orderedPts.first, let last = orderedPts.last, simd_distance(first, last) < tolerance {
            orderedPts.removeLast()
        }
        guard orderedPts.count >= 3 else { return [] }

        let vertices = orderedPts.map { Vertex2D(x: Double($0.x), z: Double($0.y)) }
        let polygon = RoomPolygon(vertices: vertices)
        guard polygon.area > minimumAreaM2 else { return [] }
        return polygon.signedArea >= 0 ? vertices : vertices.reversed()
    }
}
