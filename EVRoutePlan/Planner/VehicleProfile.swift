import Foundation

/// 2026 Hyundai Ioniq 5 (facelift, native NACS port) trims and energy model.
enum Ioniq5Trim: String, CaseIterable, Identifiable, Sendable {
    case seStandardRange = "SE Standard Range (63 kWh)"
    case seLongRangeRWD = "SE / SEL RWD (84 kWh)"
    case limitedRWD = "Limited RWD (84 kWh)"
    case seLongRangeAWD = "SE / SEL AWD (84 kWh)"
    case limitedAWD = "Limited AWD (84 kWh)"
    case xrt = "XRT (84 kWh)"

    var id: String { rawValue }

    var usableBatteryKWh: Double {
        switch self {
        case .seStandardRange: return 63.0
        default: return 84.0
        }
    }

    /// EPA-rated range, miles.
    var epaRangeMiles: Double {
        switch self {
        case .seStandardRange: return 245
        case .seLongRangeRWD: return 318
        case .limitedRWD: return 303
        case .seLongRangeAWD: return 290
        case .limitedAWD: return 269
        case .xrt: return 259
        }
    }

    /// EPA-implied consumption at reference conditions.
    var defaultWhPerMi: Double {
        usableBatteryKWh * 1000 / epaRangeMiles
    }
}

/// User-tunable planning parameters, persisted in UserDefaults by AppState.
/// Consumption model is ABRP-style: a reference Wh/mi, scaled by cruise
/// speed and (optionally) ambient temperature.
struct PlannerSettings: Sendable {
    var trim: Ioniq5Trim = .seLongRangeAWD
    /// Never plan to arrive anywhere below this state of charge.
    var reserveSOC: Double = 0.10
    /// Stop DC charging here — the curve above 80 % is slow on E-GMP.
    var maxChargeSOC: Double = 0.80
    /// Reference consumption at 65 mph, 70 °F. 0 = use the trim's EPA default.
    var referenceWhPerMi: Double = 0
    /// Typical highway cruise speed for trips.
    var maxSpeedMph: Double = 75
    /// Adjust range for ambient temperature via WeatherKit.
    var weatherAdjustEnabled: Bool = true
    /// How far off-route a charger may be, miles.
    var corridorRadiusMiles: Double = 12.0
    /// Only plan stops at chargers the car can pull at least this from.
    var minChargerKW: Double = 125
    /// Bias stop selection toward native-plug NACS sites.
    var preferNACS: Bool = true
    var avoidTolls: Bool = false
    var avoidHighways: Bool = false

    var effectiveWhPerMi: Double {
        referenceWhPerMi > 0 ? referenceWhPerMi : trim.defaultWhPerMi
    }

    /// Consumption multiplier for cruise speed. 1.0 at 65 mph; quadratic
    /// aero growth above (≈ +20 % at 80 mph), documented approximation.
    var speedMultiplier: Double {
        0.55 + 0.45 * (maxSpeedMph / 65.0) * (maxSpeedMph / 65.0)
    }

    /// Consumption multiplier for ambient temperature (heating/cooling +
    /// battery efficiency). 1.0 at 70 °F.
    static func weatherMultiplier(tempF: Double) -> Double {
        let points: [(Double, Double)] = [(0, 1.42), (20, 1.30), (45, 1.12), (70, 1.0), (85, 1.03), (95, 1.08), (110, 1.15)]
        if tempF <= points[0].0 { return points[0].1 }
        for i in 1..<points.count where tempF <= points[i].0 {
            let (x0, y0) = points[i - 1]
            let (x1, y1) = points[i]
            return y0 + (y1 - y0) * (tempF - x0) / (x1 - x0)
        }
        return points[points.count - 1].1
    }

    /// Miles of range for a full 0→1 SOC swing under given conditions.
    func milesPerSOC(weatherMultiplier: Double = 1.0) -> Double {
        trim.usableBatteryKWh * 1000 / (effectiveWhPerMi * speedMultiplier * weatherMultiplier)
    }

    /// Planning range shown in Settings (fair weather).
    var usableRangeMiles: Double { milesPerSOC() }

    /// Average DC charging power (kW) across a SOC window, approximating the
    /// E-GMP curve: strong up to ~55 %, tapering to ~80 %, slow above.
    /// `peakKW` is the min(site, car) peak for the specific station.
    func averagePowerKW(fromSOC: Double, toSOC: Double, peakKW: Double) -> Double {
        guard toSOC > fromSOC else { return peakKW }
        func fractionOfPeak(at soc: Double) -> Double {
            switch soc {
            case ..<0.55: return 1.0
            case ..<0.70: return 0.75
            case ..<0.80: return 0.55
            case ..<0.90: return 0.30
            default: return 0.15
            }
        }
        var total = 0.0
        var weight = 0.0
        var soc = fromSOC
        while soc < toSOC {
            let step = min(0.05, toSOC - soc)
            total += fractionOfPeak(at: soc) * step
            weight += step
            soc += step
        }
        return peakKW * (weight > 0 ? total / weight : 1.0)
    }

    /// Minutes to charge between two SOC levels at a station.
    func chargeMinutes(fromSOC: Double, toSOC: Double, stationPeakKW: Double) -> Double {
        guard toSOC > fromSOC else { return 0 }
        let energyKWh = (toSOC - fromSOC) * trim.usableBatteryKWh
        let avgKW = averagePowerKW(fromSOC: fromSOC, toSOC: toSOC, peakKW: stationPeakKW)
        guard avgKW > 0 else { return 0 }
        // ~4 min overhead for plugging in / session start.
        return energyKWh / avgKW * 60.0 + 4.0
    }
}
