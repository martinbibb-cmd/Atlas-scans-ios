import Foundation

// MARK: - VoiceNoteStore
//
// Manages voice note audio files in the app's local documents directory.
// Audio files: Documents/VoiceNotes/<id>.m4a
//
// VoiceNoteStore is the single owner of audio bytes on disk.

final class VoiceNoteStore {

    static let shared = VoiceNoteStore()

    // MARK: - Errors

    enum VoiceNoteStoreError: Error, LocalizedError {
        case directoryCreationFailed
        case fileNotFound(String)

        var errorDescription: String? {
            switch self {
            case .directoryCreationFailed:
                return "Failed to create VoiceNotes storage directory."
            case .fileNotFound(let name):
                return "Voice note file '\(name)' was not found."
            }
        }
    }

    // MARK: - Directory

    private let fileManager = FileManager.default

    var voiceNotesDirectory: URL {
        documentSubdirectory(named: "VoiceNotes")
    }

    private func documentSubdirectory(named name: String) -> URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent(name, isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - File URL helpers

    /// Returns the full URL for the given filename inside the VoiceNotes directory.
    func fileURL(for filename: String) -> URL {
        voiceNotesDirectory.appendingPathComponent(filename)
    }

    /// Generates a new filename for a voice note recording with the given UUID.
    func filename(for id: UUID) -> String {
        "\(id.uuidString).m4a"
    }

    // MARK: - Delete

    /// Deletes the audio file for the given filename.
    func delete(filename: String) {
        let url = fileURL(for: filename)
        try? fileManager.removeItem(at: url)
    }

    /// Deletes the audio file for a VoiceNote.
    func deleteFile(for note: VoiceNote) {
        delete(filename: note.localFilename)
    }

    // MARK: - Existence check

    /// Returns true if the audio file for the given filename exists on disk.
    func fileExists(filename: String) -> Bool {
        fileManager.fileExists(atPath: fileURL(for: filename).path)
    }
}
