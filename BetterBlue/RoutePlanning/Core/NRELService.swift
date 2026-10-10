//
//  NRELService.swift
//  BetterBlue
//
//  NREL Alternative Fuel Stations API — public CCS DC fast chargers.
//  https://developer.nrel.gov/docs/transportation/alt-fuel-stations-v1/
//

import CoreLocation
import Foundation

enum NRELError: Error, LocalizedError {
    case missingAPIKey
    case badResponse(Int)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Add an NREL API key in Settings › Route Planning (free at developer.nrel.gov/signup)."
        case .badResponse(let code):
            code == 403 || code == 401
                ? "The NREL API key was rejected. Check it in Settings › Route Planning."
                : "The charger database returned HTTP \(code)."
        }
    }
}

actor NRELService {
    private static let baseURL = URL(string: "https://developer.nrel.gov/api/alt-fuel-stations/v1/")!

    private let apiKey: String
    private let session: URLSession

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    /// Chargers within `radiusMiles` of a point, nearest first.
    func fetchStations(
        near coordinate: CLLocationCoordinate2D,
        radiusMiles: Double = 25,
        limit: Int = 30
    ) async throws -> [ChargingStation] {
        var components = URLComponents(
            url: Self.baseURL.appendingPathComponent("nearest.json"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = try commonQuery() + [
            URLQueryItem(name: "latitude", value: String(coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(coordinate.longitude)),
            URLQueryItem(name: "radius", value: String(radiusMiles)),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        return try await decode(URLRequest(url: components.url!))
    }

    /// Every charger within `corridorMiles` of the route, in one request.
    func fetchStationsAlongRoute(
        _ path: RoutePath,
        corridorMiles: Double = 5
    ) async throws -> [ChargingStation] {
        // NREL caps the request size; a point every ~2 mi keeps a
        // cross-country route well under it while staying within the
        // corridor's tolerance.
        let spacing = max(2, path.totalMiles / 1500)
        let points = path.downsampled(spacingMiles: spacing)
            .map { String(format: "%.5f %.5f", $0.longitude, $0.latitude) }
            .joined(separator: ", ")

        var components = URLComponents(
            url: Self.baseURL.appendingPathComponent("nearby-route.json"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = try commonQuery() + [
            URLQueryItem(name: "distance", value: String(corridorMiles)),
            URLQueryItem(name: "limit", value: "all"),
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = [URLQueryItem(name: "route", value: "LINESTRING(\(points))")]
        request.httpBody = body.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
            .data(using: .utf8)
        return try await decode(request)
    }

    // MARK: - Private

    private func commonQuery() throws -> [URLQueryItem] {
        guard !apiKey.isEmpty else { throw NRELError.missingAPIKey }
        return [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "fuel_type", value: "ELEC"),
            URLQueryItem(name: "ev_charging_level", value: "dc_fast"),
            URLQueryItem(name: "ev_connector_type", value: "J1772COMBO"),
            URLQueryItem(name: "status", value: "E"),
            URLQueryItem(name: "access", value: "public"),
        ]
    }

    private func decode(_ request: URLRequest) async throws -> [ChargingStation] {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw NRELError.badResponse(status) }
        return try JSONDecoder().decode(NRELResponse.self, from: data)
            .stations
            .filter { $0.hasDCFast && $0.isPublic }
    }
}
