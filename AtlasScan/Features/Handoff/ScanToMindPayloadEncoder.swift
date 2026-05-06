// ScanToMindPayloadEncoder — encodes/decodes ScanToMindHandoffV1 for URL transport.

import Foundation
import AtlasContracts

enum ScanToMindPayloadEncoderError: Error, LocalizedError {
    case jsonStringConversionFailed
    case percentEncodingFailed
    case percentDecodingFailed
    case jsonDataConversionFailed

    var errorDescription: String? {
        switch self {
        case .jsonStringConversionFailed:  return "Failed to convert handoff JSON to a UTF-8 string."
        case .percentEncodingFailed:       return "Failed to percent-encode the handoff payload."
        case .percentDecodingFailed:       return "Failed to percent-decode the URL payload."
        case .jsonDataConversionFailed:    return "Failed to convert decoded payload to Data."
        }
    }
}

enum ScanToMindPayloadEncoder {

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Encodes a ``ScanToMindHandoffV1`` to a percent-encoded JSON string
    /// suitable for embedding in a URL query parameter.
    ///
    /// Uses `urlQueryAllowed` minus `+`, `&`, `=`, and `?` so the
    /// payload survives query-string parsing without corruption.
    static func encodeForURL(_ handoff: ScanToMindHandoffV1) throws -> String {
        let data = try encoder.encode(handoff)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw ScanToMindPayloadEncoderError.jsonStringConversionFailed
        }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=?")
        guard let encoded = jsonString.addingPercentEncoding(withAllowedCharacters: allowed) else {
            throw ScanToMindPayloadEncoderError.percentEncodingFailed
        }
        return encoded
    }

    /// Decodes a percent-encoded JSON string (produced by ``encodeForURL(_:)``)
    /// back into a ``ScanToMindHandoffV1``.
    static func decodeFromURLPayload(_ encoded: String) throws -> ScanToMindHandoffV1 {
        guard let jsonString = encoded.removingPercentEncoding else {
            throw ScanToMindPayloadEncoderError.percentDecodingFailed
        }
        guard let data = jsonString.data(using: .utf8) else {
            throw ScanToMindPayloadEncoderError.jsonDataConversionFailed
        }
        return try decoder.decode(ScanToMindHandoffV1.self, from: data)
    }
}
