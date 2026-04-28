import Foundation
import AtlasContracts

// MARK: - AtlasRecommendationsSync
//
// Uploads a completed SessionCaptureV2 payload to the Atlas Recommendations backend.
//
// Design:
//   • Offline-first: the draft is fully built and persisted before any network call.
//   • Auth token is read from the Keychain (AtlasKeychainStore).
//   • Retry with exponential back-off, up to maxRetries attempts.
//   • No third-party networking library — URLSession only.
//
// Endpoint (POST multipart/form-data):
//   https://next.atlas-phm.uk/api/visits/import
//
// Request fields:
//   • session  — SessionCaptureV2 JSON (UTF-8 string field "session")
//   • photos   — one per photo file, field name "photos[]", filename = localFilename
//
// Response (JSON):
//   { "visitId": "<string>", "importedAt": "<ISO-8601>" }

// MARK: - Import response

struct AtlasImportResponse: Decodable {
    let visitId: String
    let importedAt: String
}

// MARK: - Sync errors

enum AtlasSyncError: LocalizedError {
    case noAuthToken
    case invalidResponse(Int)
    case networkFailure(Error)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .noAuthToken:
            return "No Atlas auth token stored. Sign in from Settings to enable sync."
        case .invalidResponse(let code):
            return "Atlas Recommendations returned HTTP \(code)."
        case .networkFailure(let e):
            return "Network error: \(e.localizedDescription)"
        case .decodingError(let e):
            return "Unexpected response from Atlas Recommendations: \(e.localizedDescription)"
        }
    }
}

// MARK: - AtlasRecommendationsSync

/// Uploads a completed capture session to Atlas Recommendations.
///
/// Usage:
///   ```swift
///   let response = try await AtlasRecommendationsSync.importVisit(
///       payload: captureV2,
///       photoURLs: localPhotoURLs
///   )
///   ```
enum AtlasRecommendationsSync {

    // MARK: Configuration

    static let importEndpoint = URL(string: "https://next.atlas-phm.uk/api/visits/import")!
    static let maxRetries     = 3
    static let baseBackoff    = 2.0   // seconds

    // MARK: - Import

    /// Uploads the capture payload to Atlas Recommendations.
    ///
    /// - Parameters:
    ///   - payload: The `SessionCaptureV2` contract payload.
    ///   - photoURLs: Local file URLs for evidence photos; uploaded as multipart parts.
    /// - Returns: The `AtlasImportResponse` from the backend.
    /// - Throws: `AtlasSyncError` on terminal failure.
    static func importVisit(
        payload: SessionCaptureV2,
        photoURLs: [URL] = []
    ) async throws -> AtlasImportResponse {
        guard let token = AtlasKeychainStore.loadAuthToken() else {
            throw AtlasSyncError.noAuthToken
        }

        let jsonData = try CaptureSessionExporter.encode(payload)

        var lastError: Error = AtlasSyncError.networkFailure(URLError(.timedOut))
        for attempt in 0..<maxRetries {
            if attempt > 0 {
                let backoff = baseBackoff * pow(2.0, Double(attempt - 1))
                try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
            }
            do {
                let response = try await performUpload(
                    jsonData: jsonData,
                    photoURLs: photoURLs,
                    token: token
                )
                return response
            } catch {
                lastError = error
                // Do not retry on auth errors or bad-request responses
                if case AtlasSyncError.noAuthToken = error { throw error }
                if case AtlasSyncError.invalidResponse(let code) = error,
                   (400..<500).contains(code) { throw error }
            }
        }
        throw lastError
    }

    // MARK: - Private: multipart upload

    private static func performUpload(
        jsonData: Data,
        photoURLs: [URL],
        token: String
    ) async throws -> AtlasImportResponse {
        let boundary = "AtlasBoundary\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"

        var body = Data()

        // Session JSON part
        body.append(multipartField(
            name: "session",
            data: jsonData,
            mimeType: "application/json",
            filename: "session.json",
            boundary: boundary
        ))

        // Photo parts
        for url in photoURLs {
            guard let photoData = try? Data(contentsOf: url) else { continue }
            body.append(multipartField(
                name: "photos[]",
                data: photoData,
                mimeType: "image/jpeg",
                filename: url.lastPathComponent,
                boundary: boundary
            ))
        }

        // Final boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: importEndpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 60

        let (data, urlResponse): (Data, URLResponse)
        do {
            (data, urlResponse) = try await URLSession.shared.data(for: request)
        } catch {
            throw AtlasSyncError.networkFailure(error)
        }

        guard let httpResponse = urlResponse as? HTTPURLResponse else {
            throw AtlasSyncError.networkFailure(URLError(.badServerResponse))
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AtlasSyncError.invalidResponse(httpResponse.statusCode)
        }

        do {
            let decoded = try JSONDecoder().decode(AtlasImportResponse.self, from: data)
            return decoded
        } catch {
            throw AtlasSyncError.decodingError(error)
        }
    }

    // MARK: - Private: multipart helper

    private static func multipartField(
        name: String,
        data: Data,
        mimeType: String,
        filename: String,
        boundary: String
    ) -> Data {
        var part = Data()
        part.append("--\(boundary)\r\n".data(using: .utf8)!)
        part.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        part.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        part.append(data)
        part.append("\r\n".data(using: .utf8)!)
        return part
    }
}
