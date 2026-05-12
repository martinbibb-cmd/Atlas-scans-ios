/// ARPinRenderer — Re-anchors `worldLocked` pins from `SpatialEvidenceStore`
/// when the user re-enters a previously-captured room.
///
/// This file is the seam between `SpatialEvidenceStore` (pure data, codable,
/// no platform deps) and the existing AR/ARKit code in `AtlasScan/V2/AR/`.
/// The actual ARKit anchor placement is left to a follow-up wiring PR; this
/// renderer exposes the policy ("which pins render, when, where") so the
/// AR layer just consumes a list of placement requests.

import Foundation
import simd

@MainActor
public final class ARPinRenderer: ObservableObject {

    public struct PlacementRequest: Identifiable, Sendable, Equatable {
        public let id: UUID
        public let pinId: UUID
        public let roomId: UUID
        public let category: EquipmentObjectCategory
        public let worldTransformElements: [Double]

        public init(
            id: UUID = UUID(),
            pinId: UUID,
            roomId: UUID,
            category: EquipmentObjectCategory,
            worldTransformElements: [Double]
        ) {
            self.id = id
            self.pinId = pinId
            self.roomId = roomId
            self.category = category
            self.worldTransformElements = worldTransformElements
        }
    }

    @Published public private(set) var activePlacements: [PlacementRequest] = []

    private let store: SpatialEvidenceStore

    public init(store: SpatialEvidenceStore = .shared) {
        self.store = store
    }

    /// Called when the user enters (or re-enters) `roomId`. Computes the set
    /// of placement requests for the room's renderable pins. Only pins whose
    /// `AnchorConfidence.canRenderInAR` is true (currently `worldLocked`
    /// only) are returned — `raycastEstimated`, `screenOnly`, and `manual`
    /// pins are intentionally excluded from AR re-rendering and surface in
    /// the review screen instead.
    public func enterRoom(_ roomId: UUID) {
        let pins = store.renderablePins(in: roomId)
        activePlacements = pins.compactMap { pin -> PlacementRequest? in
            guard let transform = pin.worldTransform else { return nil }
            return PlacementRequest(
                pinId: pin.id,
                roomId: roomId,
                category: pin.objectCategory,
                worldTransformElements: transform.matrix
            )
        }
    }

    /// Called when the user leaves the active room (or the survey ends).
    public func leaveRoom() {
        activePlacements = []
    }

    /// Bridge helper: convert flat 16-double row-major matrix into a
    /// `simd_float4x4` for the AR layer.
    public static func simdTransform(from elements: [Double]) -> simd_float4x4 {
        precondition(elements.count == 16, "Expected 16 transform elements")
        let f = elements.map { Float($0) }
        return simd_float4x4(
            SIMD4<Float>(f[0],  f[1],  f[2],  f[3]),
            SIMD4<Float>(f[4],  f[5],  f[6],  f[7]),
            SIMD4<Float>(f[8],  f[9],  f[10], f[11]),
            SIMD4<Float>(f[12], f[13], f[14], f[15])
        )
    }
}
