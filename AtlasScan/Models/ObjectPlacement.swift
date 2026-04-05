import Foundation

// MARK: - PlacementMode

/// Describes how a service object is physically attached or placed in a room.
enum PlacementMode: String, Codable, CaseIterable {
    case wallMounted  = "wall_mounted"
    case floorPlaced  = "floor_placed"
    case unplaced     = "unplaced"

    var displayName: String {
        switch self {
        case .wallMounted: return "Wall Mounted"
        case .floorPlaced: return "Floor Placed"
        case .unplaced:    return "Unplaced"
        }
    }

    var symbolName: String {
        switch self {
        case .wallMounted: return "rectangle.on.rectangle.slash"
        case .floorPlaced: return "square.on.square"
        case .unplaced:    return "questionmark.square.dashed"
        }
    }
}

// MARK: - PlacementSize

/// Approximate footprint of a placed service object, in metres.
struct PlacementSize: Codable, Equatable {
    var widthMetres: Double
    var depthMetres: Double

    init(widthMetres: Double = 0.5, depthMetres: Double = 0.3) {
        self.widthMetres = max(0, widthMetres)
        self.depthMetres = max(0, depthMetres)
    }
}

// MARK: - ServiceObjectCategory + default placement

extension ServiceObjectCategory {

    /// Default placement mode for this category of service object.
    /// User-guided placement overrides this at placement time.
    var defaultPlacementMode: PlacementMode {
        switch self {
        // Wall-mounted emitters and controls
        case .radiator, .radiatorDrop, .towelRail, .fanConvector,
             .thermostat, .programmer, .smartController, .thermostatReceiver,
             .gasMeter, .electricMeter, .consumerUnit,
             .stopTap, .flue, .likelyFlueRoute,
             .zoneValve, .externalWall, .serviceVoid:
            return .wallMounted

        // Floor-standing / room-placed plant and fixtures
        case .boiler, .heatPump, .cylinder, .thermalStore, .bufferVessel,
             .pump, .lowLossHeader, .expansionVessel, .manifold,
             .airingCupboard, .plantSpace, .drainPoint,
             .ufhZone, .loftHatch:
            return .floorPlaced

        case .other:
            return .unplaced
        }
    }
}
