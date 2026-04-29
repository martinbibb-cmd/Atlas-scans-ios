import Foundation

// MARK: - CaptureSessionPersistence
//
// Local-first persistence for CaptureSessionDraft.
//
// Each session draft is stored as a separate file:
//   Documents/CaptureSessions/<uuid>.capture.json
//
// All writes are immediate — no sync dependency.
// The "last incomplete session" is the most-recently-updated non-exported draft.

final class CaptureSessionPersistence {

    // MARK: Singleton

    static let shared = CaptureSessionPersistence()

    // MARK: Test factory

    /// Creates an isolated instance backed by a temporary directory.
    /// Use only in test targets — never in production code.
    static func makeTestInstance() -> CaptureSessionPersistence {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AtlasScanTest-\(UUID().uuidString)", isDirectory: true)
        return CaptureSessionPersistence(customDirectory: dir)
    }

    // MARK: Private

    private let fileManager = FileManager.default

    /// When non-nil, overrides the default Documents-based directory.
    private let customDirectory: URL?

    private var storeDirectory: URL {
        let base: URL
        if let custom = customDirectory {
            base = custom
        } else {
            base = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("CaptureSessions", isDirectory: true)
        }
        try? fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private init(customDirectory: URL? = nil) {
        self.customDirectory = customDirectory
    }

    // MARK: - Public API

    /// Saves a draft session to local storage.
    func save(_ draft: CaptureSessionDraft) {
        var d = draft
        d.touch()
        let url = fileURL(for: d.id)
        do {
            let data = try encoder.encode(d)
            try data.write(to: url, options: .atomic)
        } catch {
            print("[CaptureSessionPersistence] Failed to save \(d.id): \(error)")
        }
    }

    /// Loads a specific draft session by ID.
    func load(id: UUID) -> CaptureSessionDraft? {
        let url = fileURL(for: id)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(CaptureSessionDraft.self, from: data)
    }

    /// Loads all stored draft sessions, sorted newest-first.
    func loadAll() -> [CaptureSessionDraft] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: storeDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> CaptureSessionDraft? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(CaptureSessionDraft.self, from: data)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Returns the most-recently-updated draft that has not yet been exported.
    func lastIncompleteDraft() -> CaptureSessionDraft? {
        loadAll().first { $0.exportState != .exported }
    }

    /// Deletes a draft session from local storage.
    func delete(id: UUID) {
        let url = fileURL(for: id)
        try? fileManager.removeItem(at: url)
    }

    /// Deletes all persisted drafts under the store directory.
    /// Intended for use in test teardown — not for production use.
    func deleteAll() {
        try? fileManager.removeItem(at: storeDirectory)
    }

    // MARK: - Private helpers

    private func fileURL(for id: UUID) -> URL {
        storeDirectory.appendingPathComponent("\(id.uuidString).capture.json")
    }
}
