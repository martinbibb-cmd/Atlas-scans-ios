import Foundation
import AtlasContracts

// MARK: - AtlasScanVisitStore
//
// Single active-visit lifecycle store.
//
// Design:
//   • Manages exactly one active visit at a time.
//   • Persists to Documents/active_visit.json.
//   • createVisit also creates a linked CaptureSessionDraft.
//   • clearActiveVisit removes the lifecycle record but preserves
//     capture evidence in CaptureSessionPersistence.
//   • All mutations publish on the main actor so SwiftUI observes correctly.

@MainActor
final class AtlasScanVisitStore: ObservableObject {

    // MARK: Singleton

    static let shared = AtlasScanVisitStore()

    // MARK: Test factory

    /// Creates an isolated instance backed by a temporary directory.
    /// Use only in test targets — never in production code.
    static func makeTestInstance() -> AtlasScanVisitStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AtlasScanVisitTest-\(UUID().uuidString)", isDirectory: true)
        return AtlasScanVisitStore(customDirectory: dir)
    }

    // MARK: Published state

    @Published private(set) var activeVisit: AtlasScanVisit?

    // MARK: Private

    private let fileManager = FileManager.default
    private let customDirectory: URL?

    private var storeURL: URL {
        let base: URL
        if let custom = customDirectory {
            base = custom
        } else {
            base = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        }
        try? fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("active_visit.json")
    }

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    // MARK: Init

    private init(customDirectory: URL? = nil) {
        self.customDirectory = customDirectory
        self.activeVisit = Self.readFromDisk(customDirectory: customDirectory)
    }

    // MARK: - Public API

    /// Creates a new visit with a linked CaptureSessionDraft and sets it as the active visit.
    ///
    /// - Parameters:
    ///   - visitNumber: Engineer-assigned visit / job reference.
    ///   - brandId:     Optional brand or client identifier.
    /// - Returns: The newly created visit.
    @discardableResult
    func createVisit(visitNumber: String?, brandId: String?) -> AtlasScanVisit {
        let ref = visitNumber?.trimmingCharacters(in: .whitespaces) ?? ""

        // Create and persist the capture session draft.
        var draft = CaptureSessionStore.newSession(visitReference: ref)
        CaptureSessionPersistence.shared.save(draft)

        // Create the lifecycle visit linked to the draft.
        var visit = AtlasScanVisit(visitNumber: visitNumber, brandId: brandId)
        visit.captureSessionId = draft.id
        saveActiveVisit(visit)
        return visit
    }

    /// Returns the current active visit (same as `activeVisit` property).
    func loadActiveVisit() -> AtlasScanVisit? {
        activeVisit
    }

    /// Saves a visit as the active visit, persisting to disk.
    func saveActiveVisit(_ visit: AtlasScanVisit) {
        var v = visit
        v.updatedAt = Date()
        activeVisit = v
        persist(v)
    }

    /// Clears the active visit.
    ///
    /// Does not delete the linked CaptureSessionDraft — evidence is preserved.
    func clearActiveVisit() {
        activeVisit = nil
        try? fileManager.removeItem(at: storeURL)
    }

    /// Updates the status of the active visit.
    func updateStatus(_ status: AtlasVisitStatusV1) {
        guard var visit = activeVisit else { return }
        visit.status = status
        if status == .complete {
            visit.completedAt = Date()
        }
        saveActiveVisit(visit)
    }

    /// Updates the readiness flags of the active visit.
    func updateReadiness(_ readiness: AtlasVisitReadinessV1) {
        guard var visit = activeVisit else { return }
        visit.readiness = readiness
        saveActiveVisit(visit)
    }

    // MARK: - Private helpers

    private func persist(_ visit: AtlasScanVisit) {
        guard let data = try? encoder.encode(visit) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    private static func readFromDisk(customDirectory: URL?) -> AtlasScanVisit? {
        let base: URL
        if let custom = customDirectory {
            base = custom
        } else {
            base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        }
        let url = base.appendingPathComponent("active_visit.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(AtlasScanVisit.self, from: data)
    }
}
