import CoreLocation
import Foundation

enum NRELError: Error, LocalizedError {
    case missingAPIKey
    case badResponse(Int)
    case noStationsFound

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:       return "NREL API key is missing. Add it to Secrets.xcconfig."
        case .badResponse(let c):  return "NREL API returned HTTP \(c)."
        case .noStationsFound:     return "No CCS fast chargers found in this area."
        }
    }
}

actor NRELService {
    private let apiKey: String
    private let session: URLSession

    private static let baseURL = "https://developer.nrel.gov/api/alt-fuel-stations/v1.json"

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    func fetchCCSStations(
        near coordinate: CLLocationCoordinate2D,
        radiusMiles: Double = Ioniq5Config.corridorRadiusMiles
    ) async throws -> [ChargingStation] {
        guard !apiKey.isEmpty, apiKey != "YOUR_NREL_API_KEY_HERE" else {
            throw NRELError.missingAPIKey
        }

        var components = URLComponents(string: Self.baseURL)!
        components.queryItems = [
            URLQueryItem(name: "api_key",            value: apiKey),
            URLQueryItem(name: "fuel_type",          value: "ELEC"),
            URLQueryItem(name: "ev_connector_types", value: "CCS"),
            URLQueryItem(name: "status",             value: "E"),
            URLQueryItem(name: "access",             value: "public"),
            URLQueryItem(name: "latitude",           value: String(coordinate.latitude)),
            URLQueryItem(name: "longitude",          value: String(coordinate.longitude)),
            URLQueryItem(name: "radius",             value: String(radiusMiles)),
            URLQueryItem(name: "limit",              value: "30"),
        ]

        let (data, response) = try await session.data(from: components.url!)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw NRELError.badResponse(status) }

        let decoded = try JSONDecoder().decode(NRELResponse.self, from: data)
        return decoded.altFuelStations.filter { $0.hasDCFast && $0.accessCode == "public" }
    }
}
