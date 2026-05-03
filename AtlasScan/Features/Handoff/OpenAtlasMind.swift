import Foundation
import AtlasContracts
#if canImport(UIKit)
import UIKit
#endif

// MARK: - OpenAtlasMind
//
// Opens the Atlas Mind PWA at a handoff route with a preloaded
// ScanToMindHandoffV1 payload.
//
// Supported routes:
//   /receive-scan    — general visit handoff
//   /quote-planner   — quote planner pre-loaded with visit evidence
//
// Default URLs:
//   https://next.atlas-phm.uk/receive-scan
//   https://next.atlas-phm.uk/quote-planner
//
// URL construction (receive-scan):
//   https://next.atlas-phm.uk/receive-scan?payload=<percent-encoded JSON>
//
// URL construction (quote-planner):
//   https://next.atlas-phm.uk/quote-planner?sessionRef=<visitId>&payload=<percent-encoded JSON>
//
//   When the encoded payload exceeds the safe URL length limit, the payload
//   parameter is omitted and Mind is opened with sessionRef alone so that it
//   can fetch the session via its own API.
//
// Developer Mode override:
//   When Developer Mode is active, the base URLs can be overridden via
//   UserDefaults keys "atlas.mind.receiveScanURL" and
//   "atlas.mind.quotePlannerURL".  This allows testing against a local or
//   staging Mind instance without changing production config.
//   In production (Developer Mode off) the default URLs are always used.
//
// Rules:
//   • No JSON screen is shown in the normal user flow.
//   • Developer tools (e.g. copy payload, override URL) must stay behind
//     DeveloperModeStore.isEnabled.
//   • openMind(with:) and openQuotePlanner(with:) must be called on the main actor.
//   • makeQuotePlannerURL(for:) is a pure function safe to call from any context.

enum OpenAtlasMind {

    // MARK: - Configuration

    private static let defaultReceiveScanURL = URL(string: "https://next.atlas-phm.uk/receive-scan")!
    private static let defaultQuotePlannerURL = URL(string: "https://next.atlas-phm.uk/quote-planner")!

    /// Maximum safe URL length before falling back to sessionRef-only for the quote-planner route.
    private static let quotePlannerURLLengthLimit = 8_000

    /// UserDefaults key used to override the receive-scan base URL in Developer Mode.
    static let devOverrideURLKey = "atlas.mind.receiveScanURL"

    /// UserDefaults key used to override the quote-planner base URL in Developer Mode.
    static let devOverrideQuotePlannerURLKey = "atlas.mind.quotePlannerURL"

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

    /// The base quote-planner URL to use.
    ///
    /// Returns the Developer Mode override URL when Developer Mode is active
    /// and a valid override has been stored; otherwise returns the default.
    static var quotePlannerBaseURL: URL {
        guard DeveloperModeStore.shared.isEnabled,
              let override = UserDefaults.standard.string(forKey: devOverrideQuotePlannerURLKey),
              !override.isEmpty,
              let url = URL(string: override) else {
            return defaultQuotePlannerURL
        }
        return url
    }

    // MARK: - Open (receive-scan)

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

    // MARK: - Open (quote-planner)

    /// Opens Atlas Mind at the /quote-planner route with visit evidence preloaded.
    ///
    /// Constructs a URL of the form:
    ///   `/quote-planner?sessionRef=<visitId>&payload=<percent-encoded JSON>`
    ///
    /// When the encoded payload would exceed ``quotePlannerURLLengthLimit`` characters,
    /// the payload parameter is omitted and Mind receives only the sessionRef.  Mind
    /// can then retrieve the session via its own API using the reference.
    ///
    /// The URL is built via ``makeQuotePlannerURL(for:)`` and can be inspected or
    /// copied before opening — useful for the "copy handoff link" fallback in the UI.
    ///
    /// - Parameter handoff: The completed handoff to deliver to Mind.
    @MainActor
    static func openQuotePlanner(with handoff: ScanToMindHandoffV1) {
        let url = makeQuotePlannerURL(for: handoff)
        openURL(url)
    }

    /// Builds the quote-planner URL for the given handoff without opening it.
    ///
    /// Always returns a valid URL — falls back to sessionRef-only when the full
    /// payload URL would exceed ``quotePlannerURLLengthLimit`` characters or when
    /// payload encoding fails.
    ///
    /// This is a pure function; it has no side effects and can be called from
    /// any context (not restricted to the main actor).
    ///
    /// - Parameter handoff: The handoff to build a quote-planner URL for.
    /// - Returns: The best-effort quote-planner URL for this handoff.
    static func makeQuotePlannerURL(for handoff: ScanToMindHandoffV1) -> URL {
        let base = quotePlannerBaseURL

        // Attempt to build the full URL with encoded payload.
        if let encoded = try? ScanToMindPayloadEncoder.encodeForURL(handoff) {
            var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
            // visitId (UUID) is percent-encoded for robustness; payload is already encoded by the encoder.
            let encodedRef = handoff.visitId
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? handoff.visitId
            components?.percentEncodedQuery = "sessionRef=\(encodedRef)&payload=\(encoded)"
            if let url = components?.url,
               url.absoluteString.count <= quotePlannerURLLengthLimit {
                return url
            }
        }

        // Fallback: sessionRef-only URL — Mind fetches the session via its own API.
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "sessionRef", value: handoff.visitId)]
        return components?.url ?? base
    }

    // MARK: - Private

    @MainActor
    private static func openURL(_ url: URL) {
        #if canImport(UIKit)
        UIApplication.shared.open(url)
        #endif
    }
}
