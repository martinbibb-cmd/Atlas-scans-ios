/// AtlasVisitSyncService — Boundary protocol for the future
/// Atlas-Mind ⇄ Atlas-Scan visit sync, with two implementations:
///
///   - `DevLocalAtlasVisitSyncService` — backed by `AtlasAuthService`'s
///     local fixtures (used today by the dev mock auth path).
///   - `FutureRemoteAtlasVisitSyncService` — placeholder; throws
///     `.notImplemented` until the real Mind sync API is plumbed in.
///
/// The continuous-survey shell talks to this protocol *only* — it never
/// calls `AtlasAuthService` directly for visit operations. This keeps a clean
/// seam for swapping the local impl out for the remote one in a later PR.

import Foundation

@MainActor
protocol AtlasVisitSyncService: AnyObject {
    /// Lists visits for `workspaceId`. May return locally-cached visits in
    /// addition to anything fetched from a remote.
    func listVisits(workspaceId: String) async throws -> [AtlasVisitIdentityV1]

    /// Fetches a specific visit by id, throwing if not found.
    func fetchVisit(id: String, workspaceId: String) async throws -> AtlasVisitIdentityV1

    /// Creates a new Mind visit in `workspaceId`.
    func createVisit(workspaceId: String) async throws -> AtlasVisitIdentityV1
}

enum AtlasVisitSyncError: LocalizedError, Sendable {
    case notImplemented
    case visitNotFound(String)
    case missingAuthSession

    var errorDescription: String? {
        switch self {
        case .notImplemented:
            return "Remote Atlas-Mind visit sync is not implemented yet."
        case .visitNotFound(let id):
            return "Visit \(id) was not found."
        case .missingAuthSession:
            return "An authenticated session is required to sync visits."
        }
    }
}

// MARK: - Local-fixtures impl (current default)

/// Uses the existing `AtlasAuthService` to source visits from local fixtures
/// (the dev mock). This is the implementation the
/// shell uses today; it will be swapped for `FutureRemoteAtlasVisitSyncService`
/// once the Mind backend is ready.
@MainActor
final class DevLocalAtlasVisitSyncService: AtlasVisitSyncService {
    private let authService: AtlasAuthService
    private let sessionProvider: () -> AtlasAuthSessionV1?

    init(
        authService: AtlasAuthService,
        sessionProvider: @escaping () -> AtlasAuthSessionV1?
    ) {
        self.authService = authService
        self.sessionProvider = sessionProvider
    }

    func listVisits(workspaceId: String) async throws -> [AtlasVisitIdentityV1] {
        guard let session = sessionProvider() else {
            throw AtlasVisitSyncError.missingAuthSession
        }
        return try await authService.fetchVisits(workspaceId: workspaceId, session: session)
    }

    func fetchVisit(id: String, workspaceId: String) async throws -> AtlasVisitIdentityV1 {
        let visits = try await listVisits(workspaceId: workspaceId)
        guard let match = visits.first(where: { $0.id == id }) else {
            throw AtlasVisitSyncError.visitNotFound(id)
        }
        return match
    }

    func createVisit(workspaceId: String) async throws -> AtlasVisitIdentityV1 {
        guard let session = sessionProvider() else {
            throw AtlasVisitSyncError.missingAuthSession
        }
        return try await authService.createVisit(workspaceId: workspaceId, session: session)
    }
}

// MARK: - Future remote impl (stub)

/// Placeholder for the future Atlas-Mind backend sync. All methods currently
/// throw `.notImplemented`. Wire this up once the remote API is live.
@MainActor
final class FutureRemoteAtlasVisitSyncService: AtlasVisitSyncService {
    init() {}

    func listVisits(workspaceId: String) async throws -> [AtlasVisitIdentityV1] {
        throw AtlasVisitSyncError.notImplemented
    }

    func fetchVisit(id: String, workspaceId: String) async throws -> AtlasVisitIdentityV1 {
        throw AtlasVisitSyncError.notImplemented
    }

    func createVisit(workspaceId: String) async throws -> AtlasVisitIdentityV1 {
        throw AtlasVisitSyncError.notImplemented
    }
}
