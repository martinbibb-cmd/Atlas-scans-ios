import Foundation
import AtlasContracts

// MARK: - ScanToMindPayloadEncoder
//
// Encodes and decodes ScanToMindHandoffV1 for use in the /receive-scan URL.
//
// Wire format:
//   /receive-scan?payload=<percent-encoded JSON>
//
// Encoding steps:
//   1. JSONEncoder (sorted keys, compact — no pretty-print to minimise URL length).
//   2. Percent-encode the UTF-8 JSON string for safe embedding in a query parameter.
//      Characters allowed in a URL query string but ambiguous as parameter values
//      (+, &, =, ?) are percent-encoded to prevent mis-parsing on the Mind PWA side.
//
// Decoding steps:
//   1. Remove percent-encoding.
//   2. Decode as UTF-8 JSON via JSONDecoder.
//
// Rules:
//   • Pure functions: no side effects, no I/O.
//   • The encoder never emits base64; it produces a raw percent-encoded JSON string.
//   • Both functions are symmetric: decode(encode(x)) == x.

enum ScanToMindPayloadEncoder {

    // MARK: - Errors

    enum EncodingError: LocalizedError {
        case encodingFailed(Error)
        case invalidUTF8
        case invalidPercentEncoding
        case decodingFailed(Error)

        public var errorDescription: String? {
            switch self {
            case .encodingFailed(let e):
                return "Failed to encode handoff payload: \(e.localizedDescription)"
            case .invalidUTF8:
                return "JSON payload contains non-UTF-8 data."
            case .invalidPercentEncoding:
                return "Payload has invalid percent-encoding and could not be decoded."
            case .decodingFailed(let e):
                return "Failed to decode handoff payload: \(e.localizedDescription)"
            }
        }
    }

    // MARK: - Encode

    /// Encodes a ``ScanToMindHandoffV1`` as a percent-encoded JSON string.
    ///
    /// The result is safe to embed directly as the value of the `payload`
    /// query parameter in the Mind `/receive-scan` URL.
    ///
    /// - Parameter handoff: The handoff to encode.
    /// - Returns: A percent-encoded UTF-8 JSON string.
    /// - Throws: ``EncodingError`` on failure.
    static func encodeForURL(_ handoff: ScanToMindHandoffV1) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let jsonData: Data
        do {
            jsonData = try encoder.encode(handoff)
        } catch {
            throw EncodingError.encodingFailed(error)
        }

        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw EncodingError.invalidUTF8
        }

        // Start from urlQueryAllowed and additionally remove characters that are
        // valid in a query string but would corrupt a parameter value if left raw.
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=?")

        guard let encoded = jsonString.addingPercentEncoding(withAllowedCharacters: allowed) else {
            throw EncodingError.invalidUTF8
        }

        return encoded
    }

    // MARK: - Decode

    /// Decodes a ``ScanToMindHandoffV1`` from a percent-encoded JSON string.
    ///
    /// Symmetric with ``encodeForURL(_:)``.
    ///
    /// - Parameter payload: A percent-encoded UTF-8 JSON string produced by
    ///   ``encodeForURL(_:)``.
    /// - Returns: The decoded ``ScanToMindHandoffV1``.
    /// - Throws: ``EncodingError`` on failure.
    static func decodeFromURLPayload(_ payload: String) throws -> ScanToMindHandoffV1 {
        guard let jsonString = payload.removingPercentEncoding else {
            throw EncodingError.invalidPercentEncoding
        }
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw EncodingError.invalidUTF8
        }
        do {
            return try JSONDecoder().decode(ScanToMindHandoffV1.self, from: jsonData)
        } catch {
            throw EncodingError.decodingFailed(error)
        }
    }
}
