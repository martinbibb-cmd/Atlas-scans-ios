import Foundation
import ARKit
import AVFoundation
import simd
import UIKit

// MARK: - ExternalFlueCaptureSession
//
// ARKit-backed session for the outdoor flue-clearance capture flow.
//
// Workflow:
//   1. Call start() — begins AR world tracking.
//   2. User taps to place the flue terminal anchor.
//   3. User taps to place nearby-feature anchors (window, door, air brick, etc.),
//      selecting the feature kind for each placement.
//   4. Distances from the terminal to each feature are computed in world space.
//   5. Call finishCapture() — evaluates compliance and returns a completed
//      ExternalClearanceScene ready to store in PropertyScanSession.
//   6. Call pause() when the view disappears.
//
// Architecture rules:
//   • Compliance is computed from structured measurements, NOT from raw mesh geometry.
//   • The raw LiDAR mesh is used only for surface raycasting to improve anchor accuracy.
//   • All ARKit types are confined to this file.
//   • No point-cloud blob is written by default; rawMeshURL is always nil unless
//     an optional debug export is explicitly triggered.

// MARK: - ExternalFluePhase

/// Workflow phase for the external flue-clearance capture session.
enum ExternalFluePhase: Equatable {
    /// Camera permission was denied.
    case permissionDenied
    /// AR world tracking is initialising (poor environment, insufficient features).
    case initialising
    /// Engineer should tap to place the flue terminal anchor.
    case placingTerminal
    /// Terminal anchor is placed; engineer taps to add nearby-feature markers.
    case placingFeatures
    /// Capture complete; review measurements before saving.
    case reviewing
    /// AR is unavailable on this device.
    case unavailable
}

// MARK: - ExternalFlueCaptureSession

@MainActor
final class ExternalFlueCaptureSession: NSObject, ObservableObject {

    // MARK: - Published state

    @Published private(set) var phase: ExternalFluePhase = .initialising
    @Published private(set) var terminalCapture: FlueTerminalCapture?
    @Published private(set) var nearbyFeatures: [NearbyFeatureCapture] = []

    /// Real-time obstruction violation messages derived from `nearbyFeatures`.
    ///
    /// Updated immediately whenever a feature is placed or removed, giving the
    /// engineer instant feedback (per BS 5440 / Gas Safe minimum clearances) rather
    /// than waiting until the Review phase.  Empty when all features are clear.
    @Published private(set) var liveViolations: [String] = []

    /// The kind that will be assigned to the next tapped feature anchor.
    @Published var pendingFeatureKind: ClearanceFeatureKind = .window

    // MARK: - ARKit plumbing

    private let _arView = ARSCNView(frame: .zero)
    var arView: UIView { _arView }

    // MARK: - Device capability

    static var isSupported: Bool {
        ARWorldTrackingConfiguration.isSupported
    }

    // MARK: - Lifecycle

    func start() {
        guard Self.isSupported else {
            phase = .unavailable
            return
        }
        checkCameraPermission { [weak self] granted in
            guard let self else { return }
            Task { @MainActor in
                if granted {
                    self.runSession()
                } else {
                    self.phase = .permissionDenied
                }
            }
        }
    }

    func pause() {
        _arView.session.pause()
    }

    // MARK: - Tap handling

    /// Handles a tap at `screenPoint` in the AR view.
    ///
    /// - In `.placingTerminal` phase: places the flue terminal anchor.
    /// - In `.placingFeatures` phase: adds a nearby-feature anchor of
    ///   `pendingFeatureKind` and computes the distance to the terminal.
    func handleTap(at screenPoint: CGPoint) {
        switch phase {
        case .placingTerminal:
            placeTerminal(at: screenPoint)
        case .placingFeatures:
            placeFeature(at: screenPoint)
        default:
            break
        }
    }

    // MARK: - Feature management

    /// Removes a nearby feature by ID.
    func removeFeature(id: UUID) {
        nearbyFeatures.removeAll { $0.id == id }
        recomputeLiveViolations()
    }

    /// Updates the notes on an existing nearby feature.
    func updateFeatureNotes(id: UUID, notes: String) {
        guard let index = nearbyFeatures.firstIndex(where: { $0.id == id }) else { return }
        nearbyFeatures[index].notes = notes
    }

    // MARK: - Phase transitions

    /// Moves from `.placingTerminal` to `.placingFeatures` once a terminal has been placed.
    func beginPlacingFeatures() {
        guard terminalCapture != nil else { return }
        phase = .placingFeatures
    }

    /// Advances to the `.reviewing` phase so the engineer can review before saving.
    func finishPlacingFeatures() {
        guard phase == .placingFeatures else { return }
        phase = .reviewing
    }

    // MARK: - Output

    /// Builds a completed `ExternalClearanceScene` from the current captured state.
    ///
    /// Evaluates compliance from the structured measurements and returns a value
    /// ready to store in `PropertyScanSession.externalClearanceScenes`.
    ///
    /// - Parameters:
    ///   - propertySessionID: UUID of the owning PropertyScanSession.
    ///   - captureSessionID:  UUID for this capture run (used for file naming).
    ///   - previewImage:      Optional UIImage snapshot of the AR view.
    func buildScene(
        propertySessionID: UUID,
        captureSessionID: UUID,
        previewImage: UIImage? = nil
    ) -> ExternalClearanceScene {
        let measurements = buildMeasurements()

        var scene = ExternalClearanceScene(
            propertySessionID: propertySessionID,
            captureSessionID: captureSessionID,
            previewImageURLString: nil,
            flueTerminal: terminalCapture,
            nearbyFeatures: nearbyFeatures,
            measurements: measurements
        )

        // Evaluate compliance from structured measurements
        scene.compliance = scene.evaluateCompliance()

        // Save preview image if provided
        if let img = previewImage,
           let data = img.jpegData(compressionQuality: 0.75) {
            let dir = evidenceDirectory(for: captureSessionID)
            let previewURL = dir.appendingPathComponent("preview.jpg")
            if (try? data.write(to: previewURL)) != nil {
                scene.previewImageURLString = previewURL.absoluteString
            }
        }

        return scene
    }

    // MARK: - Private: session setup

    private func runSession() {
        let config = ARWorldTrackingConfiguration()
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        config.environmentTexturing = .none
        _arView.automaticallyUpdatesLighting = false
        _arView.session.delegate = self
        _arView.session.run(config, options: [.removeExistingAnchors, .resetTracking])
        phase = .placingTerminal
    }

    // MARK: - Private: terminal placement

    private func placeTerminal(at screenPoint: CGPoint) {
        guard let position = resolveWorldPosition(screenPoint: screenPoint) else { return }

        let forwardDir = cameraForwardDirection()
        terminalCapture = FlueTerminalCapture(
            x: Double(position.x),
            y: Double(position.y),
            z: Double(position.z),
            normalX: forwardDir.map { Double($0.x) },
            normalY: forwardDir.map { Double($0.y) },
            normalZ: forwardDir.map { Double($0.z) },
            heightAboveGroundM: Double(max(0, position.y))
        )
        phase = .placingFeatures
    }

    // MARK: - Private: feature placement

    private func placeFeature(at screenPoint: CGPoint) {
        guard let position = resolveWorldPosition(screenPoint: screenPoint) else { return }
        let terminalPos = terminalCapture.map {
            simd_float3(Float($0.x), Float($0.y), Float($0.z))
        }
        let distanceM: Double? = terminalPos.map { tp in
            let dx = Float(position.x) - tp.x
            let dy = Float(position.y) - tp.y
            let dz = Float(position.z) - tp.z
            return Double((dx * dx + dy * dy + dz * dz).squareRoot())
        }

        let feature = NearbyFeatureCapture(
            kind: pendingFeatureKind,
            x: Double(position.x),
            y: Double(position.y),
            z: Double(position.z),
            distanceToTerminalM: distanceM
        )
        nearbyFeatures.append(feature)
        recomputeLiveViolations()
    }

    // MARK: - Private: live violation check

    /// Recomputes `liveViolations` from the current `nearbyFeatures`.
    ///
    /// Minimum clearances applied (BS 5440 Part 1 / Gas Safe guidance):
    ///   • Terminal to opening (window, door, air brick, opening, adjacent flue): 300 mm
    ///   • Terminal to boundary: 600 mm
    ///   • Terminal to eaves / gutter: 300 mm
    ///   • All other feature kinds: 300 mm (conservative fallback)
    private func recomputeLiveViolations() {
        var violations: [String] = []
        for feature in nearbyFeatures {
            guard let dist = feature.distanceToTerminalM else { continue }
            let minimum: Double
            switch feature.kind {
            case .boundary:
                minimum = 0.60
            default:
                minimum = 0.30
            }
            if dist < minimum {
                let distMM = Int((dist * 1000).rounded())
                let minMM = Int(minimum * 1000)
                violations.append(
                    "\(feature.kind.displayName) is \(distMM) mm away — minimum \(minMM) mm required (BS 5440 Part 1)."
                )
            }
        }
        liveViolations = violations
    }

    // MARK: - Private: measurement builder

    private func buildMeasurements() -> [ClearanceMeasurementCapture] {
        var results: [ClearanceMeasurementCapture] = []

        for feature in nearbyFeatures {
            guard let dist = feature.distanceToTerminalM else { continue }
            let kind: ClearanceMeasurementCapture.MeasurementKind
            switch feature.kind {
            case .window, .door, .airBrick, .opening, .adjacentFlue:
                kind = .terminalToOpening
            case .boundary:
                kind = .terminalToBoundary
            case .eaves, .gutter:
                kind = .terminalToEaves
            case .soilStack, .balcony:
                kind = .terminalToBoundary
            }
            results.append(ClearanceMeasurementCapture(kind: kind, valueM: dist))
        }

        return results
    }

    // MARK: - Private: world-position resolution

    /// Resolves a screen tap to a world-space position using ARKit raycasting.
    /// Tries existing-plane geometry first; falls back to estimated-plane if no hit.
    private func resolveWorldPosition(screenPoint: CGPoint) -> simd_float3? {
        // Try LiDAR mesh / existing-plane first for better accuracy, then fall back
        // to estimated plane. Both targets are checked in priority order to minimise
        // duplicate query creation.
        for target: ARRaycastQuery.Target in [.existingPlaneGeometry, .estimatedPlane] {
            if let q = _arView.raycastQuery(from: screenPoint, allowing: target, alignment: .any),
               let hit = _arView.session.raycast(q).first {
                let col = hit.worldTransform.columns.3
                return simd_float3(col.x, col.y, col.z)
            }
        }
        return nil
    }

    /// Returns the camera's forward direction in world space (XZ plane only).
    private func cameraForwardDirection() -> simd_float3? {
        guard let frame = _arView.session.currentFrame else { return nil }
        let fwd = simd_float3(
            -frame.camera.transform.columns.2.x,
             0,
            -frame.camera.transform.columns.2.z
        )
        guard simd_length(fwd) > 0.001 else { return nil }
        return simd_normalize(fwd)
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

    // MARK: - Private: file management

    private func evidenceDirectory(for captureSessionID: UUID) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir  = docs
            .appendingPathComponent("FlueEvidenceScenes", isDirectory: true)
            .appendingPathComponent(captureSessionID.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

// MARK: - ARSessionDelegate

extension ExternalFlueCaptureSession: ARSessionDelegate {

    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // World positions resolved on tap only — no per-frame work needed.
    }

    nonisolated func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        let state = camera.trackingState
        Task { @MainActor [weak self] in
            guard let self else { return }
            if case .normal = state {
                if self.phase == .initialising {
                    self.phase = .placingTerminal
                }
            } else {
                if self.phase == .placingTerminal || self.phase == .placingFeatures {
                    self.phase = .initialising
                }
            }
        }
    }
}
