import Foundation

struct AtlasUserProfileV1: Codable, Equatable, Sendable {
    let id: String
    let email: String?
    let displayName: String?
}

struct AtlasWorkspaceV1: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
}

enum AtlasVisitSourceV1: String, Codable, Sendable {
    case mind
    case localOrphanDebug
}

struct AtlasVisitIdentityV1: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let visitReference: String
    let propertyAddress: String?
    let status: String
    let scheduledAtISO8601: String?
    let source: AtlasVisitSourceV1
}

struct AtlasAuthSessionV1: Codable, Equatable, Sendable {
    let profile: AtlasUserProfileV1
    let authToken: String
    let providerUserId: String?
}

enum AtlasAuthError: LocalizedError {
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Sign in is required."
        }
    }
}

@MainActor
protocol AtlasAuthService {
    func restoreSession() async throws -> AtlasAuthSessionV1?
    func signIn() async throws -> AtlasAuthSessionV1
    func signOut() async
    func fetchWorkspaces(for session: AtlasAuthSessionV1) async throws -> [AtlasWorkspaceV1]
    func fetchVisits(
        workspaceId: String,
        session: AtlasAuthSessionV1
    ) async throws -> [AtlasVisitIdentityV1]
    func createVisit(
        workspaceId: String,
        session: AtlasAuthSessionV1
    ) async throws -> AtlasVisitIdentityV1
}
