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
                worldTransform: nil
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
                worldTransform: nil
            )
        }
        let results = raycastResults(from: center, frame: frame, captureView: captureView)
        guard let result = results.first else {
            return LiveCapturePointProbeResultV1(
                screenPoint: normalizedPoint,
                worldPosition: nil,
                anchorConfidence: .screenOnly,
                hitNormal: nil,
                anchorId: nil,
                worldTransform: nil
            )
        }

        let anchor = ARAnchor(transform: result.worldTransform)
        captureView.captureSession.arSession.add(anchor: anchor)
        let position = result.worldTransform.columns.3
        let forward = result.worldTransform.columns.2
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
            worldTransform: worldTransform(from: result.worldTransform)
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

    private func raycastResults(
        from point: CGPoint,
        frame: ARFrame,
        captureView: RoomCaptureView
    ) -> [ARRaycastResult] {
        // Prefer confirmed plane geometry/infinite planes first so evidence
        // locks to stable surfaces; fall back to estimated planes only when
        // no confirmed plane hit is available.
        if let query = frame.raycastQuery(from: point, allowing: .existingPlaneGeometry, alignment: .any) {
            let results = captureView.captureSession.arSession.raycast(query)
            if !results.isEmpty { return results }
        }
        if let query = frame.raycastQuery(from: point, allowing: .existingPlaneInfinite, alignment: .any) {
            let results = captureView.captureSession.arSession.raycast(query)
            if !results.isEmpty { return results }
        }
        if let query = frame.raycastQuery(from: point, allowing: .estimatedPlane, alignment: .any) {
            return captureView.captureSession.arSession.raycast(query)
        }
        return []
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
