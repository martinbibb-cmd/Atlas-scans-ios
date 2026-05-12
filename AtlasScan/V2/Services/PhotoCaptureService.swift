/// PhotoCaptureService — Thin wrapper around the existing `PhotoStore`,
/// returning the new survey-shell model types (`PhotoEvidenceV1` plus the
/// optional `CapturePointV1` linkage).
///
/// The continuous-survey shell talks to this service rather than `PhotoStore`
/// directly, so that all capture-side I/O goes through a single seam — easier
/// to mock in tests and to swap for a future remote photo upload.

import Foundation
#if canImport(UIKit)
import UIKit
#endif
import AtlasScanCore

@MainActor
final class PhotoCaptureService {
    private let store: PhotoStore

    init(store: PhotoStore = .shared) {
        self.store = store
    }

    enum CaptureError: Error, LocalizedError {
        case encodingFailed
        case missingRoom
        var errorDescription: String? {
            switch self {
            case .encodingFailed: return "Could not encode photo for storage."
            case .missingRoom:    return "A confirmed room is required before capturing photos."
            }
        }
    }

    #if canImport(UIKit)
    /// Saves `image` and returns a fully-populated `PhotoEvidenceV1`.
    func capture(
        image: UIImage,
        visitId: UUID,
        roomId: UUID,
        capturePointId: UUID? = nil,
        linkedObjectId: UUID? = nil
    ) throws -> PhotoEvidenceV1 {
        let id = UUID()
        let result = try store.save(image, id: id)
        return PhotoEvidenceV1(
            id: id,
            visitId: visitId,
            roomId: roomId,
            capturePointId: capturePointId,
            linkedObjectId: linkedObjectId,
            relativeFilePath: "Photos/\(result.filename)"
        )
    }
    #endif
}
