import Foundation

// MARK: - ServiceObjectCategory

/// Domain categories for tagged service objects.
/// Grouped to reflect heating-system and building-services engineering.
enum ServiceObjectCategory: String, Codable, CaseIterable, Identifiable {

    // Heat source / plant
    case boiler
    case heatPump       = "heat_pump"
    case cylinder
    case thermalStore   = "thermal_store"
    case bufferVessel   = "buffer_vessel"
    case pump
    case lowLossHeader  = "low_loss_header"
    case expansionVessel = "expansion_vessel"
    case manifold
    case zoneValve      = "zone_valve"

    // Emitters
    case radiator
    case radiatorDrop   = "radiator_drop"
    case towelRail      = "towel_rail"
    case ufhZone        = "ufh_zone"
    case fanConvector   = "fan_convector"

    // Services / utilities
    case gasMeter       = "gas_meter"
    case electricMeter  = "electric_meter"
    case consumerUnit   = "consumer_unit"
    case stopTap        = "stop_tap"
    case flue
    case drainPoint     = "drain_point"

    // Controls
    case thermostat
    case programmer
    case smartController = "smart_controller"
    case thermostatReceiver = "thermostat_receiver"

    // Structural / siting
    case airingCupboard = "airing_cupboard"
    case loftHatch      = "loft_hatch"
    case externalWall   = "external_wall_candidate"
    case likelyFlueRoute = "likely_flue_route"
    case serviceVoid    = "service_void"
    case plantSpace     = "plant_space"

    // Fallback
    case other

    var id: String { rawValue }

    // MARK: Display

    var displayName: String {
        switch self {
        case .boiler:               return "Boiler"
        case .heatPump:             return "Heat Pump"
        case .cylinder:             return "Cylinder"
        case .thermalStore:         return "Thermal Store"
        case .bufferVessel:         return "Buffer Vessel"
        case .pump:                 return "Pump"
        case .lowLossHeader:        return "Low Loss Header"
        case .expansionVessel:      return "Expansion Vessel"
        case .manifold:             return "Manifold"
        case .zoneValve:            return "Zone Valve"
        case .radiator:             return "Radiator"
        case .radiatorDrop:         return "Radiator Drop"
        case .towelRail:            return "Towel Rail"
        case .ufhZone:              return "UFH Zone"
        case .fanConvector:         return "Fan Convector"
        case .gasMeter:             return "Gas Meter"
        case .electricMeter:        return "Electric Meter"
        case .consumerUnit:         return "Consumer Unit"
        case .stopTap:              return "Stop Tap"
        case .flue:                 return "Flue"
        case .drainPoint:           return "Drain Point"
        case .thermostat:           return "Room Thermostat"
        case .programmer:           return "Programmer"
        case .smartController:      return "Smart Controller"
        case .thermostatReceiver:   return "Thermostat Receiver"
        case .airingCupboard:       return "Airing Cupboard"
        case .loftHatch:            return "Loft Hatch"
        case .externalWall:         return "External Wall Candidate"
        case .likelyFlueRoute:      return "Likely Flue Route"
        case .serviceVoid:          return "Service Void"
        case .plantSpace:           return "Heating cupboard / utility space"
        case .other:                return "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .boiler, .heatPump:            return "flame.fill"
        case .cylinder, .thermalStore, .bufferVessel: return "cylinder.split.1x2.fill"
        case .pump, .lowLossHeader, .expansionVessel: return "gauge.with.dots.needle.67percent"
        case .manifold, .zoneValve:         return "arrow.triangle.branch"
        case .radiator, .radiatorDrop, .towelRail, .fanConvector: return "thermometer.medium"
        case .ufhZone:                      return "square.grid.3x3.fill"
        case .gasMeter:                     return "flame"
        case .electricMeter, .consumerUnit: return "bolt.fill"
        case .stopTap, .drainPoint:         return "drop.fill"
        case .flue, .likelyFlueRoute:       return "arrow.up.to.line"
        case .thermostat, .programmer, .smartController, .thermostatReceiver: return "dial.medium"
        case .airingCupboard, .plantSpace:  return "cabinet.fill"
        case .loftHatch:                    return "door.left.hand.open"
        case .externalWall:                 return "house.fill"
        case .serviceVoid:                  return "rectangle.dashed"
        case .other:                        return "tag.fill"
        }
    }

    /// The most appropriate EvidenceKind for a direct-capture photo of this object.
    /// Used when the engineer takes an inline live-view photo so that the photo
    /// is automatically filed under the right category without extra form steps.
    var defaultEvidenceKind: CapturePhotoKind {
        switch self {
        case .boiler, .heatPump, .cylinder, .thermalStore, .bufferVessel,
             .pump, .lowLossHeader, .expansionVessel, .manifold, .zoneValve:
            return .plant
        case .radiator, .radiatorDrop, .towelRail, .ufhZone, .fanConvector:
            return .emitter
        case .flue, .likelyFlueRoute:
            return .flue
        case .thermostat, .programmer, .smartController, .thermostatReceiver:
            return .control
        case .airingCupboard, .plantSpace:
            return .cupboard
        default:
            return .other
        }
    }

    var groupName: String {
        switch self {
        case .boiler, .heatPump, .cylinder, .thermalStore, .bufferVessel,
             .pump, .lowLossHeader, .expansionVessel, .manifold, .zoneValve:
            return "Boiler, cylinder & heating equipment"
        case .radiator, .radiatorDrop, .towelRail, .ufhZone, .fanConvector:
            return "Emitters"
        case .gasMeter, .electricMeter, .consumerUnit, .stopTap, .flue, .drainPoint:
            return "Services / Utilities"
        case .thermostat, .programmer, .smartController, .thermostatReceiver:
            return "Controls"
        case .airingCupboard, .loftHatch, .externalWall, .likelyFlueRoute, .serviceVoid, .plantSpace:
            return "Structural / Siting"
        case .other:
            return "Other"
        }
    }

    // MARK: Quick-entry fields

    var quickFields: [QuickField] {
        switch self {
        case .radiator:
            return [
                QuickField(key: "type",            label: "Type",            inputKind: .text),
                QuickField(key: "width_estimate",  label: "Width estimate",  inputKind: .text),
                QuickField(key: "external_wall",   label: "On external wall?", inputKind: .boolean),
                QuickField(key: "under_window",    label: "Under window?",   inputKind: .boolean),
            ]
        case .boiler:
            return [
                QuickField(key: "type",            label: "Boiler type",     inputKind: .text),
                QuickField(key: "flue_direction",  label: "Flue direction",  inputKind: .text),
                QuickField(key: "enclosed",        label: "In cupboard?",    inputKind: .boolean),
            ]
        case .cylinder:
            return [
                QuickField(key: "vented",          label: "Vented / Unvented", inputKind: .choice(["Vented", "Unvented", "Unknown"])),
                QuickField(key: "cupboard",        label: "In cupboard?",    inputKind: .boolean),
                QuickField(key: "size",            label: "Approx size",     inputKind: .text),
            ]
        case .flue:
            return [
                QuickField(key: "direction",       label: "Direction",       inputKind: .choice(["Rear", "Left", "Right", "Top", "Unknown"])),
                QuickField(key: "type",            label: "Flue type",       inputKind: .text),
            ]
        default:
            return []
        }
    }
}

// MARK: - QuickField

struct QuickField: Identifiable {
    let id = UUID()
    let key: String
    let label: String
    let inputKind: InputKind

    enum InputKind {
        case text
        case boolean
        case choice([String])
    }
}
