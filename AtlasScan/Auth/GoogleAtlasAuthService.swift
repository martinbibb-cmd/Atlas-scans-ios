import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif
#if canImport(FirebaseCore)
import FirebaseCore
#endif

@MainActor
final class GoogleAtlasAuthService: AtlasAuthService {
    private let visitClient: CloudflareVisitClient
    private let fallbackService: DevMockAtlasAuthService

    init(
        visitClient: CloudflareVisitClient = .shared,
        fallbackService: DevMockAtlasAuthService = DevMockAtlasAuthService()
    ) {
        self.visitClient = visitClient
        self.fallbackService = fallbackService
    }

    func restoreSession() async throws -> AtlasAuthSessionV1? {
#if canImport(GoogleSignIn)
        if GIDSignIn.sharedInstance.hasPreviousSignIn {
            let result = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
            return try await makeSession(from: result.user)
        }
#endif
        if let fallback = try await fallbackService.restoreSession() {
            return fallback
        }
        return nil
    }

    func signInWithGoogle() async throws -> AtlasAuthSessionV1 {
#if canImport(GoogleSignIn) && canImport(UIKit)
#if canImport(FirebaseCore)
        if FirebaseApp.app() == nil,
           Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            FirebaseApp.configure()
        }
#endif
        let plistClientID = (Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
#if canImport(FirebaseCore)
        let firebaseClientID = FirebaseApp.app()?.options.clientID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
#else
        let firebaseClientID: String? = nil
#endif
        guard let clientID = [plistClientID, firebaseClientID].compactMap({ $0 }).first(where: { !$0.isEmpty })
        else {
            throw AtlasAuthError.missingGoogleClientID
        }

        guard let presenting = Self.topViewController() else {
            throw AtlasAuthError.missingPresentationContext
        }

        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenting)
        return try await makeSession(from: result.user)
#else
        return try await fallbackService.signInWithGoogle()
#endif
    }

    func signOut() async {
#if canImport(FirebaseAuth)
        try? Auth.auth().signOut()
#endif
#if canImport(GoogleSignIn)
        GIDSignIn.sharedInstance.signOut()
#endif
        AtlasKeychainStore.deleteAuthToken()
    }

    func fetchWorkspaces(for session: AtlasAuthSessionV1) async throws -> [AtlasWorkspaceV1] {
        let display = session.profile.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let shortName = (display?.isEmpty == false ? display! : "Atlas")
        return [
            AtlasWorkspaceV1(id: "mind-primary", name: "\(shortName) Workspace")
        ]
    }

    func fetchVisits(
        workspaceId: String,
        session: AtlasAuthSessionV1
    ) async throws -> [AtlasVisitIdentityV1] {
        _ = workspaceId
        _ = session
        do {
            let visits = try await visitClient.fetchUpcomingVisits()
            return visits.map {
                AtlasVisitIdentityV1(
                    id: $0.id,
                    visitReference: $0.visitReference,
                    propertyAddress: $0.propertyAddress,
                    status: $0.status,
                    scheduledAtISO8601: $0.scheduledAt,
                    source: .mind
                )
            }
        } catch {
            return try await fallbackService.fetchVisits(workspaceId: workspaceId, session: session)
        }
    }

    func createVisit(
        workspaceId: String,
        session: AtlasAuthSessionV1
    ) async throws -> AtlasVisitIdentityV1 {
        _ = workspaceId
        let dateCode = DateFormatter.jobCodeFormatter.string(from: Date())
        let emailPrefix = session.profile.email?
            .split(separator: "@")
            .first
            .map(String.init)
            .prefix(4)
            .uppercased() ?? "ATLS"
        let reference = "JOB-\(dateCode)-\(emailPrefix)"

        do {
            let remoteId = try await visitClient.createVisit(reference: reference, propertyAddress: nil)
            return AtlasVisitIdentityV1(
                id: remoteId,
                visitReference: reference,
                propertyAddress: nil,
                status: "in_progress",
                scheduledAtISO8601: ISO8601DateFormatter().string(from: Date()),
                source: .mind
            )
        } catch {
            return try await fallbackService.createVisit(workspaceId: workspaceId, session: session)
        }
    }

#if canImport(GoogleSignIn)
    private func makeSession(from user: GIDGoogleUser) async throws -> AtlasAuthSessionV1 {
        let token = try await exchangeFirebaseToken(using: user)
        guard !token.isEmpty else {
            throw AtlasAuthError.missingGoogleToken
        }

        AtlasKeychainStore.saveAuthToken(token)

        return AtlasAuthSessionV1(
            profile: AtlasUserProfileV1(
                id: user.userID ?? user.profile?.email ?? UUID().uuidString,
                email: user.profile?.email,
                displayName: user.profile?.name
            ),
            authToken: token,
            providerUserId: user.userID
        )
    }

    private func exchangeFirebaseToken(using user: GIDGoogleUser) async throws -> String {
#if canImport(FirebaseAuth)
        guard let idToken = user.idToken?.tokenString, !idToken.isEmpty else {
            throw AtlasAuthError.missingGoogleIDTokenForFirebase
        }
        let accessToken = user.accessToken.tokenString
        let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)
        do {
            let authResult = try await Auth.auth().signIn(with: credential)
            return try await authResult.user.getIDToken()
        } catch {
            throw AtlasAuthError.firebaseAuthFailed(error.localizedDescription)
        }
#else
        throw AtlasAuthError.firebaseAuthUnavailable
#endif
    }
#endif

#if canImport(UIKit)
    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let window = scenes
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        var root = window?.rootViewController
        while let presented = root?.presentedViewController {
            root = presented
        }
        return root
    }
#endif
}

private extension DateFormatter {
    static let jobCodeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}
