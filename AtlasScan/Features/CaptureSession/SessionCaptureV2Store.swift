import Foundation
import AtlasContracts

// MARK: - SessionCaptureV2Store
//
// Local-first persistence for a visit's SessionCaptureV2 payload.
//
// Each capture is stored at:
//   Documents/captures/{visitId}/session_capture_v2.json
//
// Design:
//   • One file per visit — overwrites on each save.
//   • All writes are immediate (atomic) — no sync dependency.
//   • The store has no in-memory cache; callers load on demand.

final class SessionCaptureV2Store {

    // MARK: Singleton

    static let shared = SessionCaptureV2Store()

    // MARK: Test factory

    /// Creates an isolated instance backed by a temporary directory.
    /// Use only in test targets — never in production code.
    static func makeTestInstance() -> SessionCaptureV2Store {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionCaptureV2StoreTest-\(UUID().uuidString)", isDirectory: true)
        return SessionCaptureV2Store(customDirectory: dir)
    }

    // MARK: Private

    private let fileManager = FileManager.default

    /// When non-nil, overrides the default Documents-based root directory.
    private let customDirectory: URL?

    private var capturesRoot: URL {
        let base: URL
        if let custom = customDirectory {
            base = custom
        } else {
            base = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        }
        return base.appendingPathComponent("captures", isDirectory: true)
    }

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private let decoder: JSONDecoder = JSONDecoder()

    private init(customDirectory: URL? = nil) {
        self.customDirectory = customDirectory
    }

    // MARK: - Public API

    /// Saves a ``SessionCaptureV2`` payload for the given visit.
    ///
    /// Creates `Documents/captures/{visitId}/` if needed, then writes
    /// `session_capture_v2.json` atomically.
    func saveCapture(_ capture: SessionCaptureV2, for visitId: String) {
        let dir = captureDirectory(for: visitId)
        do {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try encoder.encode(capture)
            try data.write(to: captureFileURL(for: visitId), options: .atomic)
        } catch {
            print("[SessionCaptureV2Store] Failed to save capture for \(visitId): \(error)")
        }
    }

    /// Loads the persisted ``SessionCaptureV2`` for the given visit, or nil
    /// if no capture has been saved yet.
    func loadCapture(for visitId: String) -> SessionCaptureV2? {
        let url = captureFileURL(for: visitId)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(SessionCaptureV2.self, from: data)
    }

    /// Removes the persisted capture directory for the given visit.
    func clearCapture(for visitId: String) {
        let dir = captureDirectory(for: visitId)
        try? fileManager.removeItem(at: dir)
    }

    // MARK: - Private helpers

    private func captureDirectory(for visitId: String) -> URL {
        capturesRoot.appendingPathComponent(visitId, isDirectory: true)
    }

    private func captureFileURL(for visitId: String) -> URL {
        captureDirectory(for: visitId)
            .appendingPathComponent("session_capture_v2.json")
    }
}
