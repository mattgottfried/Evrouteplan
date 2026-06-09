import BetterBlueKit
import Foundation

enum BluelinkError: Error, LocalizedError {
    case notConnected
    case noVehiclesFound
    case noEVStatus

    var errorDescription: String? {
        switch self {
        case .notConnected:     return "Not connected to BlueLink. Please sign in."
        case .noVehiclesFound:  return "No vehicles found in your BlueLink account."
        case .noEVStatus:       return "This vehicle does not report EV status."
        }
    }
}

@MainActor
@Observable
final class BluelinkService {
    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case refreshing
        case failed(String)
    }

    private(set) var connectionState: ConnectionState = .disconnected
    private(set) var currentVehicle: Vehicle?
    private(set) var vehicleStatus: VehicleStatus?

    private var apiClient: (any APIClientProtocol)?
    private var authToken: AuthToken?

    // MARK: - Public API

    var currentSOCFraction: Double? {
        vehicleStatus?.evStatus?.evRange.percentage.map { $0 / 100.0 }
    }

    var currentRangeMiles: Double? {
        guard let range = vehicleStatus?.evStatus?.evRange.range else { return nil }
        if range.units == .miles { return range.length }
        return range.length / 1.609344
    }

    var isCharging: Bool {
        vehicleStatus?.evStatus?.charging == true
    }

    var chargingKW: Double? {
        guard isCharging else { return nil }
        return vehicleStatus?.evStatus?.chargeSpeed
    }

    func connect(username: String, password: String, pin: String) async {
        connectionState = .connecting

        // NOTE: If the compiler reports unknown members on APIClientConfiguration,
        // check the installed BetterBlueKit version — the brand/region enum cases
        // may use slightly different names (e.g. .hyundaiUSA vs brand:.hyundai + region:.usa).
        let config = APIClientConfiguration(
            brand: .hyundai,
            region: .usa,
            username: username,
            password: password,
            pin: pin
        )

        do {
            let client = createBetterBlueKitAPIClient(configuration: config)
            let token = try await client.login()
            let vehicles = try await client.fetchVehicles(authToken: token)

            guard let vehicle = vehicles.first else { throw BluelinkError.noVehiclesFound }

            self.apiClient = client
            self.authToken = token
            self.currentVehicle = vehicle
            self.connectionState = .connected

            try await refreshStatus()
        } catch {
            connectionState = .failed(error.localizedDescription)
        }
    }

    func refreshStatus() async throws {
        guard let client = apiClient, let vehicle = currentVehicle else {
            throw BluelinkError.notConnected
        }
        connectionState = .refreshing
        defer {
            if case .refreshing = connectionState { connectionState = .connected }
        }
        // README example: client.fetchVehicleStatus(for: vehicle)
        // Token is managed internally by the client after login().
        vehicleStatus = try await client.fetchVehicleStatus(for: vehicle)
    }

    func disconnect() {
        apiClient = nil
        authToken = nil
        currentVehicle = nil
        vehicleStatus = nil
        connectionState = .disconnected
    }
}
