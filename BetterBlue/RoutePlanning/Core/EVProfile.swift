//
//  EVProfile.swift
//  BetterBlue
//
//  Battery/charging characteristics the route planner needs for a vehicle.
//  Stored per VIN in UserDefaults (not on BBVehicle) so adding it doesn't
//  change the CloudKit-synced SwiftData schema.
//

import Foundation

struct EVProfile: Codable, Hashable, Sendable {
    var name: String
    /// Usable pack capacity.
    var usableBatteryKWh: Double
    /// Rated (EPA) range on a full charge.
    var ratedRangeMiles: Double
    /// Peak DC fast-charge power the car accepts.
    var maxDCKW: Double
    /// State of charge to leave each charging stop with.
    var targetSOC: Double = 0.80
    /// Minimum state of charge to arrive anywhere with.
    var arrivalReserveSOC: Double = 0.10

    /// Effective full-charge range. Live BlueLink data (range ÷ SOC) reflects
    /// real conditions — temperature, speed, driving style — better than the
    /// rated figure, so prefer it when it's plausible.
    func fullRangeMiles(liveRangeMiles: Double?, livePercent: Double?) -> Double {
        guard let range = liveRangeMiles, let percent = livePercent,
              percent >= 10, range > 0 else { return ratedRangeMiles }
        let derived = range / (percent / 100)
        // Guard against glitchy readings (stale range after a charge, etc.).
        guard derived >= ratedRangeMiles * 0.5, derived <= ratedRangeMiles * 1.5 else {
            return ratedRangeMiles
        }
        return derived
    }
}

// MARK: - Presets

extension EVProfile {
    static let ioniq5StandardRWD = EVProfile(
        name: "Ioniq 5 Standard Range RWD", usableBatteryKWh: 63.0, ratedRangeMiles: 245, maxDCKW: 175)
    static let ioniq5LongRangeRWD = EVProfile(
        name: "Ioniq 5 Long Range RWD", usableBatteryKWh: 84.0, ratedRangeMiles: 318, maxDCKW: 260)
    static let ioniq5LongRangeAWD = EVProfile(
        name: "Ioniq 5 Long Range AWD", usableBatteryKWh: 84.0, ratedRangeMiles: 290, maxDCKW: 260)
    static let ioniq5Gen1RWD = EVProfile(
        name: "Ioniq 5 Long Range RWD (2022–24)", usableBatteryKWh: 77.4, ratedRangeMiles: 303, maxDCKW: 235)
    static let ioniq5Gen1AWD = EVProfile(
        name: "Ioniq 5 Long Range AWD (2022–24)", usableBatteryKWh: 77.4, ratedRangeMiles: 266, maxDCKW: 235)
    static let ioniq6LongRangeRWD = EVProfile(
        name: "Ioniq 6 Long Range RWD", usableBatteryKWh: 77.4, ratedRangeMiles: 342, maxDCKW: 235)
    static let ioniq9AWD = EVProfile(
        name: "Ioniq 9 AWD", usableBatteryKWh: 110.3, ratedRangeMiles: 311, maxDCKW: 230)
    static let konaElectric = EVProfile(
        name: "Kona Electric Long Range", usableBatteryKWh: 64.8, ratedRangeMiles: 261, maxDCKW: 100)
    static let ev6LongRangeRWD = EVProfile(
        name: "EV6 Long Range RWD", usableBatteryKWh: 84.0, ratedRangeMiles: 319, maxDCKW: 260)
    static let ev9LongRangeAWD = EVProfile(
        name: "EV9 Long Range AWD", usableBatteryKWh: 99.8, ratedRangeMiles: 280, maxDCKW: 230)
    static let niroEV = EVProfile(
        name: "Niro EV", usableBatteryKWh: 64.8, ratedRangeMiles: 253, maxDCKW: 85)

    static let presets: [EVProfile] = [
        .ioniq5StandardRWD, .ioniq5LongRangeRWD, .ioniq5LongRangeAWD,
        .ioniq5Gen1RWD, .ioniq5Gen1AWD, .ioniq6LongRangeRWD, .ioniq9AWD,
        .konaElectric, .ev6LongRangeRWD, .ev9LongRangeAWD, .niroEV,
    ]

    /// Best-guess preset from the model name BlueLink reports.
    static func defaultPreset(forModel model: String) -> EVProfile {
        let m = model.uppercased().replacingOccurrences(of: " ", with: "")
        if m.contains("IONIQ5") { return .ioniq5LongRangeAWD }
        if m.contains("IONIQ6") { return .ioniq6LongRangeRWD }
        if m.contains("IONIQ9") { return .ioniq9AWD }
        if m.contains("KONA") { return .konaElectric }
        if m.contains("EV6") { return .ev6LongRangeRWD }
        if m.contains("EV9") { return .ev9LongRangeAWD }
        if m.contains("NIRO") { return .niroEV }
        return .ioniq5LongRangeAWD
    }
}

// MARK: - Storage

enum EVProfileStore {
    private static func key(_ vin: String) -> String { "routePlanning.evProfile.\(vin)" }

    static func profile(forVIN vin: String, model: String, defaults: UserDefaults = .standard) -> EVProfile {
        if let data = defaults.data(forKey: key(vin)),
           let profile = try? JSONDecoder().decode(EVProfile.self, from: data) {
            return profile
        }
        return .defaultPreset(forModel: model)
    }

    static func save(_ profile: EVProfile, forVIN vin: String, defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(profile) {
            defaults.set(data, forKey: key(vin))
        }
    }
}
