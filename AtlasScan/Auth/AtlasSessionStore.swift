import Foundation

struct AtlasPersistedSessionV1: Codable, Sendable {
    var authSession: AtlasAuthSessionV1
    var workspaces: [AtlasWorkspaceV1]
    var selectedWorkspace: AtlasWorkspaceV1?
    var selectedVisit: AtlasVisitIdentityV1?
}

final class AtlasSessionStore {
    static let shared = AtlasSessionStore()

    private let defaults: UserDefaults
    private let sessionKey = "atlas.auth.persistedSession.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> AtlasPersistedSessionV1? {
        guard let data = defaults.data(forKey: sessionKey) else { return nil }
        return try? JSONDecoder().decode(AtlasPersistedSessionV1.self, from: data)
    }

    func save(_ snapshot: AtlasPersistedSessionV1) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: sessionKey)
    }

    func clear() {
        defaults.removeObject(forKey: sessionKey)
    }

    func loadLocalOrphanVisits() -> [AtlasVisitIdentityV1] {
        CaptureSessionPersistence.shared.loadAll()
            .filter { draft in
                draft.appointmentId == nil && draft.exportState != .exported
            }
            .map { draft in
                let fallbackReference = "LOCAL-\(draft.id.uuidString.prefix(8))"
                let reference = draft.visitReference.trimmingCharacters(in: .whitespacesAndNewlines)
                return AtlasVisitIdentityV1(
                    id: draft.id.uuidString,
                    visitReference: reference.isEmpty ? fallbackReference : reference,
                    propertyAddress: draft.propertyAddress.isEmpty ? nil : draft.propertyAddress,
                    status: "draft",
                    scheduledAtISO8601: nil,
                    source: .localOrphanDebug
                )
            }
    }
}
