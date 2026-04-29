import Foundation
import AtlasContracts

// MARK: - AtlasMindClient
//
// Sends a completed `AtlasPropertyV1` handoff payload directly to Atlas Mind.
//
// Design:
//   • The engineer never sees raw JSON — the submission is invisible to the UI.
//   • Auth token is read from the Keychain (AtlasKeychainStore).
//   • Retry with exponential back-off, up to maxRetries attempts.
//   • No third-party networking library — URLSession only.
//
// Endpoint (POST application/json):
//   https://next.atlas-phm.uk/api/property/import
//
// Request body: AtlasPropertyV1 encoded as JSON (UTF-8)
//
// Response (JSON):
//   { "propertyId": "<string>", "importedAt": "<ISO-8601>" }

// MARK: - Import response

struct AtlasMindImportResponse: Decodable {
    let propertyId: String
    let importedAt: String
}

// MARK: - Client errors

enum AtlasMindClientError: LocalizedError {
    case noAuthToken
    case encodingFailure(Error)
    case invalidResponse(Int)
    case networkFailure(Error)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .noAuthToken:
            return "No Atlas auth token stored. Sign in from Settings to enable sync."
        case .encodingFailure(let e):
            return "Failed to encode handoff payload: \(e.localizedDescription)"
        case .invalidResponse(let code):
            return "Atlas Mind returned HTTP \(code)."
        case .networkFailure(let e):
            return "Network error: \(e.localizedDescription)"
        case .decodingError(let e):
            return "Unexpected response from Atlas Mind: \(e.localizedDescription)"
        }
    }
}

// MARK: - AtlasMindClient

/// Submits a completed property handoff directly to Atlas Mind.
///
/// Usage:
///   ```swift
///   let response = try await AtlasMindClient.submitHandoff(session: session)
///   ```
enum AtlasMindClient {

    // MARK: Configuration

    // swiftlint:disable:next force_unwrapping
    static let importEndpoint: URL = {
        guard let url = URL(string: "https://next.atlas-phm.uk/api/property/import") else {
            preconditionFailure("AtlasMindClient: invalid import endpoint URL — this is a compile-time constant and must be valid.")
        }
        return url
    }()
    static let maxRetries     = 3
    static let baseBackoff    = 2.0   // seconds

    // MARK: - Submit

    /// Maps `session` to `AtlasPropertyV1` and POSTs it directly to Atlas Mind.
    ///
    /// - Parameter session: The completed `PropertyScanSession` to hand off.
    /// - Returns: The `AtlasMindImportResponse` from the backend.
    /// - Throws: `AtlasMindClientError` on terminal failure.
    static func submitHandoff(session: PropertyScanSession) async throws -> AtlasMindImportResponse {
        guard let token = AtlasKeychainStore.loadAuthToken() else {
            throw AtlasMindClientError.noAuthToken
        }

        let property = VisitSessionMapper.toAtlasPropertyV1(session)
        let jsonData: Data
        do {
            jsonData = try VisitSessionMapper.encode(property)
        } catch {
            throw AtlasMindClientError.encodingFailure(error)
        }

        var lastError: Error = AtlasMindClientError.networkFailure(URLError(.timedOut))
        for attempt in 0..<maxRetries {
            if attempt > 0 {
                let backoff = baseBackoff * pow(2.0, Double(attempt - 1))
                try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
            }
            do {
                return try await performUpload(jsonData: jsonData, token: token)
            } catch {
                lastError = error
                // Do not retry on auth errors or 4xx client errors.
                if case AtlasMindClientError.noAuthToken = error { throw error }
                if case AtlasMindClientError.invalidResponse(let code) = error,
                   (400..<500).contains(code) { throw error }
            }
        }
        throw lastError
    }

    // MARK: - Private: upload

    private static func performUpload(
        jsonData: Data,
        token: String
    ) async throws -> AtlasMindImportResponse {
        var request = URLRequest(url: importEndpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        request.timeoutInterval = 60

        let (data, urlResponse): (Data, URLResponse)
        do {
            (data, urlResponse) = try await URLSession.shared.data(for: request)
        } catch {
            throw AtlasMindClientError.networkFailure(error)
        }

        guard let httpResponse = urlResponse as? HTTPURLResponse else {
            throw AtlasMindClientError.networkFailure(URLError(.badServerResponse))
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AtlasMindClientError.invalidResponse(httpResponse.statusCode)
        }

        do {
            return try JSONDecoder().decode(AtlasMindImportResponse.self, from: data)
        } catch {
            throw AtlasMindClientError.decodingError(error)
        }
    }
}
