/// MindRecallClient — Fetches a previously-uploaded session from Atlas Mind.

import Foundation
import AtlasScanCore

@MainActor
public final class MindRecallClient: ObservableObject {
    @Published public var isRecalling = false
    @Published public var recallError: Error?

    public var store: AtomicSessionStore?

    public init(store: AtomicSessionStore? = nil) {
        self.store = store
    }

    public func recall(visitId: UUID) async throws -> SessionCaptureV2 {
        isRecalling = true
        defer { isRecalling = false }
        recallError = nil
        do {
            if let store {
                let session = try store.load(visitId: visitId)
                return session
            }
            // No persistent store — return an empty placeholder session.
            return SessionCaptureV2(visitId: visitId)
        } catch {
            recallError = error
            throw error
        }
    }
}
