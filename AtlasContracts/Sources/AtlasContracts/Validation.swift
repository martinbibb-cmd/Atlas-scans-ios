import Foundation

// MARK: - Validation result types

/// Result of validating a scan bundle against the contract.
public enum ScanValidationResult: Sendable {
    /// The bundle is structurally valid and has been decoded.
    case success(ScanBundleV1)
    /// The bundle is invalid; `errors` describes each problem found.
    case failure([String])

    /// `true` when the bundle passed validation.
    public var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    /// The list of error messages when validation failed; empty on success.
    public var errors: [String] {
        if case .failure(let e) = self { return e }
        return []
    }

    /// The decoded bundle when validation succeeded; `nil` on failure.
    public var bundle: ScanBundleV1? {
        if case .success(let b) = self { return b }
        return nil
    }
}

// MARK: - Public entry point

/// Validates raw JSON `data` against the ScanBundleV1 contract.
///
/// 1. Confirms the input is a non-null JSON object.
/// 2. Checks `version` is present and supported.
/// 3. Validates required structural fields for the detected version.
/// 4. Decodes the bundle if all checks pass.
///
/// - Parameter data: Raw UTF-8 JSON data.
/// - Returns: `.success(bundle)` if valid, `.failure([errors])` otherwise.
public func validateScanBundle(_ data: Data) -> ScanValidationResult {
    guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return .failure(["Input is not a valid JSON object."])
    }

    guard let version = raw["version"] as? String, !version.isEmpty else {
        return .failure(["version: missing, empty, or not a string."])
    }

    guard isSupportedVersion(version) else {
        let supported = supportedScanBundleVersions.joined(separator: ", ")
        return .failure(["version: '\(version)' is not supported. Supported versions: \(supported)."])
    }

    var errors: [String] = []

    if (raw["bundleId"] as? String)?.isEmpty != false {
        errors.append("bundleId: must be a non-empty string.")
    }

    if let rooms = raw["rooms"] as? [[String: Any]] {
        for (i, room) in rooms.enumerated() {
            errors.append(contentsOf: validateRoom(room, path: "rooms[\(i)]"))
        }
    } else {
        errors.append("rooms: must be an array.")
    }

    if (raw["anchors"] as? [[String: Any]]) == nil {
        errors.append("anchors: must be an array.")
    }

    if (raw["qaFlags"] as? [[String: Any]]) == nil {
        errors.append("qaFlags: must be an array.")
    }

    if let meta = raw["meta"] as? [String: Any] {
        errors.append(contentsOf: validateMeta(meta, path: "meta"))
    } else {
        errors.append("meta: must be an object.")
    }

    guard errors.isEmpty else {
        return .failure(errors)
    }

    do {
        let bundle = try JSONDecoder().decode(ScanBundleV1.self, from: data)
        return .success(bundle)
    } catch {
        return .failure(["Failed to decode bundle: \(error.localizedDescription)"])
    }
}

// MARK: - Internal field validators

private func validateRoom(_ room: [String: Any], path: String) -> [String] {
    var errors: [String] = []

    if (room["id"] as? String) == nil {
        errors.append("\(path).id: must be a string.")
    }
    if (room["label"] as? String) == nil {
        errors.append("\(path).label: must be a string.")
    }
    if room["floorIndex"] == nil {
        errors.append("\(path).floorIndex: must be an integer.")
    }
    if room["areaM2"] == nil {
        errors.append("\(path).areaM2: must be a number.")
    }
    if room["heightM"] == nil {
        errors.append("\(path).heightM: must be a number.")
    }
    if (room["polygon"] as? [[String: Any]]) == nil {
        errors.append("\(path).polygon: must be an array.")
    }
    if (room["walls"] as? [[String: Any]]) == nil {
        errors.append("\(path).walls: must be an array.")
    }
    if (room["detectedObjects"] as? [[String: Any]]) == nil {
        errors.append("\(path).detectedObjects: must be an array.")
    }
    // Derive valid values from ScanConfidenceBand to avoid drift with the type definition.
    let validConfidence = ScanConfidenceBand.allCases.map(\.rawValue)
    if let conf = room["confidence"] as? String {
        if !validConfidence.contains(conf) {
            errors.append("\(path).confidence: must be one of: \(validConfidence.joined(separator: ", ")).")
        }
    } else {
        errors.append("\(path).confidence: must be a string.")
    }

    return errors
}

private func validateMeta(_ meta: [String: Any], path: String) -> [String] {
    var errors: [String] = []

    if (meta["capturedAt"] as? String) == nil {
        errors.append("\(path).capturedAt: must be a string.")
    }
    if (meta["deviceModel"] as? String) == nil {
        errors.append("\(path).deviceModel: must be a string.")
    }
    if (meta["scannerApp"] as? String) == nil {
        errors.append("\(path).scannerApp: must be a string.")
    }
    if (meta["coordinateConvention"] as? String) == nil {
        errors.append("\(path).coordinateConvention: must be a string.")
    }

    return errors
}
