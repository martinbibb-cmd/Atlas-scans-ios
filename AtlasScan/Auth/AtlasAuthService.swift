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
    case missingGoogleClientID
    case missingPresentationContext
    case googleSignInUnavailable
    case missingGoogleToken
    case notAuthenticated
    case firebaseAuthFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingGoogleClientID:
            return "Missing GIDClientID in Info.plist."
        case .missingPresentationContext:
            return "Unable to present Google Sign-In."
        case .googleSignInUnavailable:
            return "Google Sign-In is unavailable in this build."
        case .missingGoogleToken:
            return "Google sign-in succeeded but no token was returned."
        case .notAuthenticated:
            return "Sign in is required."
        case .firebaseAuthFailed(let message):
            return "Firebase authentication failed: \(message)"
        }
    }
}

@MainActor
protocol AtlasAuthService {
    func restoreSession() async throws -> AtlasAuthSessionV1?
    func signInWithGoogle() async throws -> AtlasAuthSessionV1
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
