import Foundation

@MainActor
final class DevMockAtlasAuthService: AtlasAuthService {
    func restoreSession() async throws -> AtlasAuthSessionV1? {
        guard let token = AtlasKeychainStore.loadAuthToken() else { return nil }
        return AtlasAuthSessionV1(
            profile: AtlasUserProfileV1(
                id: "dev-engineer",
                email: "engineer@atlas-phm.uk",
                displayName: "Atlas Engineer"
            ),
            authToken: token,
            providerUserId: "dev-engineer"
        )
    }

    func signInWithGoogle() async throws -> AtlasAuthSessionV1 {
        let token = "dev-token-\(UUID().uuidString)"
        AtlasKeychainStore.saveAuthToken(token)
        return AtlasAuthSessionV1(
            profile: AtlasUserProfileV1(
                id: "dev-engineer",
                email: "engineer@atlas-phm.uk",
                displayName: "Atlas Engineer"
            ),
            authToken: token,
            providerUserId: "dev-engineer"
        )
    }

    func signOut() async {
        AtlasKeychainStore.deleteAuthToken()
    }

    func fetchWorkspaces(for session: AtlasAuthSessionV1) async throws -> [AtlasWorkspaceV1] {
        let namePrefix = session.profile.displayName?.split(separator: " ").first.map(String.init) ?? "Atlas"
        return [
            AtlasWorkspaceV1(id: "workspace-mind", name: "\(namePrefix) Mind Workspace"),
            AtlasWorkspaceV1(id: "workspace-training", name: "\(namePrefix) Training Workspace")
        ]
    }

    func fetchVisits(
        workspaceId: String,
        session: AtlasAuthSessionV1
    ) async throws -> [AtlasVisitIdentityV1] {
        _ = workspaceId
        _ = session
        return [
            AtlasVisitIdentityV1(
                id: "mind-visit-001",
                visitReference: "JOB-2026-0101",
                propertyAddress: "12 Coronation Street, Manchester",
                status: "scheduled",
                scheduledAtISO8601: "2026-05-12T09:00:00Z",
                source: .mind
            ),
            AtlasVisitIdentityV1(
                id: "mind-visit-002",
                visitReference: "JOB-2026-0102",
                propertyAddress: "47 Baker Street, London",
                status: "confirmed",
                scheduledAtISO8601: "2026-05-12T14:00:00Z",
                source: .mind
            )
        ]
    }

    func createVisit(
        workspaceId: String,
        session: AtlasAuthSessionV1
    ) async throws -> AtlasVisitIdentityV1 {
        _ = workspaceId
        _ = session
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let short = String(timestamp.prefix(10)).replacingOccurrences(of: "-", with: "")
        return AtlasVisitIdentityV1(
            id: "mind-visit-\(UUID().uuidString)",
            visitReference: "JOB-\(short)-\(Int.random(in: 100...999))",
            propertyAddress: nil,
            status: "in_progress",
            scheduledAtISO8601: timestamp,
            source: .mind
        )
    }
}
