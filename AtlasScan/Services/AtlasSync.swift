import Foundation

// MARK: - AtlasSync
//
// Manages the upload of scan sessions and photos to the Atlas backend.
//
// Design principles:
//   - Offline-first: local saves are always completed before any upload attempt.
//   - Per-item state: each photo and session carries its own sync state.
//   - Async upload: uploads happen in the background; the queue is retried on failure.
//   - No dependency on AtlasContracts internals — the sync layer maps models to
//     the shared export contract types for transmission.
//
// Current implementation: stub/offline-first skeleton.
// Real HTTP transport is wired in when an Atlas API endpoint is available.

// MARK: - AtlasSyncDelegate

protocol AtlasSyncDelegate: AnyObject {
    /// Called when a photo's sync state changes.
    func atlasSync(_ sync: AtlasSync, didUpdatePhoto photoID: UUID, syncState: PhotoSyncState)
    /// Called when a session's sync state changes.
    func atlasSync(_ sync: AtlasSync, didUpdateSession sessionID: UUID, syncState: SessionSyncState)
    /// Called when an upload fails with a recoverable error.
    func atlasSync(_ sync: AtlasSync, uploadFailedFor photoID: UUID, error: Error)
}

// MARK: - AtlasSyncConfiguration

struct AtlasSyncConfiguration {
    /// Base URL of the Atlas API. Nil means Atlas sync is disabled.
    var apiBaseURL: URL?

    /// Maximum number of retry attempts before marking an item as failed.
    var maxRetries: Int = 3

    /// Initial backoff interval in seconds for retry scheduling.
    var initialBackoffSeconds: TimeInterval = 5.0

    /// Whether Atlas sync is enabled for this configuration.
    var isEnabled: Bool { apiBaseURL != nil }
}

// MARK: - AtlasSyncUploadItem

/// A single item in the upload queue.
struct AtlasSyncUploadItem: Identifiable {

    enum ItemKind {
        case photo(TaggedPhoto)
        case sessionMetadata(PropertyScanSession)
    }

    var id: UUID = UUID()
    var kind: ItemKind
    var retryCount: Int = 0
    var lastAttempt: Date?

    var photoID: UUID? {
        if case .photo(let p) = kind { return p.id }
        return nil
    }

    var sessionID: UUID? {
        if case .sessionMetadata(let s) = kind { return s.id }
        return nil
    }
}

// MARK: - AtlasSync

/// Manages the upload queue and sync lifecycle for a scan session.
///
/// Usage:
///   1. Call `enqueuePhoto(_:)` to mark a photo as queued for upload.
///   2. Call `enqueueSession(_:)` to mark a session for metadata upload.
///   3. Call `processQueue()` to start processing pending uploads.
///   4. Call `cancelAll()` to stop all in-flight uploads.
///
/// All state transitions are reported via `AtlasSyncDelegate`.
@MainActor
final class AtlasSync: ObservableObject {

    // MARK: Published state

    @Published private(set) var uploadQueue: [AtlasSyncUploadItem] = []
    @Published private(set) var isUploading: Bool = false

    // MARK: Configuration

    private let configuration: AtlasSyncConfiguration

    weak var delegate: AtlasSyncDelegate?

    // MARK: Internal state

    private var activeTasks: [UUID: Task<Void, Never>] = [:]

    // MARK: Init

    init(configuration: AtlasSyncConfiguration = AtlasSyncConfiguration()) {
        self.configuration = configuration
    }

    // MARK: Queue management

    /// Enqueues a photo for upload to Atlas.
    /// No-op when Atlas sync is not configured.
    func enqueuePhoto(_ photo: TaggedPhoto) {
        guard configuration.isEnabled else { return }
        guard photo.syncState.canQueue else { return }
        let item = AtlasSyncUploadItem(kind: .photo(photo))
        uploadQueue.append(item)
    }

    /// Enqueues a batch of photos for upload to Atlas.
    /// Only photos with `syncState.canQueue == true` are added.
    func enqueuePhotos(_ photos: [TaggedPhoto]) {
        photos.forEach { enqueuePhoto($0) }
    }

    /// Enqueues session metadata for upload to Atlas.
    func enqueueSession(_ session: PropertyScanSession) {
        guard configuration.isEnabled else { return }
        let item = AtlasSyncUploadItem(kind: .sessionMetadata(session))
        uploadQueue.append(item)
    }

    /// Removes all items from the upload queue and cancels any in-flight tasks.
    func cancelAll() {
        activeTasks.values.forEach { $0.cancel() }
        activeTasks.removeAll()
        uploadQueue.removeAll()
        isUploading = false
    }

    // MARK: Upload processing

    /// Starts processing the upload queue.
    /// Items are processed concurrently up to the system's limit.
    func processQueue() {
        guard configuration.isEnabled else { return }
        guard !uploadQueue.isEmpty else { return }
        isUploading = true

        let pending = uploadQueue.filter { item in
            activeTasks[item.id] == nil
        }

        for item in pending {
            let task = Task { [weak self] in
                await self?.upload(item)
            }
            activeTasks[item.id] = task
        }
    }

    // MARK: Private: upload an item

    private func upload(_ item: AtlasSyncUploadItem) async {
        switch item.kind {
        case .photo(let photo):
            await uploadPhoto(photo, item: item)
        case .sessionMetadata(let session):
            await uploadSessionMetadata(session, item: item)
        }
    }

    private func uploadPhoto(_ photo: TaggedPhoto, item: AtlasSyncUploadItem) async {
        guard let baseURL = configuration.apiBaseURL else { return }

        // Update state to uploading
        updatePhotoState(photoID: photo.id, syncState: .uploading)

        do {
            let remoteID = try await performPhotoUpload(photo, baseURL: baseURL)
            // Success — mark as uploaded and store the remote asset ID
            updatePhotoState(photoID: photo.id, syncState: .uploaded, remoteAssetID: remoteID)
            removeFromQueue(itemID: item.id)
        } catch {
            let retries = item.retryCount
            if retries < configuration.maxRetries {
                // Reschedule with backoff
                let backoff = configuration.initialBackoffSeconds * pow(2.0, Double(retries))
                updateQueueItem(itemID: item.id, incrementRetry: true)
                try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                await uploadPhoto(photo, item: itemWithRetry(item))
            } else {
                // Exhausted retries — mark as failed
                updatePhotoState(photoID: photo.id, syncState: .failed)
                removeFromQueue(itemID: item.id)
                delegate?.atlasSync(self, uploadFailedFor: photo.id, error: error)
            }
        }

        activeTasks.removeValue(forKey: item.id)
        updateUploadingState()
    }

    private func uploadSessionMetadata(_ session: PropertyScanSession, item: AtlasSyncUploadItem) async {
        guard let baseURL = configuration.apiBaseURL else { return }

        do {
            try await performSessionMetadataUpload(session, baseURL: baseURL)
            delegate?.atlasSync(self, didUpdateSession: session.id, syncState: .uploaded)
            removeFromQueue(itemID: item.id)
        } catch {
            let retries = item.retryCount
            if retries < configuration.maxRetries {
                let backoff = configuration.initialBackoffSeconds * pow(2.0, Double(retries))
                updateQueueItem(itemID: item.id, incrementRetry: true)
                try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                await uploadSessionMetadata(session, item: itemWithRetry(item))
            } else {
                delegate?.atlasSync(self, didUpdateSession: session.id, syncState: .failed)
                removeFromQueue(itemID: item.id)
            }
        }

        activeTasks.removeValue(forKey: item.id)
        updateUploadingState()
    }

    // MARK: Private: transport stubs

    /// Uploads a photo file and its metadata to Atlas.
    /// Returns the remote asset identifier assigned by Atlas.
    private func performPhotoUpload(_ photo: TaggedPhoto, baseURL: URL) async throws -> String {
        // Transport stub — replace with real URLSession multipart upload when API is available.
        // For now: simulate a network delay and return a synthetic remote ID.
        try await Task.sleep(nanoseconds: 100_000_000)  // 0.1 s stub
        return "remote_\(photo.id.uuidString)"
    }

    /// Uploads session metadata to Atlas.
    private func performSessionMetadataUpload(_ session: PropertyScanSession, baseURL: URL) async throws {
        // Transport stub — replace with real URLSession JSON upload when API is available.
        try await Task.sleep(nanoseconds: 50_000_000)   // 0.05 s stub
    }

    // MARK: Private: queue / state helpers

    private func updatePhotoState(photoID: UUID, syncState: PhotoSyncState, remoteAssetID: String? = nil) {
        delegate?.atlasSync(self, didUpdatePhoto: photoID, syncState: syncState)
    }

    private func removeFromQueue(itemID: UUID) {
        uploadQueue.removeAll { $0.id == itemID }
    }

    private func updateQueueItem(itemID: UUID, incrementRetry: Bool) {
        guard let index = uploadQueue.firstIndex(where: { $0.id == itemID }) else { return }
        if incrementRetry {
            uploadQueue[index].retryCount += 1
        }
        uploadQueue[index].lastAttempt = Date()
    }

    private func itemWithRetry(_ item: AtlasSyncUploadItem) -> AtlasSyncUploadItem {
        var copy = item
        copy.retryCount += 1
        copy.lastAttempt = Date()
        return copy
    }

    private func updateUploadingState() {
        isUploading = !uploadQueue.isEmpty
    }
}

// MARK: - AtlasSyncUploadItem.ItemKind helpers

extension AtlasSyncUploadItem.ItemKind: CustomStringConvertible {
    var description: String {
        switch self {
        case .photo(let p): return "photo(\(p.id.uuidString))"
        case .sessionMetadata(let s): return "session(\(s.id.uuidString))"
        }
    }
}
