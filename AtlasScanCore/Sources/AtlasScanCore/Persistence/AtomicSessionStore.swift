/// AtomicSessionStore — Persists `SessionCaptureV2` as JSON with atomic file writes.
///
/// All sessions are stored under:
///   <Documents>/captures/<visitId>/session.json
///
/// USDZ meshes are placed alongside:
///   <Documents>/captures/<visitId>/usdz/

import Foundation

public final class AtomicSessionStore: Sendable {

    public static let shared = AtomicSessionStore()

    // MARK: - Init

    public init() {}

    // MARK: - Public API

    public func save(_ session: SessionCaptureV2) throws {
        let dir = captureDirectory(for: session.visitId)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = sessionFileURL(for: session.visitId)
        let tmp = url.deletingLastPathComponent()
            .appendingPathComponent(".\(session.visitId.uuidString).tmp")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(session)
        try data.write(to: tmp, options: .atomic)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
    }

    public func load(visitId: UUID) throws -> SessionCaptureV2 {
        let url = sessionFileURL(for: visitId)
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SessionCaptureV2.self, from: data)
    }

    public func delete(visitId: UUID) throws {
        let dir = captureDirectory(for: visitId)
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
    }

    public func allVisitIds() throws -> [UUID] {
        let root = capturesRoot()
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: root.path)
            .compactMap { UUID(uuidString: $0) }
    }

    /// Returns (or creates) the directory for placing USDZ assets for a visit.
    public func usdzDirectory(for visitId: UUID) throws -> URL {
        let dir = captureDirectory(for: visitId).appendingPathComponent("usdz", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Private helpers

    private func capturesRoot() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("captures", isDirectory: true)
    }

    private func captureDirectory(for visitId: UUID) -> URL {
        capturesRoot().appendingPathComponent(visitId.uuidString, isDirectory: true)
    }

    private func sessionFileURL(for visitId: UUID) -> URL {
        captureDirectory(for: visitId).appendingPathComponent("session.json")
    }
}
