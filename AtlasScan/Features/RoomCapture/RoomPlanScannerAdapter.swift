import Foundation
import Combine
import UIKit
import RoomPlan
import AVFoundation
import simd

// MARK: - RoomPlanScannerAdapter
//
// RoomPlan-backed implementation of ScannerAdapterProtocol.
// Requires a LiDAR-equipped device; check isSupported before use.
//
// Architecture rule: all RoomPlan framework types stay inside this file.
// Only local app model types (ScannedRoom, ScannedWall, ScannedOpening) cross
// the boundary. The rest of the app never imports RoomPlan.

final class RoomPlanScannerAdapter: NSObject, ScannerAdapterProtocol {

    // MARK: - Device capability

    static var isSupported: Bool {
        RoomCaptureSession.isSupported
    }

    // MARK: - ScannerAdapterProtocol

    private let stateSubject = CurrentValueSubject<ScannerState, Never>(.idle)
    private let capturedRoomSubject = PassthroughSubject<ScannedRoom, Never>()

    var statePublisher: AnyPublisher<ScannerState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    var capturedRoomPublisher: AnyPublisher<ScannedRoom, Never> {
        capturedRoomSubject.eraseToAnyPublisher()
    }

    var scannerView: UIView? { _captureView }

    // MARK: - Private

    private let _captureView: RoomCaptureView
    private var currentJobID: UUID?
    private var currentRoomName: String?
    private var isCancelled = false

    // MARK: - Init

    override init() {
        _captureView = RoomCaptureView(frame: .zero)
        super.init()
        _captureView.captureSession.delegate = self
    }

    // MARK: - ScannerAdapterProtocol methods

    func startCapture(jobID: UUID, roomName: String) {
        currentJobID = jobID
        currentRoomName = roomName
        isCancelled = false

        checkCameraPermission { [weak self] granted in
            guard let self else { return }
            DispatchQueue.main.async {
                if granted {
                    self.stateSubject.send(.initialising)
                    self._captureView.captureSession.run(configuration: .init())
                } else {
                    self.stateSubject.send(.permissionDenied)
                }
            }
        }
    }

    func stopCapture() {
        stateSubject.send(.processing)
        _captureView.captureSession.stop()
    }

    func cancelCapture() {
        isCancelled = true
        _captureView.captureSession.stop()
        stateSubject.send(.idle)
    }

    // MARK: - Camera permission

    private func checkCameraPermission(completion: @escaping (Bool) -> Void) {
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

// MARK: - RoomCaptureSessionDelegate

extension RoomPlanScannerAdapter: RoomCaptureSessionDelegate {

    func captureSession(_ session: RoomCaptureSession,
                        didStartWith configuration: RoomCaptureSession.Configuration) {
        DispatchQueue.main.async { [weak self] in
            self?.stateSubject.send(.scanning)
        }
    }

    func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
        if case .initialising = stateSubject.value {
            DispatchQueue.main.async { [weak self] in
                self?.stateSubject.send(.scanning)
            }
        }
    }

    func captureSession(_ session: RoomCaptureSession,
                        didEndWith data: CapturedRoomData, error: Error?) {
        guard !isCancelled else {
            isCancelled = false
            return
        }

        if let error {
            DispatchQueue.main.async { [weak self] in
                self?.stateSubject.send(.failed(error.localizedDescription))
            }
            return
        }

        processRoomData(data)
    }

    // MARK: - Room processing

    private func processRoomData(_ data: CapturedRoomData) {
        let jobID = currentJobID ?? UUID()
        let name = currentRoomName ?? "Room"

        Task { [weak self] in
            guard let self else { return }
            do {
                let builder = RoomBuilder(options: [.beautifyObjects])
                let captured = try await builder.capturedRoom(from: data)
                let scannedRoom = RoomPlanMapper.map(capturedRoom: captured, jobID: jobID, name: name)
                await MainActor.run {
                    self.stateSubject.send(.completed(scannedRoom))
                    self.capturedRoomSubject.send(scannedRoom)
                }
            } catch {
                await MainActor.run {
                    self.stateSubject.send(.failed(error.localizedDescription))
                }
            }
        }
    }
}

// MARK: - RoomPlanMapper
//
// Maps RoomPlan's CapturedRoom into local app models (ScannedRoom / ScannedWall /
// ScannedOpening). All RoomPlan types stay inside this file.

enum RoomPlanMapper {

    // MARK: - Entry point

    /// Maps a RoomPlan `CapturedRoom` into a local `ScannedRoom`.
    static func map(capturedRoom: CapturedRoom, jobID: UUID, name: String) -> ScannedRoom {
        let walls = mapWalls(
            capturedRoom.walls,
            doors: capturedRoom.doors,
            windows: capturedRoom.windows,
            openings: capturedRoom.openings
        )
        let openings = mapOpenings(
            doors: capturedRoom.doors,
            windows: capturedRoom.windows,
            openings: capturedRoom.openings,
            walls: capturedRoom.walls
        )
        let area = computeFloorArea(capturedRoom.floors, walls: capturedRoom.walls)
        let height = computeCeilingHeight(capturedRoom.walls)

        return ScannedRoom(
            jobID: jobID,
            name: name,
            areaSquareMetres: area,
            ceilingHeightMetres: height,
            walls: walls,
            openings: openings,
            geometryCaptured: true
        )
    }

    // MARK: - Wall mapping

    private static func mapWalls(
        _ walls: [CapturedRoom.Surface],
        doors: [CapturedRoom.Surface],
        windows: [CapturedRoom.Surface],
        openings: [CapturedRoom.Surface]
    ) -> [ScannedWall] {
        walls.enumerated().map { index, wall in
            let hasDoor   = doors.contains   { nearestWallIndex(for: $0, walls: walls) == index }
            let hasWindow = windows.contains { nearestWallIndex(for: $0, walls: walls) == index }
            return ScannedWall(
                index: index,
                lengthMetres: Double(wall.dimensions.x),
                heightMetres: Double(wall.dimensions.y),
                isExternalWall: false,
                hasWindow: hasWindow,
                hasDoor: hasDoor,
                bearingDegrees: wallBearing(from: wall.transform)
            )
        }
    }

    // MARK: - Opening mapping

    private static func mapOpenings(
        doors: [CapturedRoom.Surface],
        windows: [CapturedRoom.Surface],
        openings: [CapturedRoom.Surface],
        walls: [CapturedRoom.Surface]
    ) -> [ScannedOpening] {
        var result: [ScannedOpening] = []

        for surface in doors {
            result.append(ScannedOpening(
                kind: .door,
                wallIndex: nearestWallIndex(for: surface, walls: walls),
                widthMetres: Double(surface.dimensions.x),
                heightMetres: Double(surface.dimensions.y)
            ))
        }
        for surface in windows {
            result.append(ScannedOpening(
                kind: .window,
                wallIndex: nearestWallIndex(for: surface, walls: walls),
                widthMetres: Double(surface.dimensions.x),
                heightMetres: Double(surface.dimensions.y)
            ))
        }
        for surface in openings {
            result.append(ScannedOpening(
                kind: .archway,
                wallIndex: nearestWallIndex(for: surface, walls: walls),
                widthMetres: Double(surface.dimensions.x),
                heightMetres: Double(surface.dimensions.y)
            ))
        }

        return result
    }

    // MARK: - Geometry helpers (internal for unit testing)

    /// Computes the compass bearing of the wall's length direction from a wall surface transform.
    ///
    /// Returns degrees 0–360 where 0 = North (+Z axis) and 90 = East (+X axis).
    /// The wall's local X-axis (column 0 of the transform) runs along the wall length.
    static func wallBearing(from transform: simd_float4x4) -> Double {
        let dx = transform.columns.0.x
        let dz = transform.columns.0.z
        let radians = atan2(Double(dx), Double(dz))
        let degrees = radians * 180.0 / .pi
        return degrees < 0 ? degrees + 360.0 : degrees
    }

    /// Returns the index of the wall whose centre is closest (by horizontal distance) to the
    /// given surface. Falls back to 0 when the walls array is empty.
    static func nearestWallIndex(
        for surface: CapturedRoom.Surface,
        walls: [CapturedRoom.Surface]
    ) -> Int {
        nearestWallIndex(
            surfaceX: surface.transform.columns.3.x,
            surfaceZ: surface.transform.columns.3.z,
            wallCentres: walls.map { (x: $0.transform.columns.3.x, z: $0.transform.columns.3.z) }
        )
    }

    /// Core nearest-wall logic using raw XZ coordinates.
    /// Separated from the RoomPlan surface overload so it can be tested without the framework.
    static func nearestWallIndex(
        surfaceX: Float,
        surfaceZ: Float,
        wallCentres: [(x: Float, z: Float)]
    ) -> Int {
        guard !wallCentres.isEmpty else { return 0 }
        var nearest = 0
        var nearestDist = Float.infinity
        for (i, wall) in wallCentres.enumerated() {
            let dx = surfaceX - wall.x
            let dz = surfaceZ - wall.z
            let dist = (dx * dx + dz * dz).squareRoot()
            if dist < nearestDist {
                nearestDist = dist
                nearest = i
            }
        }
        return nearest
    }

    // MARK: - Room metric helpers

    /// Total floor area from floor surfaces, or a rectangle estimate from wall lengths.
    private static func computeFloorArea(
        _ floors: [CapturedRoom.Surface],
        walls: [CapturedRoom.Surface]
    ) -> Double? {
        if !floors.isEmpty {
            let total = floors.reduce(0.0) { $0 + Double($1.dimensions.x * $1.dimensions.z) }
            return total > 0 ? total : nil
        }
        // Fallback: estimate from wall lengths as a rectangle
        guard walls.count >= 2 else { return nil }
        let lengths = walls.map { Double($0.dimensions.x) }.sorted()
        let half = lengths.count / 2
        let shorter = lengths[0..<half].reduce(0, +) / Double(max(half, 1))
        let longer  = lengths[half...].reduce(0, +) / Double(max(lengths.count - half, 1))
        return shorter * longer
    }

    /// Average ceiling height derived from wall surface heights (dimensions.y).
    /// Returns nil when no walls are available.
    private static func computeCeilingHeight(_ walls: [CapturedRoom.Surface]) -> Double? {
        guard !walls.isEmpty else { return nil }
        let heights = walls.map { Double($0.dimensions.y) }
        return heights.reduce(0, +) / Double(heights.count)
    }
}
