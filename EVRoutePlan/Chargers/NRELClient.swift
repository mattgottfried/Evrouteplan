import CoreLocation
import Foundation

enum NRELError: LocalizedError {
    case missingAPIKey
    case httpError(Int)
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No NREL API key set. Get a free key at developer.nlr.gov/signup and paste it in Settings."
        case .httpError(let code):
            return code == 403
                ? "NREL rejected the API key (HTTP 403). Check the key in Settings."
                : "NREL station lookup failed (HTTP \(code))."
        case .malformedResponse:
            return "NREL returned an unexpected response."
        }
    }
}

/// Fetches public DC fast chargers usable by a 2026 Ioniq 5 (native NACS
/// port + CCS adapter) from the NREL Alternative Fuel Station API.
actor NRELClient {
    private let session: URLSession
    private var cache: [String: [ChargingStation]] = [:]

    /// Read from UserDefaults each call so a key pasted in Settings takes
    /// effect immediately.
    private var apiKey: String {
        UserDefaults.standard.string(forKey: "nrelAPIKey")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        session = URLSession(configuration: config)
    }

    func fastChargers(
        near coordinate: CLLocationCoordinate2D,
        radiusMiles: Double,
        limit: Int = 60
    ) async throws -> [ChargingStation] {
        guard !apiKey.isEmpty else { throw NRELError.missingAPIKey }

        // ~7 km grid cache key so repeated corridor queries don't refetch.
        let cacheKey = String(format: "%.1f,%.1f,%.0f", coordinate.latitude, coordinate.longitude, radiusMiles)
        if let cached = cache[cacheKey] { return cached }

        // The API portal moved from developer.nrel.gov to developer.nlr.gov
        // (May 2026). Try the current domain first; fall back to the legacy
        // one so lookups survive the transition in either direction. Both
        // are CISA-verified .gov domains.
        let hosts = ["developer.nlr.gov", "developer.nrel.gov"]
        var data = Data()
        var succeeded = false
        var lastError: Error = NRELError.malformedResponse

        for host in hosts {
            var components = URLComponents(string: "https://\(host)/api/alt-fuel-stations/v1/nearest.json")!
            components.queryItems = [
                URLQueryItem(name: "api_key", value: apiKey),
                URLQueryItem(name: "latitude", value: String(coordinate.latitude)),
                URLQueryItem(name: "longitude", value: String(coordinate.longitude)),
                URLQueryItem(name: "radius", value: String(radiusMiles)),
                URLQueryItem(name: "fuel_type", value: "ELEC"),
                URLQueryItem(name: "ev_charging_level", value: "dc_fast"),
                URLQueryItem(name: "ev_connector_type", value: "J1772COMBO,TESLA"),
                URLQueryItem(name: "status", value: "E"),
                URLQueryItem(name: "access", value: "public"),
                URLQueryItem(name: "limit", value: String(limit)),
            ]
            do {
                let (body, response) = try await session.data(from: components.url!)
                guard let http = response as? HTTPURLResponse else { throw NRELError.malformedResponse }
                guard (200..<300).contains(http.statusCode) else {
                    throw NRELError.httpError(http.statusCode)
                }
                data = body
                succeeded = true
                break
            } catch {
                lastError = error  // unreachable host or error — try the next
            }
        }
        guard succeeded else { throw lastError }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NRELError.malformedResponse
        }
        // Response key is "fuel_stations"; accept the legacy name too.
        let entries = (json["fuel_stations"] ?? json["alt_fuel_stations"]) as? [Any] ?? []

        // Re-filter client-side so a server-side filter quirk can't slip
        // through: public, DC fast plugs present, connector the car can use.
        let stations = entries
            .compactMap { ChargingStation(nrelJSON: $0) }
            .filter { station in
                station.dcFastCount > 0 && (station.hasCCS || station.hasNACS)
            }

        cache[cacheKey] = stations
        return stations
    }

    func clearCache() {
        cache.removeAll()
    }
}
