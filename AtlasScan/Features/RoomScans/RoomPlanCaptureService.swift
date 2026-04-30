import Foundation
import RoomPlan
import Combine

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

    // MARK: - Hardware capability

    static var isSupported: Bool {
        RoomCaptureSession.isSupported
    }

    // MARK: - RoomPlan view (exposed for UIViewRepresentable bridging)

    let roomCaptureView: RoomCaptureView
    private var captureConfig = RoomCaptureSession.Configuration()

    // MARK: - Init

    override init() {
        roomCaptureView = RoomCaptureView(frame: .zero)
        super.init()
        roomCaptureView.captureSession.delegate = self
    }

    // MARK: - Lifecycle

    /// Starts a new room scan. Resets any previous captured result.
    func startScan() {
        guard Self.isSupported else {
            sessionState = .unavailable
            return
        }
        capturedResult = nil
        sessionState = .scanning
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
        sessionState = .cancelled
    }

    /// Pauses the AR session (call when the view disappears).
    func pauseSession() {
        roomCaptureView.captureSession.stop(pauseARSession: true)
    }
}

// MARK: - RoomCaptureSessionDelegate

extension RoomPlanCaptureService: RoomCaptureSessionDelegate {

    nonisolated func captureSession(
        _ session: RoomCaptureSession,
        didUpdate room: CapturedRoom
    ) {
        // Live update — RoomCaptureView renders the in-progress geometry automatically.
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
        // Build the plain-struct result from CapturedRoomData.
        let result = RoomPlanCaptureService.buildResult(from: data)
        Task { @MainActor in
            // Ignore completion if the user cancelled while processing.
            guard self.sessionState == .processing else { return }
            self.capturedResult = result
            self.sessionState = .completed
        }
    }

    // MARK: - Private: build RoomPlanScanResult

    private static func buildResult(from data: CapturedRoomData) -> RoomPlanScanResult {
        let room = data.capturedRoom

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

        // Build a normalised rectangular outline (5% inset) when dimensions are known.
        let outlinePoints: [NormalisedPoint] = (width != nil && depth != nil) ? [
            NormalisedPoint(x: 0.05, y: 0.05),
            NormalisedPoint(x: 0.95, y: 0.05),
            NormalisedPoint(x: 0.95, y: 0.95),
            NormalisedPoint(x: 0.05, y: 0.95),
        ] : []

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
            rawJSON: nil
        )
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
        @unknown default:   self = .unknown
        }
    }
}
