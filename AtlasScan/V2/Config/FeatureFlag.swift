/// FeatureFlag — Lightweight runtime feature flags for the Atlas Scan rebuild.
///
/// Backed by `UserDefaults` so flags can be toggled from a debug menu without
/// rebuilding. A compiled-in default is always provided; the live value is the
/// stored override (if any) or the default.
///
/// The `continuousSurveyShell` flag controls whether the new survey-first
/// navigation shell (`SurveyAppRootView`) is the active root, or whether the
/// app continues to use the legacy `PropertyMapView` path.
///
/// PR-6 cutover sets `continuousSurveyShell` default to `true`.

import Foundation

public enum FeatureFlag: String, CaseIterable, Sendable {
    /// Use the continuous-survey navigation shell as the app root.
    /// PR-6 cutover: default is `true`. Toggle off to fall back to the
    /// legacy `PropertyMapView` path while the new shell stabilises.
    case continuousSurveyShell

    /// Hard-coded default value for each flag.
    public var defaultValue: Bool {
        switch self {
        case .continuousSurveyShell:
            return true
        }
    }

    public var defaultsKey: String {
        "atlas.featureFlag.\(rawValue)"
    }
}

public enum FeatureFlags {
    /// Storage backend. Overridable in tests.
    nonisolated(unsafe) public static var defaults: UserDefaults = .standard

    /// Returns the current value for `flag` — stored override if present,
    /// otherwise the compiled-in default.
    public static func isEnabled(_ flag: FeatureFlag) -> Bool {
        if defaults.object(forKey: flag.defaultsKey) != nil {
            return defaults.bool(forKey: flag.defaultsKey)
        }
        return flag.defaultValue
    }

    /// Sets a runtime override for `flag`. Pass `nil` to clear the override
    /// and revert to the compiled-in default.
    public static func setOverride(_ value: Bool?, for flag: FeatureFlag) {
        if let value {
            defaults.set(value, forKey: flag.defaultsKey)
        } else {
            defaults.removeObject(forKey: flag.defaultsKey)
        }
    }
}
