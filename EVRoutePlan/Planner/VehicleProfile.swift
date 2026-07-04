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
}

/// User-tunable planning parameters, persisted in UserDefaults by AppState.
struct PlannerSettings: Sendable {
    var trim: Ioniq5Trim = .seLongRangeAWD
    /// Never plan to arrive anywhere below this state of charge.
    var reserveSOC: Double = 0.10
    /// Stop DC charging here — the curve above 80 % is slow on E-GMP.
    var maxChargeSOC: Double = 0.80
    /// Real-world highway range as a fraction of EPA (75 mph, HVAC).
    var rangeFactor: Double = 0.85
    /// How far off-route a charger may be, miles.
    var corridorRadiusMiles: Double = 12.0

    var usableRangeMiles: Double { trim.epaRangeMiles * rangeFactor }
    var milesPerSOC: Double { usableRangeMiles } // miles for SOC 0→1

    /// Average DC charging power (kW) across a SOC window, approximating the
    /// E-GMP curve: strong up to ~55 %, tapering to ~80 %, slow above.
    /// `peakKW` is the min(site, car) peak for the specific station.
    func averagePowerKW(fromSOC: Double, toSOC: Double, peakKW: Double) -> Double {
        guard toSOC > fromSOC else { return peakKW }
        // Piecewise fraction-of-peak by SOC band.
        func fractionOfPeak(at soc: Double) -> Double {
            switch soc {
            case ..<0.55: return 1.0
            case ..<0.70: return 0.75
            case ..<0.80: return 0.55
            case ..<0.90: return 0.30
            default: return 0.15
            }
        }
        // Integrate in 5 % steps.
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
