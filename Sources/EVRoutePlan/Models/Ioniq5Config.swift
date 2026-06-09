import Foundation

enum Ioniq5Config {
    enum Variant: String, CaseIterable, Sendable {
        case standardRWD   = "Standard Range RWD"
        case longRangeRWD  = "Long Range RWD"
        case longRangeAWD  = "Long Range AWD"

        var batteryKWh: Double {
            switch self {
            case .standardRWD:  return 77.4
            case .longRangeRWD, .longRangeAWD: return 84.0
            }
        }

        var epaRangeMiles: Double {
            switch self {
            case .standardRWD:  return 266.0
            case .longRangeRWD: return 303.0
            case .longRangeAWD: return 310.0
            }
        }
    }

    static let maxDCChargingKW: Double = 350.0
    static let defaultTargetSOC: Double = 0.80
    // Plan to arrive with 10 % SOC remaining
    static let arrivalBufferFactor: Double = 0.90
    // Use 75 % of available range per driving segment
    static let segmentFactor: Double = 0.75
    // Search radius around each waypoint for chargers
    static let corridorRadiusMiles: Double = 15.0
    static let minimumDCFastKW: Double = 50.0
    static let defaultVariant: Variant = .longRangeAWD
}
