import Foundation
import Combine

// MARK: - ScannerAdapterProtocol
//
// Abstracts the scanner framework (e.g. RoomPlan) from the app's capture flow.
// Swap MockScannerAdapter for RoomPlanScannerAdapter in PR 2.

protocol ScannerAdapterProtocol: AnyObject {
    var statePublisher: AnyPublisher<ScannerState, Never> { get }
    var capturedRoomPublisher: AnyPublisher<ScannedRoom, Never> { get }

    func startCapture(jobID: UUID, roomName: String)
    func stopCapture()
    func cancelCapture()
}

// MARK: - ScannerState

enum ScannerState: Equatable {
    case idle
    case initialising
    case scanning
    case processing
    case completed(ScannedRoom)
    case failed(String)

    var isActive: Bool {
        switch self {
        case .initialising, .scanning, .processing: return true
        default: return false
        }
    }

    static func == (lhs: ScannerState, rhs: ScannerState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.initialising, .initialising),
             (.scanning, .scanning),
             (.processing, .processing):
            return true
        case (.completed(let a), .completed(let b)):
            return a.id == b.id
        case (.failed(let a), .failed(let b)):
            return a == b
        default:
            return false
        }
    }
}
