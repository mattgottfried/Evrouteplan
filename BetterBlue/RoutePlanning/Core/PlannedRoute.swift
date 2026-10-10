//
//  PlannedRoute.swift
//  BetterBlue
//

import CoreLocation
import Foundation

struct RoutePlace: Sendable {
    let name: String
    let coordinate: CLLocationCoordinate2D
}

struct ChargingStop: Identifiable, Sendable {
    var id: Int { station.id }
    let station: ChargingStation
    /// Distance along the original route where the stop branches off.
    let routeMile: Double
    /// One-way distance from the route to the station.
    let detourMiles: Double
    let arrivalSOC: Double
    let departureSOC: Double
    let chargeMinutes: Double
    let distanceFromPreviousMiles: Double
}

/// One drive between consecutive places (start → stop 1 → … → destination),
/// handed to the maps app one at a time.
struct RouteLeg: Identifiable, Sendable {
    let id: Int
    let start: RoutePlace
    let end: RoutePlace
    let distanceMiles: Double
    let driveMinutes: Double
    let coordinates: [CLLocationCoordinate2D]
    /// SOC on leaving `start` and on reaching `end`.
    let departureSOC: Double
    let arrivalSOC: Double
    /// The charging stop at `end`, nil for the final leg.
    let endStop: ChargingStop?
}

struct PlannedRoute: Sendable {
    let destination: RoutePlace
    let legs: [RouteLeg]
    let stops: [ChargingStop]
    let fullRangeMiles: Double
    let profile: EVProfile
    let createdAt: Date

    var totalDistanceMiles: Double { legs.reduce(0) { $0 + $1.distanceMiles } }
    var driveMinutes: Double { legs.reduce(0) { $0 + $1.driveMinutes } }
    var chargeMinutes: Double { stops.reduce(0) { $0 + $1.chargeMinutes } }
    var totalMinutes: Double { driveMinutes + chargeMinutes }
    var requiresCharging: Bool { !stops.isEmpty }
    var arrivalSOC: Double { legs.last?.arrivalSOC ?? 0 }
    var coordinates: [CLLocationCoordinate2D] { legs.flatMap(\.coordinates) }
}

enum RouteFormat {
    static func duration(minutes: Double) -> String {
        let total = Int(minutes.rounded())
        let h = total / 60, m = total % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    static func percent(_ soc: Double) -> String {
        "\(Int((soc * 100).rounded()))%"
    }
}
