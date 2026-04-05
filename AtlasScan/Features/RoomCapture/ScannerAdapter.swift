import Foundation
import Combine
import UIKit

// MARK: - ScannerAdapterProtocol
//
// Abstracts the scanner framework (e.g. RoomPlan) from the app's capture flow.
// MockScannerAdapter is used for simulator/previews; RoomPlanScannerAdapter on
// LiDAR-capable hardware.

protocol ScannerAdapterProtocol: AnyObject {
    var statePublisher: AnyPublisher<ScannerState, Never> { get }
    var capturedRoomPublisher: AnyPublisher<ScannedRoom, Never> { get }

    /// Live-camera UIView displayed during capture.
    /// Returns nil for adapters with no camera feed (e.g. MockScannerAdapter).
    var scannerView: UIView? { get }

    func startCapture(jobID: UUID, roomName: String)
    func stopCapture()
    func cancelCapture()
}

extension ScannerAdapterProtocol {
    var scannerView: UIView? { nil }
}

// MARK: - ScannerState

enum ScannerState: Equatable {
    case idle
    case initialising
    case scanning
    case processing
    case completed(ScannedRoom)
    case failed(String)
    /// Device does not support LiDAR / RoomPlan.
    case unsupported
    /// User denied camera permission.
    case permissionDenied

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
             (.processing, .processing),
             (.unsupported, .unsupported),
             (.permissionDenied, .permissionDenied):
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
