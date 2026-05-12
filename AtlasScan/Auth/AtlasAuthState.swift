import Foundation

@MainActor
final class AtlasAuthState: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var authSession: AtlasAuthSessionV1?
    @Published private(set) var workspaces: [AtlasWorkspaceV1] = []
    @Published private(set) var visits: [AtlasVisitIdentityV1] = []
    @Published var selectedWorkspace: AtlasWorkspaceV1?
    @Published var selectedVisit: AtlasVisitIdentityV1?
    @Published var errorMessage: String?

    private let authService: AtlasAuthService
    private let sessionStore: AtlasSessionStore

    var profile: AtlasUserProfileV1? { authSession?.profile }
    var isAuthenticated: Bool { authSession != nil }

    init(
        authService: AtlasAuthService = GoogleAtlasAuthService(),
        sessionStore: AtlasSessionStore = .shared
    ) {
        self.authService = authService
        self.sessionStore = sessionStore
    }

    func bootstrap() async {
        if let persisted = sessionStore.load() {
            authSession = persisted.authSession
            workspaces = persisted.workspaces
            selectedWorkspace = persisted.selectedWorkspace
            selectedVisit = persisted.selectedVisit
        }

        do {
            if let restored = try await authService.restoreSession() {
                authSession = restored
                try await refreshWorkspacesIfNeeded()
                if let selectedWorkspace {
                    try await refreshVisits(for: selectedWorkspace)
                }
                persistSnapshot()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signInWithGoogle() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        do {
            let session = try await authService.signInWithGoogle()
            authSession = session
            selectedWorkspace = nil
            selectedVisit = nil
            visits = []
            workspaces = try await authService.fetchWorkspaces(for: session)
            if workspaces.count == 1, let first = workspaces.first {
                selectedWorkspace = first
            }
            persistSnapshot()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func chooseWorkspace(_ workspace: AtlasWorkspaceV1) {
        selectedWorkspace = workspace
        selectedVisit = nil
        visits = []
        errorMessage = nil
        persistSnapshot()
    }

    func refreshVisits() async {
        guard let session = authSession,
              let workspace = selectedWorkspace
        else {
            errorMessage = AtlasAuthError.notAuthenticated.localizedDescription
            return
        }

        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        do {
            try await refreshVisits(for: workspace, using: session)
            persistSnapshot()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createMindVisit() async {
        guard let session = authSession,
              let workspace = selectedWorkspace
        else {
            errorMessage = AtlasAuthError.notAuthenticated.localizedDescription
            return
        }

        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        do {
            let visit = try await authService.createVisit(workspaceId: workspace.id, session: session)
            selectedVisit = visit
            try await refreshVisits(for: workspace, using: session)
            if !visits.contains(where: { $0.id == visit.id }) {
                visits.insert(visit, at: 0)
            }
            persistSnapshot()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func chooseVisit(_ visit: AtlasVisitIdentityV1) {
        selectedVisit = visit
        errorMessage = nil
        persistSnapshot()
    }

    func clearSelectedVisit() {
        selectedVisit = nil
        persistSnapshot()
    }

    func clearWorkspaceSelection() {
        selectedWorkspace = nil
        selectedVisit = nil
        visits = []
        persistSnapshot()
    }

    func signOut() async {
        isLoading = true
        defer { isLoading = false }
        await authService.signOut()
        authSession = nil
        selectedWorkspace = nil
        selectedVisit = nil
        workspaces = []
        visits = []
        errorMessage = nil
        sessionStore.clear()
    }

    private func refreshWorkspacesIfNeeded() async throws {
        guard let session = authSession else { return }
        if workspaces.isEmpty {
            workspaces = try await authService.fetchWorkspaces(for: session)
        }
        if selectedWorkspace == nil, workspaces.count == 1 {
            selectedWorkspace = workspaces.first
        }
    }

    private func refreshVisits(
        for workspace: AtlasWorkspaceV1,
        using session: AtlasAuthSessionV1? = nil
    ) async throws {
        let activeSession = session ?? authSession
        guard let activeSession else { throw AtlasAuthError.notAuthenticated }
        var remote = try await authService.fetchVisits(workspaceId: workspace.id, session: activeSession)
        let orphan = sessionStore.loadLocalOrphanVisits()
        if !orphan.isEmpty {
            remote.append(contentsOf: orphan)
        }
        visits = remote
    }

    private func persistSnapshot() {
        guard let authSession else { return }
        sessionStore.save(
            AtlasPersistedSessionV1(
                authSession: authSession,
                workspaces: workspaces,
                selectedWorkspace: selectedWorkspace,
                selectedVisit: selectedVisit
            )
        )
    }
}
