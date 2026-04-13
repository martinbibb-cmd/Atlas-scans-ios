// MARK: - Supported versions

/// The complete set of scan bundle versions this package can validate.
/// Any bundle whose `version` field is not in this array will be rejected.
public let supportedScanBundleVersions: [String] = ["1.0"]

/// The current scan bundle version emitted by this client.
public let currentScanBundleVersion: String = "1.0"

// MARK: - Version helpers

/// Returns true when `version` is one of `supportedScanBundleVersions`.
public func isSupportedVersion(_ version: String) -> Bool {
    supportedScanBundleVersions.contains(version)
}

/// Returns true when `input` has a `version` field that is non-empty but
/// is not in `supportedScanBundleVersions`.
///
/// Useful so callers can distinguish a structurally invalid bundle from one
/// that comes from a newer (unsupported) contract version.
///
/// - Parameter input: A dictionary representation of the incoming bundle.
/// - Returns: `true` when a non-empty, unrecognised version string is present.
public func isUnsupportedVersion(_ input: [String: Any]) -> Bool {
    guard let v = input["version"] as? String, !v.isEmpty else { return false }
    return !isSupportedVersion(v)
}

// MARK: - Stale-data detection

/// Returns `true` when `version` is valid but represents an older format than
/// `currentScanBundleVersion`.
///
/// Version comparison uses lexicographic ordering of the dot-separated component
/// integers (e.g. "1.0" < "1.1" < "2.0").  If either string cannot be parsed
/// as a version, the function returns `false` to avoid false positives.
///
/// - Parameter version: The `version` string from an incoming bundle.
/// - Returns: `true` when the bundle is from an older contract generation.
public func isBundleVersionStale(_ version: String) -> Bool {
    guard isSupportedVersion(version) else { return false }
    return versionComponents(version) < versionComponents(currentScanBundleVersion)
}

// MARK: - Internal helpers

private func versionComponents(_ version: String) -> [Int] {
    version.split(separator: ".").compactMap { Int($0) }
}
