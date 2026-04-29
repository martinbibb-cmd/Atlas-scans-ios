import Foundation
import UIKit

// MARK: - PhotoStore
//
// Manages evidence photo files in the app's local documents directory.
// Photos:     Documents/Photos/<id>.jpg
// Thumbnails: Documents/Thumbnails/<id>_thumb.jpg
//
// PhotoStore is the single owner of image bytes on disk.

final class PhotoStore {

    static let shared = PhotoStore()

    // MARK: - Errors

    enum PhotoStoreError: Error, LocalizedError {
        case encodingFailed
        var errorDescription: String? {
            "Failed to save photo. Please ensure you have sufficient storage space and try again."
        }
    }

    // MARK: - Directories

    private let fileManager = FileManager.default

    var photosDirectory: URL {
        documentSubdirectory(named: "Photos")
    }

    var thumbnailsDirectory: URL {
        documentSubdirectory(named: "Thumbnails")
    }

    private func documentSubdirectory(named name: String) -> URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent(name, isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Save

    /// Saves a full-resolution image and generates a thumbnail.
    ///
    /// - Parameters:
    ///   - image: The UIImage to persist.
    ///   - id: A unique identifier used to name both files. Defaults to a new UUID.
    /// - Returns: A tuple of `(filename, thumbnailPath)` that should be persisted
    ///   alongside the photo record.
    @discardableResult
    func save(_ image: UIImage, id: UUID = UUID()) throws -> (filename: String, thumbnailPath: String?) {
        let filename = "\(id.uuidString).jpg"
        let fileURL = photosDirectory.appendingPathComponent(filename)
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            throw PhotoStoreError.encodingFailed
        }
        try data.write(to: fileURL, options: .atomic)
        let thumbnailPath = makeThumbnail(for: image, id: id)
        return (filename, thumbnailPath)
    }

    // MARK: - Load

    /// Loads the full-resolution image for the given filename, or nil if not found.
    func image(filename: String) -> UIImage? {
        let url = photosDirectory.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// Loads the thumbnail for the given path, or nil if not found.
    func thumbnail(path: String) -> UIImage? {
        let url = thumbnailsDirectory.appendingPathComponent(path)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    // MARK: - Delete

    /// Deletes the full-resolution image file for the given filename.
    func delete(filename: String) {
        let url = photosDirectory.appendingPathComponent(filename)
        try? fileManager.removeItem(at: url)
    }

    /// Deletes the thumbnail file for the given path, if non-nil.
    func deleteThumbnail(path: String?) {
        guard let path else { return }
        let url = thumbnailsDirectory.appendingPathComponent(path)
        try? fileManager.removeItem(at: url)
    }

    // MARK: - Private helpers

    private func makeThumbnail(for image: UIImage, id: UUID) -> String? {
        let side: CGFloat = 120
        let size = CGSize(width: side, height: side)
        let renderer = UIGraphicsImageRenderer(size: size)
        let thumb = renderer.image { _ in
            let scale = max(size.width / image.size.width, size.height / image.size.height)
            let scaledSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let origin = CGPoint(
                x: (size.width - scaledSize.width) / 2,
                y: (size.height - scaledSize.height) / 2
            )
            image.draw(in: CGRect(origin: origin, size: scaledSize))
        }
        let path = "\(id.uuidString)_thumb.jpg"
        let url = thumbnailsDirectory.appendingPathComponent(path)
        guard let data = thumb.jpegData(compressionQuality: 0.7) else { return nil }
        try? data.write(to: url, options: .atomic)
        return path
    }
}

