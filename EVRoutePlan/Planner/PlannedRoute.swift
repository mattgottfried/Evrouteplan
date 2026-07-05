import CoreLocation
import Foundation

/// A destination the user has planned to before, for one-tap replanning.
struct RecentDestination: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    let name: String
    let subtitle: String
    let latitude: Double
    let longitude: Double
}

struct ChargingStop: Identifiable, Sendable {
    let id = UUID()
    let station: ChargingStation
    /// Distance driven since the previous stop (or the start), miles.
    let legMiles: Double
    /// Predicted state of charge on arrival at this station (0–1).
    let arrivalSOC: Double
    /// State of charge to leave with (0–1).
    let departureSOC: Double
    /// Estimated time plugged in, minutes.
    let chargeMinutes: Double
}

struct PlannedRoute: Sendable {
    let destinationName: String
    let destinationCoordinate: CLLocationCoordinate2D
    let totalMiles: Double
    let driveMinutes: Double
    let stops: [ChargingStop]
    /// Predicted SOC on arrival at the final destination (0–1).
    let arrivalSOC: Double
    /// Route geometry for the map, decimated.
    let polylineCoordinates: [CLLocationCoordinate2D]
    let plannedAt = Date()

    var chargeMinutes: Double { stops.reduce(0) { $0 + $1.chargeMinutes } }
    var totalMinutes: Double { driveMinutes + chargeMinutes }
    var needsCharging: Bool { !stops.isEmpty }
}
