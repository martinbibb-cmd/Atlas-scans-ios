/// ScanSessionCoordinator — Drives the live scan session lifecycle.

import Foundation
import SwiftUI
import AtlasScanCore

@MainActor
public final class ScanSessionCoordinator: ObservableObject {
    @Published public var session: SessionCaptureV2
    @Published public var showHandoff = false
    @Published public var isSaving = false
    @Published public var saveError: Error?

    private let store: AtomicSessionStore

    public init(
        visitId: UUID = UUID(),
        store: AtomicSessionStore = .shared
    ) {
        self.session = SessionCaptureV2(visitId: visitId)
        self.store = store
    }

    // MARK: - Room management

    public func addRoom(_ room: RoomCaptureV2) {
        session.addRoom(room)
    }

    public func emitQAFlag(_ flag: QAFlagV1) {
        session.emitQAFlag(flag)
    }

    // MARK: - Handoff

    public func handOffToMind() {
        showHandoff = true
    }

    // MARK: - Persistence

    public func saveSession() async {
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        do {
            try store.save(session)
        } catch {
            saveError = error
        }
    }

    public func loadRecalledSession(_ recalled: SessionCaptureV2) {
        session = recalled
    }
}
