import CoreLocation
import Foundation

/// A DC fast-charging site from the NREL Alternative Fuel Station database.
struct ChargingStation: Identifiable, Sendable, Equatable {
    let id: Int
    let name: String
    let streetAddress: String
    let city: String
    let state: String
    let latitude: Double
    let longitude: Double
    let network: String
    let connectorTypes: [String]
    let dcFastCount: Int
    let pricing: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var shortAddress: String { "\(streetAddress), \(city), \(state)" }

    var hasNACS: Bool { connectorTypes.contains("TESLA") }
    var hasCCS: Bool { connectorTypes.contains("J1772COMBO") }

    /// Estimated peak power the 2026 Ioniq 5 can draw here.
    ///
    /// NREL doesn't publish per-plug kW, so this uses the network brand as a
    /// proxy, then caps at what the car accepts: the E-GMP pack peaks around
    /// 257 kW on an 800 V CCS dispenser, but 400 V Tesla V3 Superchargers top
    /// out near 126 kW for this car.
    var estimatedPeakKWForIoniq5: Double {
        let network = network.lowercased()
        if network.contains("tesla") { return 126 }
        let siteKW: Double
        if network.contains("electrify") { siteKW = 350 }
        else if network.contains("evgo") { siteKW = 350 }
        else if network.contains("ionna") { siteKW = 400 }
        else if network.contains("chargepoint") { siteKW = 125 }
        else if network.contains("shell") { siteKW = 180 }
        else if network.contains("francis") { siteKW = 320 }   // Francis Energy
        else if network.contains("circle") { siteKW = 180 }    // Circle K
        else { siteKW = 150 }
        return min(siteKW, 257)
    }

    /// Rough quality score used to pick between candidate stops:
    /// more plugs and faster power win; NACS gets a small bump because the
    /// 2026 Ioniq 5 plugs in without an adapter.
    var stopScore: Double {
        var score = estimatedPeakKWForIoniq5
        score += Double(min(dcFastCount, 12)) * 8
        if hasNACS && !network.lowercased().contains("tesla") { score += 10 }
        return score
    }
}

// MARK: - NREL JSON decoding

extension ChargingStation {
    /// Builds a station from one entry of the NREL `fuel_stations` array.
    /// Tolerant of missing fields; returns nil only when essentials are absent.
    init?(nrelJSON entry: Any) {
        guard let id = JSONPath.int(entry, "id"),
              let lat = JSONPath.double(entry, "latitude"),
              let lon = JSONPath.double(entry, "longitude") else { return nil }
        self.id = id
        self.latitude = lat
        self.longitude = lon
        self.name = JSONPath.string(entry, "station_name") ?? "Charging Station"
        self.streetAddress = JSONPath.string(entry, "street_address") ?? ""
        self.city = JSONPath.string(entry, "city") ?? ""
        self.state = JSONPath.string(entry, "state") ?? ""
        self.network = JSONPath.string(entry, "ev_network") ?? "Non-networked"
        self.connectorTypes = (JSONPath.value(entry, "ev_connector_types") as? [Any])?
            .compactMap { $0 as? String } ?? []
        self.dcFastCount = JSONPath.int(entry, "ev_dc_fast_num") ?? 0
        self.pricing = JSONPath.string(entry, "ev_pricing")
    }
}
