import Foundation
import Combine

// MARK: - MockScannerAdapter
//
// Used during development so the object-tagging and export pipelines can be
// exercised without a physical device or the RoomPlan framework.
// Replace with RoomPlanScannerAdapter in PR 2.

final class MockScannerAdapter: ScannerAdapterProtocol {

    // MARK: Publishers

    private let stateSubject = CurrentValueSubject<ScannerState, Never>(.idle)
    private let capturedRoomSubject = PassthroughSubject<ScannedRoom, Never>()

    var statePublisher: AnyPublisher<ScannerState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    var capturedRoomPublisher: AnyPublisher<ScannedRoom, Never> {
        capturedRoomSubject.eraseToAnyPublisher()
    }

    // MARK: State

    private var simulationTask: Task<Void, Never>?
    private var currentJobID: UUID = UUID()
    private var currentRoomName: String = ""

    // MARK: ScannerAdapterProtocol

    func startCapture(jobID: UUID, roomName: String) {
        currentJobID = jobID
        currentRoomName = roomName
        stateSubject.send(.initialising)

        simulationTask = Task { [weak self] in
            guard let self else { return }

            // Simulate initialisation delay
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            stateSubject.send(.scanning)

            // Simulate scan duration
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            stateSubject.send(.processing)

            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }

            let room = MockScannerAdapter.makeMockRoom(jobID: jobID, name: roomName)
            stateSubject.send(.completed(room))
            capturedRoomSubject.send(room)
        }
    }

    func stopCapture() {
        simulationTask?.cancel()
        simulationTask = nil
        guard case .scanning = stateSubject.value else { return }
        stateSubject.send(.processing)

        // Simulate brief processing then deliver the mock room.
        let jobID = currentJobID
        let name = currentRoomName
        simulationTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            let room = MockScannerAdapter.makeMockRoom(jobID: jobID, name: name)
            stateSubject.send(.completed(room))
            capturedRoomSubject.send(room)
        }
    }

    func cancelCapture() {
        simulationTask?.cancel()
        simulationTask = nil
        stateSubject.send(.idle)
    }

    // MARK: Mock room geometry

    private static func makeMockRoom(jobID: UUID, name: String) -> ScannedRoom {
        let walls = (0..<4).map { i in
            ScannedWall(
                index: i,
                lengthMetres: [3.8, 4.2, 3.8, 4.2][i],
                heightMetres: 2.4,
                isExternalWall: i == 0 || i == 1,
                hasWindow: i == 0,
                hasDoor: i == 2
            )
        }

        let openings = [
            ScannedOpening(kind: .window, wallIndex: 0, widthMetres: 1.2, heightMetres: 1.1),
            ScannedOpening(kind: .door,   wallIndex: 2, widthMetres: 0.85, heightMetres: 2.0),
        ]

        return ScannedRoom(
            jobID: jobID,
            name: name,
            floor: 0,
            areaSquareMetres: 15.96,
            ceilingHeightMetres: 2.4,
            walls: walls,
            openings: openings,
            geometryCaptured: true
        )
    }
}
