/// SpatialEvidenceStore — Persists `ExistingEquipmentPinV1` records keyed by
/// roomId / anchorId so the AR pin renderer can re-anchor world-locked pins
/// when the user re-enters a room mid-survey.
///
/// Backed by `UserDefaults` for simplicity; the brief calls out future work
/// to merge this into `AtomicSessionStore`. For now we keep the two stores
/// separate so the survey-shell can ship independently of any session-schema
/// changes.

import Foundation

@MainActor
public final class SpatialEvidenceStore: ObservableObject {

    public static let shared = SpatialEvidenceStore()

    public static let storageKey = "atlas.survey.spatialEvidence.v1"

    @Published public private(set) var pinsByRoom: [UUID: [ExistingEquipmentPinV1]] = [:]

    private let defaults: UserDefaults
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // MARK: - Mutations

    /// Adds (or replaces) `pin` in the room's bucket. Replaces in-place when
    /// a pin with the same id is already present. Pins without a roomId are
    /// dropped silently — they belong in a future "unbound pins" review queue.
    public func upsert(_ pin: ExistingEquipmentPinV1) {
        guard let roomId = pin.roomId else { return }
        var bucket = pinsByRoom[roomId, default: []]
        if let idx = bucket.firstIndex(where: { $0.id == pin.id }) {
            bucket[idx] = pin
        } else {
            bucket.append(pin)
        }
        pinsByRoom[roomId] = bucket
        persist()
    }

    public func remove(pinId: UUID, fromRoom roomId: UUID) {
        guard var bucket = pinsByRoom[roomId] else { return }
        bucket.removeAll(where: { $0.id == pinId })
        pinsByRoom[roomId] = bucket.isEmpty ? nil : bucket
        persist()
    }

    public func pins(in roomId: UUID) -> [ExistingEquipmentPinV1] {
        pinsByRoom[roomId] ?? []
    }

    /// Pins that should appear in AR for `roomId`. Only `worldLocked` and
    /// `raycastEstimated` pins are returned — `screenOnly`/`manual` pins are
    /// filtered out and surface in the review screen instead.
    public func renderablePins(in roomId: UUID) -> [ExistingEquipmentPinV1] {
        pins(in: roomId).filter { $0.anchorConfidence.canRenderInAR }
    }

    /// Pins that need engineer review (anchor is `screenOnly`/`manual`, or
    /// the pin was explicitly flagged).
    public func reviewQueue(in roomId: UUID) -> [ExistingEquipmentPinV1] {
        pins(in: roomId).filter { $0.anchorConfidence.requiresReview || $0.reviewStatus == .needsReview }
    }

    // MARK: - Persistence

    private func persist() {
        guard let data = try? encoder.encode(pinsByRoom) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private func load() {
        guard let data = defaults.data(forKey: Self.storageKey),
              let decoded = try? decoder.decode([UUID: [ExistingEquipmentPinV1]].self, from: data)
        else { return }
        pinsByRoom = decoded
    }
}
