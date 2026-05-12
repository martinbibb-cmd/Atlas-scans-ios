/// MeasurementCaptureService — Thin wrapper that produces
/// `SpatialMeasurementV1` records from two captured world positions.
///
/// The shell hands in the two endpoints (typically resolved from raycasts in
/// `ContinuousSurveyView`) plus their surface semantics; this service handles
/// the boilerplate distance derivation and `needsReview` flagging.

import Foundation
import simd
import AtlasScanCore

@MainActor
public final class MeasurementCaptureService {

    public init() {}

    /// Builds a `SpatialMeasurementV1` between two capture points.
    public func record(
        roomId: UUID,
        startCapturePointId: UUID,
        endCapturePointId: UUID,
        startWorldPosition: SIMD3<Double>,
        endWorldPosition: SIMD3<Double>,
        startSurfaceSemantic: SurfaceSemanticV1 = .unknown,
        endSurfaceSemantic: SurfaceSemanticV1 = .unknown,
        anchorConfidence: SpatialPinAnchorConfidence = .raycastEstimated,
        notes: String? = nil
    ) -> SpatialMeasurementV1 {
        SpatialMeasurementV1(
            roomId: roomId,
            startCapturePointId: startCapturePointId,
            endCapturePointId: endCapturePointId,
            startWorldPosition: startWorldPosition,
            endWorldPosition: endWorldPosition,
            startSurfaceSemantic: startSurfaceSemantic,
            endSurfaceSemantic: endSurfaceSemantic,
            anchorConfidence: anchorConfidence,
            notes: notes
        )
    }
}
