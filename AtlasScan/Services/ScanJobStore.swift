import Foundation

// MARK: - ScanJobStore
//
// Persists ScanJob drafts to the app's local documents directory using JSON encoding.
// Each job is stored as a separate file: <jobID>.scanjob.json

final class ScanJobStore: ObservableObject {

    @Published private(set) var jobs: [ScanJob] = []

    private let fileManager = FileManager.default

    private var storeDirectory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("ScanJobs", isDirectory: true)
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

    func save(_ job: ScanJob) {
        let url = fileURL(for: job.id)
        do {
            let data = try encoder.encode(job)
            try data.write(to: url, options: .atomic)
            if let index = jobs.firstIndex(where: { $0.id == job.id }) {
                jobs[index] = job
            } else {
                jobs.append(job)
            }
            jobs.sort { $0.updatedAt > $1.updatedAt }
        } catch {
            print("[ScanJobStore] Failed to save job \(job.id): \(error)")
        }
    }

    func delete(_ job: ScanJob) {
        let url = fileURL(for: job.id)
        try? fileManager.removeItem(at: url)
        jobs.removeAll { $0.id == job.id }
    }

    func delete(jobID: UUID) {
        guard let job = jobs.first(where: { $0.id == jobID }) else { return }
        delete(job)
    }

    func job(for id: UUID) -> ScanJob? {
        jobs.first(where: { $0.id == id })
    }

    // MARK: Private helpers

    private func fileURL(for id: UUID) -> URL {
        storeDirectory.appendingPathComponent("\(id.uuidString).scanjob.json")
    }

    private func loadAll() {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: storeDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return }

        let jobFiles = urls.filter { $0.pathExtension == "json" }
        var loaded: [ScanJob] = []

        for url in jobFiles {
            do {
                let data = try Data(contentsOf: url)
                let job = try decoder.decode(ScanJob.self, from: data)
                loaded.append(job)
            } catch {
                print("[ScanJobStore] Failed to load \(url.lastPathComponent): \(error)")
            }
        }

        jobs = loaded.sorted { $0.updatedAt > $1.updatedAt }
    }
}
