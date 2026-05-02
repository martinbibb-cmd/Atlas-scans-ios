import Foundation
import AtlasContracts
#if canImport(UIKit)
import UIKit
#endif

// MARK: - OpenAtlasMind
//
// Opens the Atlas Mind PWA at the /receive-scan route with a preloaded
// ScanToMindHandoffV1 payload.
//
// Default URL:
//   https://next.atlas-phm.uk/receive-scan
//
// URL construction:
//   https://next.atlas-phm.uk/receive-scan?payload=<percent-encoded JSON>
//
// Developer Mode override:
//   When Developer Mode is active, the base receive-scan URL can be overridden
//   via UserDefaults key "atlas.mind.receiveScanURL".  This allows testing
//   against a local or staging Mind instance without changing production config.
//   In production (Developer Mode off) the default URL is always used.
//
// Rules:
//   • No JSON screen is shown in the normal user flow.
//   • Developer tools (e.g. copy payload, override URL) must stay behind
//     DeveloperModeStore.isEnabled.
//   • openMind(with:) must be called on the main actor.

enum OpenAtlasMind {

    // MARK: - Configuration

    private static let defaultReceiveScanURL = URL(string: "https://next.atlas-phm.uk/receive-scan")!

    /// UserDefaults key used to override the receive-scan base URL in Developer Mode.
    static let devOverrideURLKey = "atlas.mind.receiveScanURL"

    /// The base receive-scan URL to use.
    ///
    /// Returns the Developer Mode override URL when Developer Mode is active
    /// and a valid override has been stored; otherwise returns the default.
    static var receiveScanBaseURL: URL {
        guard DeveloperModeStore.shared.isEnabled,
              let override = UserDefaults.standard.string(forKey: devOverrideURLKey),
              !override.isEmpty,
              let url = URL(string: override) else {
            return defaultReceiveScanURL
        }
        return url
    }

    // MARK: - Open

    /// Encodes the handoff and opens Atlas Mind at the /receive-scan route.
    ///
    /// The full ``ScanToMindHandoffV1`` is percent-encoded as a JSON query
    /// parameter and appended to the base receive-scan URL.  The resulting
    /// URL is opened via `UIApplication.shared.open` (default browser or
    /// installed Mind PWA).
    ///
    /// Failures during encoding are silently ignored; Mind will simply open
    /// at the base URL without a preloaded visit.  This is intentional —
    /// the engineer should never see a blocking error screen at this point.
    ///
    /// - Parameter handoff: The completed handoff to deliver to Mind.
    @MainActor
    static func openMind(with handoff: ScanToMindHandoffV1) {
        let encodedPayload: String
        do {
            encodedPayload = try ScanToMindPayloadEncoder.encodeForURL(handoff)
        } catch {
            // Encoding failure: open Mind at the base URL without a payload.
            print("[OpenAtlasMind] Failed to encode handoff payload: \(error.localizedDescription)")
            openURL(receiveScanBaseURL)
            return
        }

        var components = URLComponents(url: receiveScanBaseURL, resolvingAgainstBaseURL: false)
        // Assign the pre-encoded payload directly to avoid double-encoding.
        components?.percentEncodedQuery = "payload=\(encodedPayload)"

        let url = components?.url ?? receiveScanBaseURL
        openURL(url)
    }

    // MARK: - Private

    @MainActor
    private static func openURL(_ url: URL) {
        #if canImport(UIKit)
        UIApplication.shared.open(url)
        #endif
    }
}
