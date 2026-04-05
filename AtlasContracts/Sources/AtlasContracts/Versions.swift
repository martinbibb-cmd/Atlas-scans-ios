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
