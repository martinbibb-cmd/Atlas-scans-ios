import Foundation

// MARK: - LiDARMeasurementAxis

/// The directional axis along which a LiDAR clearance distance was measured.
enum LiDARMeasurementAxis: String, CaseIterable {
    case front   = "front"
    case rear    = "rear"
    case left    = "left"
    case right   = "right"
    case ceiling = "ceiling"

    var displayName: String {
        switch self {
        case .front:   return "Front"
        case .rear:    return "Rear"
        case .left:    return "Left"
        case .right:   return "Right"
        case .ceiling: return "Ceiling"
        }
    }

    var symbolName: String {
        switch self {
        case .front:   return "arrow.forward.circle"
        case .rear:    return "arrow.backward.circle"
        case .left:    return "arrow.left.circle"
        case .right:   return "arrow.right.circle"
        case .ceiling: return "arrow.up.to.line"
        }
    }
}

// MARK: - LiDARAxisMeasurement

/// One measured clearance distance along a single axis, compared to the required minimum.
struct LiDARAxisMeasurement {
    let axis: LiDARMeasurementAxis

    /// Distance to the nearest detected surface in metres.
    /// `nil` when no surface was detected within the maximum scan range.
    let measuredMetres: Double?

    /// Minimum required clearance for this axis, in metres.
    let requiredMetres: Double

    var status: ClearanceStatus {
        guard let m = measuredMetres else { return .clear }
        if m < requiredMetres         { return .conflict }
        if m < requiredMetres * 1.20  { return .warning  }
        return .clear
    }

    var displayMeasured: String {
        guard let m = measuredMetres else { return "No obstruction" }
        return String(format: "%.2f m", m)
    }

    var displayRequired: String {
        String(format: "min %.2f m", requiredMetres)
    }
}

// MARK: - LiDARClearanceMeasurement

/// Full result of a LiDAR-based clearance measurement for one appliance position.
struct LiDARClearanceMeasurement {
    let category: ServiceObjectCategory
    let profileName: String?
    let axes: [LiDARAxisMeasurement]
    let capturedAt: Date

    var overallStatus: ClearanceStatus {
        if axes.contains(where: { $0.status == .conflict }) { return .conflict }
        if axes.contains(where: { $0.status == .warning  }) { return .warning  }
        return .clear
    }
}
