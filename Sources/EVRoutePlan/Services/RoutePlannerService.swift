import CoreLocation
import Foundation
import MapKit

enum RoutePlannerError: Error, LocalizedError {
    case noRouteFound
    case destinationUnreachable

    var errorDescription: String? {
        switch self {
        case .noRouteFound:           return "Could not find a driving route to the destination."
        case .destinationUnreachable: return "Could not plan a route: no charging stations found along the way."
        }
    }
}

@MainActor
final class RoutePlannerService {
    private let nrelService: NRELService

    init(nrelService: NRELService) {
        self.nrelService = nrelService
    }

    func planRoute(
        to destination: MKMapItem,
        currentSOCFraction: Double,
        variant: Ioniq5Config.Variant
    ) async throws -> PlannedRoute {
        let route = try await fetchRoute(to: destination)
        let totalMiles = route.distance / 1609.344
        let coords = route.polyline.coordinates
        let destInfo = DestinationInfo(
            name: destination.name ?? "Destination",
            coordinate: destination.placemark.coordinate
        )

        let availableMiles = currentSOCFraction * variant.epaRangeMiles
        if totalMiles <= availableMiles * Ioniq5Config.arrivalBufferFactor {
            return PlannedRoute(
                destination: destInfo,
                totalDistanceMiles: totalMiles,
                stops: [],
                estimatedDriveMinutes: route.expectedTravelTime / 60.0,
                estimatedChargeMinutes: 0,
                routeCoordinates: coords
            )
        }

        let stops = try await insertChargingStops(
            along: coords,
            totalMiles: totalMiles,
            startSOC: currentSOCFraction,
            variant: variant
        )

        let totalChargeMins = stops.reduce(0) { $0 + $1.estimatedChargeTimeMinutes }

        return PlannedRoute(
            destination: destInfo,
            totalDistanceMiles: totalMiles,
            stops: stops,
            estimatedDriveMinutes: route.expectedTravelTime / 60.0,
            estimatedChargeMinutes: totalChargeMins,
            routeCoordinates: coords
        )
    }

    // MARK: - Private

    private func fetchRoute(to destination: MKMapItem) async throws -> MKRoute {
        let request = MKDirections.Request()
        request.source = .forCurrentLocation()
        request.destination = destination
        request.transportType = .automobile
        let response = try await MKDirections(request: request).calculate()
        guard let route = response.routes.first else { throw RoutePlannerError.noRouteFound }
        return route
    }

    private func insertChargingStops(
        along coords: [CLLocationCoordinate2D],
        totalMiles: Double,
        startSOC: Double,
        variant: Ioniq5Config.Variant
    ) async throws -> [ChargingStop] {
        var stops: [ChargingStop] = []
        var usedIDs = Set<Int>()
        var currentSOC = startSOC
        var previousCoord = coords.first ?? CLLocationCoordinate2D()
        var totalAccumulatedMiles = 0.0  // from route start
        var milesSinceLastStop = 0.0

        for coord in coords.dropFirst() {
            let stepMiles = distance(from: previousCoord, to: coord)
            totalAccumulatedMiles += stepMiles
            milesSinceLastStop += stepMiles
            previousCoord = coord

            let remainingMiles = totalMiles - totalAccumulatedMiles
            let rangeAvailableMiles = currentSOC * variant.epaRangeMiles

            // Can we reach the destination from here with the safety buffer?
            if remainingMiles <= rangeAvailableMiles * Ioniq5Config.arrivalBufferFactor {
                break
            }

            // Trigger a charging stop when we've used segmentFactor of current range.
            let segmentThreshold = currentSOC * variant.epaRangeMiles * Ioniq5Config.segmentFactor
            guard milesSinceLastStop >= segmentThreshold else { continue }

            let arrivalSOC = max(currentSOC - milesSinceLastStop / variant.epaRangeMiles, 0.05)

            guard let station = try await bestStation(near: coord, excluding: usedIDs) else {
                continue
            }
            usedIDs.insert(station.id)

            let chargeTime = estimateChargeMinutes(
                fromSOC: arrivalSOC,
                toSOC: Ioniq5Config.defaultTargetSOC,
                chargerKW: station.estimatedMaxKW,
                batteryKWh: variant.batteryKWh
            )

            stops.append(ChargingStop(
                station: station,
                arrivalSOC: arrivalSOC,
                estimatedChargeTimeMinutes: chargeTime,
                distanceFromPreviousMiles: milesSinceLastStop
            ))

            // Reset for next segment using the departure SOC (80%).
            currentSOC = Ioniq5Config.defaultTargetSOC
            milesSinceLastStop = 0.0
        }

        return stops
    }

    private func bestStation(
        near coord: CLLocationCoordinate2D,
        excluding used: Set<Int>
    ) async throws -> ChargingStation? {
        let stations = try await nrelService.fetchCCSStations(near: coord)
        let here = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        return stations
            .filter { !used.contains($0.id) && $0.estimatedMaxKW >= Ioniq5Config.minimumDCFastKW }
            .min {
                let da = CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: here)
                let db = CLLocation(latitude: $1.latitude, longitude: $1.longitude).distance(from: here)
                return da < db
            }
    }

    private func estimateChargeMinutes(
        fromSOC: Double,
        toSOC: Double,
        chargerKW: Double,
        batteryKWh: Double
    ) -> Double {
        guard toSOC > fromSOC, chargerKW > 0 else { return 0 }
        return (toSOC - fromSOC) * batteryKWh / chargerKW * 60.0
    }

    private func distance(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude)) / 1609.344
    }
}

// MARK: - MKPolyline helpers

extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](
            repeating: kCLLocationCoordinate2DInvalid,
            count: pointCount
        )
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }
}
