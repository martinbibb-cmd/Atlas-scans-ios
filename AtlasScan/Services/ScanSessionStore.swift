import Foundation

// MARK: - ScanSessionStore
//
// Persists PropertyScanSession records to the app's local documents directory.
// Each session is stored as a separate file: <sessionID>.session.json
//
// Offline-first: all writes go to local storage immediately.
// Atlas sync is handled separately by AtlasSync.

final class ScanSessionStore: ObservableObject {

    @Published private(set) var sessions: [PropertyScanSession] = []

    private let fileManager = FileManager.default

    private var storeDirectory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("ScanSessions", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
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

    // MARK: Lifecycle

    init() {
        loadAll()
    }

    // MARK: Public API

    func save(_ session: PropertyScanSession) {
        var s = session
        s.touch()
        let url = fileURL(for: s.id)
        do {
            let data = try encoder.encode(s)
            try data.write(to: url, options: .atomic)
            if let index = sessions.firstIndex(where: { $0.id == s.id }) {
                sessions[index] = s
            } else {
                sessions.append(s)
            }
            sessions.sort { $0.updatedAt > $1.updatedAt }
        } catch {
            print("[ScanSessionStore] Failed to save session \(s.id): \(error)")
        }
    }

    func delete(_ session: PropertyScanSession) {
        let url = fileURL(for: session.id)
        try? fileManager.removeItem(at: url)
        sessions.removeAll { $0.id == session.id }
    }

    func delete(sessionID: UUID) {
        guard let session = sessions.first(where: { $0.id == sessionID }) else { return }
        delete(session)
    }

    func session(for id: UUID) -> PropertyScanSession? {
        sessions.first { $0.id == id }
    }

    // MARK: Private helpers

    private func fileURL(for id: UUID) -> URL {
        storeDirectory.appendingPathComponent("\(id.uuidString).session.json")
    }

    private func loadAll() {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: storeDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return }

        let sessionFiles = urls.filter { $0.pathExtension == "json" }
        var loaded: [PropertyScanSession] = []

        for url in sessionFiles {
            do {
                let data = try Data(contentsOf: url)
                let session = try decoder.decode(PropertyScanSession.self, from: data)
                loaded.append(session)
            } catch {
                print("[ScanSessionStore] Failed to load \(url.lastPathComponent): \(error)")
            }
        }

        sessions = loaded.sorted { $0.updatedAt > $1.updatedAt }
    }
}
