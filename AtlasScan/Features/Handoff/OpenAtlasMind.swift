// OpenAtlasMind — URL construction and deep-link routing for Atlas Mind.
//
// Routes:
//   /receive-scan    — primary handoff; Mind preloads the full visit capture.
//   /quote-planner   — opens the Quote Planner with visit evidence preloaded.
//
// URL format:
//   https://next.atlas-phm.uk/<route>?sessionRef=<visitId>&payload=<encodedJSON>
//
// The payload is percent-encoded JSON (via ScanToMindPayloadEncoder.encodeForURL).
// When the full URL would exceed 8 000 characters the payload is omitted and only
// the sessionRef parameter is included (Mind falls back to a server-side fetch).

import Foundation
import AtlasContracts

#if canImport(UIKit)
import UIKit
#endif

enum OpenAtlasMind {

    private static let mindBaseURL = URL(string: "https://next.atlas-phm.uk")!
    /// Maximum URL length before the payload is dropped in favour of sessionRef-only.
    ///
    /// 8 000 characters is a conservative limit that fits within the practical
    /// browser URL bar and iOS `UIApplication.open` constraints (the HTTP spec
    /// has no hard limit, but many proxies and browsers cap at 8 000–16 000 chars).
    private static let maxURLLength = 8_000

    // MARK: - openMind

    /// Opens Atlas Mind at `/receive-scan` with the handoff payload pre-loaded.
    static func openMind(with handoff: ScanToMindHandoffV1) {
        let url = makeReceiveScanURL(for: handoff)
        open(url)
    }

    // MARK: - openQuotePlanner

    /// Opens Atlas Mind at `/quote-planner` with the handoff payload pre-loaded.
    static func openQuotePlanner(with handoff: ScanToMindHandoffV1) {
        let url = makeQuotePlannerURL(for: handoff)
        open(url)
    }

    // MARK: - makeQuotePlannerURL

    /// Builds the `/quote-planner` URL for the given handoff.
    ///
    /// Always includes `sessionRef=<visitId>`. Appends a percent-encoded
    /// `payload=` parameter when the resulting URL stays within
    /// ``maxURLLength`` characters; otherwise omits the payload so Mind
    /// can fall back to a server-side fetch using the session reference.
    static func makeQuotePlannerURL(for handoff: ScanToMindHandoffV1) -> URL {
        makeURL(route: "quote-planner", handoff: handoff)
    }

    // MARK: - Private helpers

    private static func makeReceiveScanURL(for handoff: ScanToMindHandoffV1) -> URL {
        makeURL(route: "receive-scan", handoff: handoff)
    }

    /// Constructs a Mind URL for the given route, applying the sessionRef + payload
    /// pattern with automatic fallback when the URL would exceed ``maxURLLength``.
    private static func makeURL(route: String, handoff: ScanToMindHandoffV1) -> URL {
        let base = mindBaseURL.appendingPathComponent(route).absoluteString
        let sessionRef = handoff.visit.visitId

        if let encoded = try? ScanToMindPayloadEncoder.encodeForURL(handoff) {
            let fullString = "\(base)?sessionRef=\(sessionRef)&payload=\(encoded)"
            if fullString.count <= maxURLLength, let url = URL(string: fullString) {
                return url
            }
        }

        // Fallback: sessionRef only (Mind fetches the session server-side).
        // This string is always valid: the base URL and visitId are well-formed,
        // so the force-unwrap is safe.
        let fallback = "\(base)?sessionRef=\(sessionRef)"
        return URL(string: fallback)!
    }

    private static func open(_ url: URL) {
        #if canImport(UIKit)
        Task { @MainActor in
            await UIApplication.shared.open(url)
        }
        #endif
    }
}
