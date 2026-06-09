import CoreLocation

struct NRELResponse: Decodable, Sendable {
    let altFuelStations: [ChargingStation]

    enum CodingKeys: String, CodingKey {
        case altFuelStations = "alt_fuel_stations"
    }
}

struct ChargingStation: Decodable, Identifiable, Sendable {
    let id: Int
    let stationName: String
    let streetAddress: String
    let city: String
    let state: String
    let zip: String
    let latitude: Double
    let longitude: Double
    let evNetwork: String?
    let evConnectorTypes: [String]?
    let evDcFastNum: Int?
    let evLevel2EvseNum: Int?
    let accessCode: String
    let statusCode: String

    enum CodingKeys: String, CodingKey {
        case id
        case stationName        = "station_name"
        case streetAddress      = "street_address"
        case city
        case state
        case zip
        case latitude
        case longitude
        case evNetwork          = "ev_network"
        case evConnectorTypes   = "ev_connector_types"
        case evDcFastNum        = "ev_dc_fast_num"
        case evLevel2EvseNum    = "ev_level2_evse_num"
        case accessCode         = "access_code"
        case statusCode         = "status_code"
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var hasDCFast: Bool { (evDcFastNum ?? 0) > 0 }

    // Proxy estimate — NREL doesn't expose per-port kW; use network brand as signal.
    var estimatedMaxKW: Double {
        guard let network = evNetwork?.lowercased() else { return Ioniq5Config.minimumDCFastKW }
        if network.contains("electrify") { return 350.0 }
        if network.contains("tesla")     { return 250.0 }
        if network.contains("evgo")      { return 200.0 }
        if network.contains("chargepoint") { return 62.5 }
        return Ioniq5Config.minimumDCFastKW
    }
}
