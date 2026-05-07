import Foundation
import RoomPlan
import Combine
import simd
import AtlasScanCore

// MARK: - RoomPlanCaptureService
//
// Wraps Apple's RoomPlan RoomCaptureSession to manage a live room scan.
//
// Architecture:
//   • All RoomPlan types are confined to this file.
//   • Converts CapturedRoomData into RoomPlanScanResult for the pure mapper.
//   • Publishes sessionState and capturedResult for the SwiftUI layer.
//   • Does NOT persist or export — the caller maps the result into the
//     existing CaptureSessionDraft via RoomPlanMapper.
//   • If a visitId is configured via configure(visitId:), the scan's USDZ is
//     exported (best-effort) to <AppSupport>/captures/<visitId>/<scanId>.usdz
//     and the relative path is stored in RoomPlanScanResult.rawScanAssetRef.
//
// LiDAR hardware support:
//   • isSupported returns false on devices without LiDAR.
//   • The UI falls back to manual entry when unsupported.

@MainActor
final class RoomPlanCaptureService: NSObject, ObservableObject {

    // MARK: - Session state

    enum SessionState: Equatable {
        /// Device does not have LiDAR / RoomPlan support.
        case unavailable
        /// Ready to start scanning.
        case ready
        /// Live AR scanning in progress.
        case scanning
        /// Scan stopped; RoomPlan is processing the geometry.
        case processing
        /// Processing complete; capturedResult is available.
        case completed
        /// Session was cancelled by the user.
        case cancelled
        /// Session ended with an error.
        case failed(String)
    }

    @Published private(set) var sessionState: SessionState = .ready
    @Published private(set) var capturedResult: RoomPlanScanResult?
    @Published private(set) var liveCapturePolygon: [Vertex2D] = []

    // MARK: - Hardware capability

    static var isSupported: Bool {
        RoomCaptureSession.isSupported
    }

    // MARK: - RoomPlan view (exposed for UIViewRepresentable bridging)

    let roomCaptureView: RoomCaptureView
    private var captureConfig = RoomCaptureSession.Configuration()

    // MARK: - USDZ persistence state

    /// The visit UUID used to build the captures directory path.
    private var visitId: UUID?

    /// A fresh UUID is assigned each time startScan() is called so that
    /// sequential scans in the same session each produce a unique filename
    /// on the file system.
    private var currentScanId: UUID = UUID()

    // MARK: - Init

    override init() {
        roomCaptureView = RoomCaptureView(frame: .zero)
        super.init()
        roomCaptureView.captureSession.delegate = self
    }

    // MARK: - Configuration

    /// Configures the service with the visit UUID so that the captured USDZ can be
    /// saved to the correct `captures/<visitId>/` directory.
    ///
    /// Call this before `startScan()`. It is safe to call multiple times.
    func configure(visitId: UUID) {
        self.visitId = visitId
    }

    // MARK: - Lifecycle

    /// Starts a new room scan. Resets any previous captured result.
    func startScan() {
        guard Self.isSupported else {
            sessionState = .unavailable
            return
        }
        capturedResult = nil
        liveCapturePolygon = []
        currentScanId  = UUID()   // fresh ID for each new scan so files never collide
        sessionState   = .scanning
        roomCaptureView.captureSession.run(configuration: captureConfig)
    }

    /// Stops the active scan and begins RoomPlan geometry processing.
    func stopScan() {
        guard sessionState == .scanning else { return }
        sessionState = .processing
        roomCaptureView.captureSession.stop(pauseARSession: false)
    }

    /// Cancels the active scan without producing a result.
    func cancelScan() {
        roomCaptureView.captureSession.stop(pauseARSession: true)
        capturedResult = nil
        liveCapturePolygon = []
        sessionState = .cancelled
    }

    /// Pauses the AR session (call when the view disappears).
    func pauseSession() {
        roomCaptureView.captureSession.stop(pauseARSession: true)
    }

    // MARK: - USDZ save URL helpers

    /// Constructs the destination URL for the USDZ export.
    ///
    /// Creates the intermediate directory if it does not yet exist.
    /// Returns `nil` when no `visitId` has been configured.
    private func makeUSDZSaveURL() -> URL? {
        guard let visitId else { return nil }
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport
            .appendingPathComponent("captures", isDirectory: true)
            .appendingPathComponent(visitId.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(currentScanId.uuidString).usdz")
    }

    /// The relative asset reference stored in `RoomPlanScanResult.rawScanAssetRef`.
    private func rawScanAssetRef(for visitId: UUID) -> String {
        "captures/\(visitId.uuidString)/\(currentScanId.uuidString).usdz"
    }
}

// MARK: - RoomCaptureSessionDelegate

extension RoomPlanCaptureService: RoomCaptureSessionDelegate {

    nonisolated func captureSession(
        _ session: RoomCaptureSession,
        didUpdate room: CapturedRoom
    ) {
        let polygon = Self.makeLivePolygon(from: room)
        Task { @MainActor in
            self.liveCapturePolygon = polygon
        }
    }

    nonisolated func captureSession(
        _ session: RoomCaptureSession,
        didEndWith data: CapturedRoomData,
        error: (any Error)?
    ) {
        if let error {
            let message = error.localizedDescription
            Task { @MainActor in self.sessionState = .failed(message) }
            return
        }
        // Build the plain-struct result asynchronously via RoomBuilder.
        // Run the task on the main actor so we can read/write isolated state
        // directly without extra MainActor.run hops.
        Task { @MainActor in
            let saveURL  = self.makeUSDZSaveURL()
            let assetRef = self.visitId.map { self.rawScanAssetRef(for: $0) }
            do {
                let result = try await RoomPlanCaptureService.buildResult(
                    from: data,
                    saveUSDZAt: saveURL,
                    rawScanAssetRef: assetRef
                )
                // Ignore completion if the user cancelled while processing.
                guard self.sessionState == .processing else { return }
                self.capturedResult = result
                self.liveCapturePolygon = Self.vertices(from: result)
                self.sessionState = .completed
            } catch {
                self.sessionState = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Private: build RoomPlanScanResult

    /// Builds the `RoomPlanScanResult` from captured data.
    ///
    /// - Parameters:
    ///   - data:             The raw RoomPlan capture data.
    ///   - saveUSDZAt:       Optional destination URL.  When non-nil the method
    ///                       exports the room geometry as a USDZ file (best-effort;
    ///                       a failure does not propagate as an error).
    ///   - rawScanAssetRef:  The pre-computed relative path to store in the result
    ///                       when the USDZ export succeeds.
    private nonisolated static func buildResult(
        from data: CapturedRoomData,
        saveUSDZAt saveURL: URL?,
        rawScanAssetRef: String?
    ) async throws -> RoomPlanScanResult {
        let roomBuilder = RoomBuilder(options: [])
        let room = try await roomBuilder.capturedRoom(from: data)

        // Best-effort USDZ export — never fails the whole build.
        var resolvedAssetRef: String? = nil
        if let saveURL, let rawScanAssetRef {
            do {
                try room.export(to: saveURL)
                resolvedAssetRef = rawScanAssetRef
            } catch {
                // Non-fatal: continue without persisting the USDZ asset.
            }
        }

        // Compute axis-aligned bounding box from wall surface transforms + dimensions.
        var minX: Float = .greatestFiniteMagnitude
        var maxX: Float = -.greatestFiniteMagnitude
        var minZ: Float = .greatestFiniteMagnitude
        var maxZ: Float = -.greatestFiniteMagnitude
        var maxHeight: Float = 0

        for wall in room.walls {
            let cx  = wall.transform.columns.3.x
            let cz  = wall.transform.columns.3.z
            let halfW = wall.dimensions.x / 2
            let halfD = wall.dimensions.z / 2
            minX = min(minX, cx - halfW)
            maxX = max(maxX, cx + halfW)
            minZ = min(minZ, cz - halfD)
            maxZ = max(maxZ, cz + halfD)
            maxHeight = max(maxHeight, wall.dimensions.y)
        }

        let width:  Double? = maxX > minX ? Double(maxX - minX) : nil
        let depth:  Double? = maxZ > minZ ? Double(maxZ - minZ) : nil
        let height: Double? = maxHeight > 0 ? Double(maxHeight) : nil

        // Extract the actual room polygon from wall geometry.
        // This replaces the V1 bounding-box rectangle with a true multi-vertex
        // polygon so L-shapes, T-shapes, and alcoves are accurately represented.
        let (outlinePoints, wallSegmentLengthsM) = RoomPlanCaptureService.extractPolygon(
            from: room.walls,
            minX: minX, maxX: maxX,
            minZ: minZ, maxZ: maxZ
        )

        // Convert RoomPlan detected objects to RoomPlanDetectedObject.
        let detectedObjects: [RoomPlanDetectedObject] = room.objects.compactMap { obj in
            guard let w = width, let d = depth, w > 0, d > 0 else { return nil }
            let cx = Double(obj.transform.columns.3.x)
            let cz = Double(obj.transform.columns.3.z)
            let nx = ((cx - Double(minX)) / w).clamped(to: 0...1)
            let nz = ((cz - Double(minZ)) / d).clamped(to: 0...1)
            let category = RoomPlanObjectCategory(roomPlanCategory: obj.category)
            return RoomPlanDetectedObject(
                category: category,
                label: category.displayLabel,
                normalisedPositionX: nx,
                normalisedPositionY: nz
            )
        }

        return RoomPlanScanResult(
            widthM: width,
            depthM: depth,
            heightM: height,
            outlinePoints: outlinePoints,
            detectedObjects: detectedObjects,
            rawJSON: nil,
            rawScanAssetRef: resolvedAssetRef,
            wallSegmentLengthsM: wallSegmentLengthsM.isEmpty ? nil : wallSegmentLengthsM
        )
    }

    // MARK: - Anti-Square Polygon Extraction
    //
    // Extracts the true room outline polygon from wall surfaces captured by RoomPlan.
    //
    // RoomPlan wall coordinate conventions (Y-up, right-handed space):
    //   • transform.columns.3 (x, z) = wall centre position on the floor plane
    //   • transform.columns.0        = local X axis — the direction *along* the
    //                                  wall face (i.e. parallel to the wall surface,
    //                                  not perpendicular to it). Travelling ± halfLen
    //                                  along this axis reaches the two wall endpoints.
    //   • dimensions.x               = wall width in metres (distance between endpoints)
    //
    // From each wall we compute the two floor-plane endpoints, then chain the
    // segments end-to-end (greedy nearest-endpoint matching) to build an ordered
    // polygon. The result is normalised to [margin, 1−margin] preserving aspect ratio.
    //
    // Returns: (outlinePoints, wallSegmentLengthsM)
    //   • outlinePoints          — normalised polygon vertices (empty on failure)
    //   • wallSegmentLengthsM    — raw metric segment lengths in polygon order

    /// Minimum wall or axis span (metres) required to treat geometry as valid.
    /// Walls shorter than this are treated as degenerate and discarded.
    private nonisolated static let minimumWallLengthMeters: Float = 0.01

    /// Lower bound for the adaptive endpoint-chaining tolerance (metres).
    private nonisolated static let polygonToleranceMin:        Float = 0.01
    /// Fraction of the room's shortest span used as the chaining tolerance.
    private nonisolated static let polygonToleranceFraction:   Float = 0.10
    /// Upper bound for the adaptive endpoint-chaining tolerance (metres).
    /// This caps the tolerance so it cannot grow larger than a typical wall gap.
    private nonisolated static let polygonToleranceMax:        Float = 0.25

    private nonisolated static func extractPolygon(
        from walls: [CapturedRoom.Surface],
        minX: Float, maxX: Float,
        minZ: Float, maxZ: Float
    ) -> ([NormalisedPoint], [Double]) {

        // ── Step 1: Compute floor-plane endpoints for each wall ──────────────

        typealias Pt = SIMD2<Float>
        var segments: [(a: Pt, b: Pt)] = []

        for wall in walls {
            let cx    = wall.transform.columns.3.x
            let cz    = wall.transform.columns.3.z
            let axisX = wall.transform.columns.0.x
            let axisZ = wall.transform.columns.0.z
            let norm  = sqrt(axisX * axisX + axisZ * axisZ)
            guard norm > 1e-4 else { continue }
            let ux = axisX / norm
            let uz = axisZ / norm
            let halfLen = wall.dimensions.x / 2.0
            segments.append((
                a: Pt(cx + halfLen * ux, cz + halfLen * uz),
                b: Pt(cx - halfLen * ux, cz - halfLen * uz)
            ))
        }

        guard segments.count >= 3 else { return ([], []) }

        // ── Step 2: Chain segments into a closed polygon ─────────────────────
        //
        // Strategy: greedy nearest-endpoint matching.
        // Start with segment[0].a, connect to whichever unused endpoint (a or b)
        // of any remaining segment is closest.  Stop when we've consumed all
        // segments or the next match is farther than `tolerance`.
        //
        // Tolerance is adaptive: 10 % of the room's minimum span, capped at
        // 25 cm, which handles the small gaps that arise from wall thickness.

        let roomSpanX = maxX - minX
        let roomSpanZ = maxZ - minZ
        let tolerance = max(
            RoomPlanCaptureService.polygonToleranceMin,
            min(Float(min(roomSpanX, roomSpanZ)) * RoomPlanCaptureService.polygonToleranceFraction,
                RoomPlanCaptureService.polygonToleranceMax)
        )

        var orderedPts: [Pt] = [segments[0].a, segments[0].b]
        var remaining = Array(segments.dropFirst())

        while !remaining.isEmpty {
            let last = orderedPts[orderedPts.count - 1]
            var bestIdx  = -1
            var bestDist = Float.greatestFiniteMagnitude
            var useEndA  = true

            for (i, seg) in remaining.enumerated() {
                let dA = simd_distance(last, seg.a)
                let dB = simd_distance(last, seg.b)
                if dA < bestDist { bestDist = dA; bestIdx = i; useEndA = true  }
                if dB < bestDist { bestDist = dB; bestIdx = i; useEndA = false }
            }

            guard bestIdx >= 0, bestDist < tolerance else { break }

            let seg = remaining.remove(at: bestIdx)
            // Append the far endpoint of the matched segment.
            orderedPts.append(useEndA ? seg.b : seg.a)
        }

        guard orderedPts.count >= 3 else { return ([], []) }

        // Remove the closing point if it is a near-duplicate of the first vertex
        // (RoomPlan sometimes closes the polygon with an extra overlapping point).
        if let first = orderedPts.first, let last = orderedPts.last,
           simd_distance(first, last) < tolerance {
            orderedPts.removeLast()
        }

        guard orderedPts.count >= 3 else { return ([], []) }

        // ── Step 3: Compute per-segment metric lengths ───────────────────────

        let segmentLengths: [Double] = orderedPts.indices.map { i in
            let next = (i + 1) % orderedPts.count
            return Double(simd_distance(orderedPts[i], orderedPts[next]))
        }

        // ── Step 4: Normalise to [margin, 1−margin] preserving aspect ratio ──

        let pxs = orderedPts.map { $0.x }
        let pzs = orderedPts.map { $0.y }
        guard let pMinX = pxs.min(), let pMaxX = pxs.max(),
              let pMinZ = pzs.min(), let pMaxZ = pzs.max() else { return ([], []) }

        let rangeX = pMaxX - pMinX
        let rangeZ = pMaxZ - pMinZ
        guard rangeX > RoomPlanCaptureService.minimumWallLengthMeters ||
              rangeZ > RoomPlanCaptureService.minimumWallLengthMeters else { return ([], []) }

        let margin: Float = 0.05
        let usableSize: Float = 1.0 - 2 * margin
        let maxRange = max(rangeX, rangeZ, RoomPlanCaptureService.minimumWallLengthMeters)
        let scale = usableSize / maxRange

        // Centre the polygon within the normalised canvas.
        let offsetX = margin + (usableSize - rangeX * scale) / 2
        let offsetZ = margin + (usableSize - rangeZ * scale) / 2

        let normalised: [NormalisedPoint] = orderedPts.map { pt in
            NormalisedPoint(
                x: Double((pt.x - pMinX) * scale + offsetX),
                y: Double((pt.y - pMinZ) * scale + offsetZ)
            )
        }

        return (normalised, segmentLengths)
    }
}

private extension RoomPlanCaptureService {
    nonisolated static func makeLivePolygon(from room: CapturedRoom) -> [Vertex2D] {
        guard let floor = room.floors.first else { return [] }
        let transform = floor.transform
        let corners: [SIMD4<Float>] = [
            SIMD4(-0.5, 0,  0.5, 1),
            SIMD4( 0.5, 0,  0.5, 1),
            SIMD4( 0.5, 0, -0.5, 1),
            SIMD4(-0.5, 0, -0.5, 1)
        ]
        return corners.map { local in
            let world = transform * local
            return Vertex2D(x: Double(world.x), z: Double(world.z))
        }
    }

    nonisolated static func vertices(from result: RoomPlanScanResult) -> [Vertex2D] {
        let width = max(result.widthM ?? 1, 0.1)
        let depth = max(result.depthM ?? 1, 0.1)
        guard !result.outlinePoints.isEmpty else {
            return [
                Vertex2D(x: -width / 2, z:  depth / 2),
                Vertex2D(x:  width / 2, z:  depth / 2),
                Vertex2D(x:  width / 2, z: -depth / 2),
                Vertex2D(x: -width / 2, z: -depth / 2)
            ]
        }
        return result.outlinePoints.map { point in
            Vertex2D(
                x: (point.x - 0.5) * width,
                z: (0.5 - point.y) * depth
            )
        }
    }
}

// MARK: - RoomPlanObjectCategory + RoomPlan initialiser

extension RoomPlanObjectCategory {

    /// Initialise from an Apple `CapturedRoom.Object.Category`.
    init(roomPlanCategory: CapturedRoom.Object.Category) {
        switch roomPlanCategory {
        case .bathtub:      self = .bathtub
        case .bed:          self = .bed
        case .chair:        self = .chair
        case .dishwasher:   self = .dishwasher
        case .fireplace:    self = .fireplace
        case .oven:         self = .oven
        case .refrigerator: self = .refrigerator
        case .sink:         self = .sink
        case .sofa:         self = .sofa
        case .stairs:       self = .stairs
        case .stove:        self = .stove
        case .television:   self = .television
        case .toilet:       self = .toilet
        case .washerDryer:  self = .washerDryer
        case .storage:      self = .storage
        case .table:        self = .table
        @unknown default:   self = .unknown
        }
    }
}
