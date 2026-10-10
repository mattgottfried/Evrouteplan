//
//  ChargingStation.swift
//  BetterBlue
//
//  NREL Alternative Fuel Stations model (DC fast chargers only).
//

import CoreLocation
import Foundation

/// NREL returns `fuel_stations` from `nearest.json` / `nearby-route.json`
/// and `alt_fuel_stations` from `v1.json`; accept either.
struct NRELResponse: Decodable, Sendable {
    let stations: [ChargingStation]

    private enum CodingKeys: String, CodingKey {
        case fuelStations = "fuel_stations"
        case altFuelStations = "alt_fuel_stations"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stations = try container.decodeIfPresent([ChargingStation].self, forKey: .fuelStations)
            ?? container.decodeIfPresent([ChargingStation].self, forKey: .altFuelStations)
            ?? []
    }
}

struct ChargingStation: Codable, Identifiable, Hashable, Sendable {
    /// Floor for a "fast" charger; also the estimate for unknown networks.
    static let minimumDCFastKW: Double = 50

    let id: Int
    let stationName: String
    let streetAddress: String?
    let city: String?
    let state: String?
    let zip: String?
    let latitude: Double
    let longitude: Double
    let evNetwork: String?
    let evConnectorTypes: [String]?
    let evDcFastNum: Int?
    let accessCode: String?

    enum CodingKeys: String, CodingKey {
        case id
        case stationName = "station_name"
        case streetAddress = "street_address"
        case city, state, zip, latitude, longitude
        case evNetwork = "ev_network"
        case evConnectorTypes = "ev_connector_types"
        case evDcFastNum = "ev_dc_fast_num"
        case accessCode = "access_code"
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var hasDCFast: Bool { (evDcFastNum ?? 0) > 0 }
    var isPublic: Bool { accessCode == nil || accessCode == "public" }

    var locality: String {
        [city, state].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    var networkName: String { evNetwork.map(Self.prettyNetwork) ?? "Unknown network" }

    /// NREL doesn't expose per-port power, so the network brand is the best
    /// available proxy for peak kW.
    var estimatedMaxKW: Double {
        guard let network = evNetwork?.lowercased() else { return Self.minimumDCFastKW }
        if network.contains("ionna") { return 400 }
        if network.contains("mercedes") { return 400 }
        if network.contains("electrify") { return 350 }
        if network.contains("tesla") { return 250 }
        if network.contains("rivian") { return 220 }
        if network.contains("evgo") { return 200 }
        if network.contains("chargepoint") { return 62.5 }
        return Self.minimumDCFastKW
    }

    private static func prettyNetwork(_ raw: String) -> String {
        switch raw {
        case "Electrify America": return raw
        case "EVGO": return "EVgo"
        case "Tesla", "TESLA": return "Tesla Supercharger"
        case "ChargePoint Network": return "ChargePoint"
        default: return raw.replacingOccurrences(of: "_", with: " ")
        }
    }
}
