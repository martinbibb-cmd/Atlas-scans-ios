import SwiftUI

// MARK: - VisitCaptureScreen

/// The capture screens available within one visit session.
///
/// Engineers can move freely between screens at any time; switching never
/// creates a separate session fragment.  All screens read from and write
/// to the single shared `VisitCaptureViewModel`.
enum VisitCaptureScreen: String, CaseIterable, Hashable {

    case overview = "overview"
    case lidar    = "lidar"
    case photos   = "photos"
    case voice    = "voice"
    case objects  = "objects"
    case summary  = "summary"

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .lidar:    return "LiDAR"
        case .photos:   return "Photos"
        case .voice:    return "Voice"
        case .objects:  return "Objects"
        case .summary:  return "Summary"
        }
    }

    var symbolName: String {
        switch self {
        case .overview: return "house"
        case .lidar:    return "lidar.scanner"
        case .photos:   return "camera"
        case .voice:    return "mic"
        case .objects:  return "mappin.and.ellipse"
        case .summary:  return "checklist"
        }
    }

    /// Short label used in the segmented control / tab bar.
    var shortLabel: String {
        switch self {
        case .overview: return "Visit"
        case .lidar:    return "LiDAR"
        case .photos:   return "Photos"
        case .voice:    return "Voice"
        case .objects:  return "Objects"
        case .summary:  return "Summary"
        }
    }
}
