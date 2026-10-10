//
//  RoutePlannerService.swift
//  BetterBlue
//
//  Directions (MapKit) + corridor chargers (NREL) + stop selection
//  (ChargeStopPlanner) → a PlannedRoute split into drivable legs.
//

import CoreLocation
import Foundation
import MapKit

enum RoutePlannerError: Error, LocalizedError {
    case noRouteFound

    var errorDescription: String? {
        "Couldn't find a driving route to that destination."
    }
}

@MainActor
final class RoutePlannerService {
    private let nrel: NRELService

    init(nrel: NRELService) {
        self.nrel = nrel
    }

    /// - Parameter origin: nil plans from the device's current location;
    ///   a coordinate is used when re-planning mid-trip.
    func planRoute(
        from origin: CLLocationCoordinate2D?,
        to destination: MKMapItem,
        startSOC: Double,
        profile: EVProfile,
        fullRangeMiles: Double
    ) async throws -> PlannedRoute {
        let source = origin.map(Self.mapItem) ?? .forCurrentLocation()
        let route = try await directions(from: source, to: destination)
        let fullPath = RoutePath(coordinates: route.polyline.coordinates)
        let destinationPlace = RoutePlace(
            name: destination.name ?? "Destination",
            coordinate: destination.location.coordinate
        )
        let startPlace = RoutePlace(
            name: origin == nil ? "Current Location" : "Here",
            coordinate: fullPath.coordinates.first ?? destinationPlace.coordinate
        )

        let planner = ChargeStopPlanner(profile: profile, fullRangeMiles: fullRangeMiles)
        let directMiles = route.distance / Geo.metersPerMile
        let canDriveDirect = (startSOC - profile.arrivalReserveSOC) * fullRangeMiles >= directMiles

        var stops: [ChargingStop] = []
        if !canDriveDirect {
            let stations = try await nrel.fetchStationsAlongRoute(fullPath, corridorMiles: planner.maxDetourMiles)
            // Planning on a ~¼-mile resampling keeps station projection cheap
            // on long routes without meaningfully moving stop positions.
            let coarse = RoutePath(coordinates: fullPath.downsampled(spacingMiles: 0.25))
            stops = try planner.planStops(along: coarse, startSOC: startSOC, stations: stations)
        }

        if stops.isEmpty {
            let miles = route.distance / Geo.metersPerMile
            return PlannedRoute(
                destination: destinationPlace,
                legs: [RouteLeg(
                    id: 0,
                    start: startPlace,
                    end: destinationPlace,
                    distanceMiles: miles,
                    driveMinutes: route.expectedTravelTime / 60,
                    coordinates: fullPath.coordinates,
                    departureSOC: startSOC,
                    arrivalSOC: startSOC - miles / fullRangeMiles,
                    endStop: nil
                )],
                stops: [],
                fullRangeMiles: fullRangeMiles,
                profile: profile,
                createdAt: .now
            )
        }

        let legs = try await buildLegs(
            source: source,
            startPlace: startPlace,
            stops: stops,
            destination: destination,
            destinationPlace: destinationPlace,
            startSOC: startSOC,
            fullRangeMiles: fullRangeMiles
        )
        return PlannedRoute(
            destination: destinationPlace,
            legs: legs,
            stops: stops,
            fullRangeMiles: fullRangeMiles,
            profile: profile,
            createdAt: .now
        )
    }

    // MARK: - Private

    /// One MapKit request per leg so each has a real polyline and ETA that
    /// includes the detour to the charger.
    private func buildLegs(
        source: MKMapItem,
        startPlace: RoutePlace,
        stops: [ChargingStop],
        destination: MKMapItem,
        destinationPlace: RoutePlace,
        startSOC: Double,
        fullRangeMiles: Double
    ) async throws -> [RouteLeg] {
        var waypoints: [(item: MKMapItem, place: RoutePlace, stop: ChargingStop?)] = stops.map { stop in
            let item = Self.mapItem(stop.station.coordinate)
            item.name = stop.station.stationName
            return (item, RoutePlace(name: stop.station.stationName, coordinate: stop.station.coordinate), stop)
        }
        waypoints.append((destination, destinationPlace, nil))

        // Sequential: a trip has a handful of legs, and MKMapItem/MKRoute
        // aren't Sendable, so fanning out buys little and costs isolation.
        var routes = [Int: LegGeometry]()
        var previous = source
        for (index, waypoint) in waypoints.enumerated() {
            let route = try await directions(from: previous, to: waypoint.item)
            routes[index] = LegGeometry(
                miles: route.distance / Geo.metersPerMile,
                minutes: route.expectedTravelTime / 60,
                coordinates: route.polyline.coordinates
            )
            previous = waypoint.item
        }

        var legs: [RouteLeg] = []
        var start = startPlace
        var departureSOC = startSOC
        for (index, waypoint) in waypoints.enumerated() {
            guard let route = routes[index] else { throw RoutePlannerError.noRouteFound }
            let miles = route.miles
            let arrivalSOC = waypoint.stop?.arrivalSOC ?? (departureSOC - miles / fullRangeMiles)
            legs.append(RouteLeg(
                id: index,
                start: start,
                end: waypoint.place,
                distanceMiles: miles,
                driveMinutes: route.minutes,
                coordinates: route.coordinates,
                departureSOC: departureSOC,
                arrivalSOC: arrivalSOC,
                endStop: waypoint.stop
            ))
            start = waypoint.place
            departureSOC = waypoint.stop?.departureSOC ?? departureSOC
        }
        return legs
    }

    private struct LegGeometry {
        let miles: Double
        let minutes: Double
        let coordinates: [CLLocationCoordinate2D]
    }

    private func directions(from source: MKMapItem, to destination: MKMapItem) async throws -> MKRoute {
        let request = MKDirections.Request()
        request.source = source
        request.destination = destination
        request.transportType = .automobile
        let response = try await MKDirections(request: request).calculate()
        guard let route = response.routes.first else { throw RoutePlannerError.noRouteFound }
        return route
    }

    private static func mapItem(_ coordinate: CLLocationCoordinate2D) -> MKMapItem {
        MKMapItem(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude), address: nil)
    }
}

extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }
}
