/// MindDeepLinkService — Builds and opens the deep-link / universal link
/// used to jump from Atlas Scan into Atlas Mind for a given visit.
///
/// Two URL forms are produced:
///
///   - Custom-scheme deep link: `atlasmind://visit/{id}?workspaceId=...&source=scan`
///   - Universal link:          `https://next.atlas-phm.uk/visit/{id}?workspaceId=...&source=scan`
///
/// `openVisit(...)` tries the universal link first (preferred — survives
/// app uninstall) and falls back to the custom scheme if `UIApplication`
/// reports it cannot open the universal link.

import Foundation
#if canImport(UIKit)
import UIKit
#endif

public enum MindDeepLinkService {

    public static let customScheme = "atlasmind"
    public static let universalHost = "next.atlas-phm.uk"
    public static let sourceQueryValue = "scan"

    /// Builds the custom-scheme deep link URL.
    public static func deepLinkURL(
        visitId: String,
        workspaceId: String?
    ) -> URL? {
        var components = URLComponents()
        components.scheme = customScheme
        components.host = "visit"
        components.path = "/\(visitId)"
        components.queryItems = queryItems(workspaceId: workspaceId)
        return components.url
    }

    /// Builds the universal link URL.
    public static func universalLinkURL(
        visitId: String,
        workspaceId: String?
    ) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = universalHost
        components.path = "/visit/\(visitId)"
        components.queryItems = queryItems(workspaceId: workspaceId)
        return components.url
    }

    private static func queryItems(workspaceId: String?) -> [URLQueryItem] {
        var items: [URLQueryItem] = [URLQueryItem(name: "source", value: sourceQueryValue)]
        if let workspaceId, !workspaceId.isEmpty {
            items.append(URLQueryItem(name: "workspaceId", value: workspaceId))
        }
        return items
    }

    /// Opens the visit in Atlas Mind. Tries the universal link first and
    /// falls back to the custom scheme. Returns `true` if either URL was
    /// dispatched to `UIApplication.open`.
    @MainActor
    @discardableResult
    public static func openVisit(
        visitId: String,
        workspaceId: String?
    ) -> Bool {
        #if canImport(UIKit)
        let app = UIApplication.shared
        if let universal = universalLinkURL(visitId: visitId, workspaceId: workspaceId),
           app.canOpenURL(universal) {
            app.open(universal, options: [:], completionHandler: nil)
            return true
        }
        if let deep = deepLinkURL(visitId: visitId, workspaceId: workspaceId),
           app.canOpenURL(deep) {
            app.open(deep, options: [:], completionHandler: nil)
            return true
        }
        return false
        #else
        return false
        #endif
    }
}
