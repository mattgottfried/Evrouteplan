import CoreLocation
import Foundation
import MapKit

enum RoutePlannerError: LocalizedError {
    case directionsFailed(destination: String, underlying: String)
    case noChargerFound(nearMile: Double)
    case tooManyStops

    var errorDescription: String? {
        switch self {
        case .directionsFailed(let destination, let underlying):
            return "Apple Maps couldn't compute a driving route to \(destination) (\(underlying)). If Airplane Mode is on, try turning it off — routing needs Apple's servers."
        case .noChargerFound(let mile):
            return String(format: "No usable DC fast charger found near mile %.0f of the route. Try raising the corridor radius in Settings.", mile)
        case .tooManyStops:
            return "This trip needs more than 10 charging stops — check the vehicle settings."
        }
    }
}

/// Plans a driving route and inserts DC fast-charging stops sized for the
/// 2026 Ioniq 5. Greedy corridor search: drive as far as the battery safely
/// allows, pick the best charger near that point, charge, repeat.
struct RoutePlanner {
    let nrel: NRELClient

    /// `origins` are tried in order until Apple Maps returns a route —
    /// callers pass a fresh GPS fix, Apple's own current-location resolver,
    /// and the car's last known position, so one bad origin can't sink the
    /// whole plan.
    func plan(
        from origins: [MKMapItem],
        to destination: MKMapItem,
        startSOC: Double,
        settings: PlannerSettings
    ) async throws -> PlannedRoute {
        let route = try await fetchRoute(origins: origins, destination: destination)

        let path = RoutePath(polyline: route.polyline)
        let totalMiles = route.distance / 1609.344
        let destinationName = destination.name ?? "Destination"
        let destinationCoord = destination.placemark.coordinate

        var stops: [ChargingStop] = []
        var soc = min(max(startSOC, 0.02), 1.0)
        var positionMiles = 0.0
        var usedStationIDs = Set<Int>()

        while true {
            let remaining = totalMiles - positionMiles
            let reachableMiles = max(soc - settings.reserveSOC, 0) * settings.milesPerSOC

            if remaining <= reachableMiles {
                let arrivalSOC = soc - remaining / settings.milesPerSOC
                return PlannedRoute(
                    destinationName: destinationName,
                    destinationCoordinate: destinationCoord,
                    totalMiles: totalMiles,
                    driveMinutes: route.expectedTravelTime / 60.0,
                    stops: stops,
                    arrivalSOC: arrivalSOC,
                    polylineCoordinates: path.decimated(maxPoints: 500)
                )
            }

            guard stops.count < 10 else { throw RoutePlannerError.tooManyStops }

            guard let stop = try await findStop(
                path: path,
                positionMiles: positionMiles,
                reachableMiles: reachableMiles,
                totalMiles: totalMiles,
                soc: soc,
                settings: settings,
                excluding: usedStationIDs
            ) else {
                throw RoutePlannerError.noChargerFound(nearMile: positionMiles + reachableMiles)
            }

            usedStationIDs.insert(stop.station.id)
            stops.append(stop.chargingStop)
            positionMiles = stop.routeMiles
            soc = stop.chargingStop.departureSOC
        }
    }

    // MARK: - Directions

    private func fetchRoute(origins: [MKMapItem], destination: MKMapItem) async throws -> MKRoute {
        var lastErrorText = "no origins available"
        for origin in origins {
            let request = MKDirections.Request()
            request.source = origin
            request.destination = destination
            request.transportType = .automobile
            do {
                let response = try await MKDirections(request: request).calculate()
                if let route = response.routes.first { return route }
                lastErrorText = "empty route response"
            } catch {
                lastErrorText = error.localizedDescription
            }
        }
        throw RoutePlannerError.directionsFailed(
            destination: destination.name ?? "the destination",
            underlying: lastErrorText
        )
    }

    // MARK: - Stop selection

    private struct StopCandidate {
        let station: ChargingStation
        let routeMiles: Double     // distance along route where we rejoin
        let detourMiles: Double    // one-way distance off the route
        let chargingStop: ChargingStop
    }

    private func findStop(
        path: RoutePath,
        positionMiles: Double,
        reachableMiles: Double,
        totalMiles: Double,
        soc: Double,
        settings: PlannerSettings,
        excluding: Set<Int>
    ) async throws -> StopCandidate? {
        // Search near 85 % of reachable distance first, then fall back closer.
        for fraction in [0.85, 0.65, 0.45, 0.25] {
            let searchMiles = min(positionMiles + reachableMiles * fraction, totalMiles - 1)
            guard searchMiles > positionMiles + 1 else { continue }
            let searchCoord = path.coordinate(atMiles: searchMiles)

            let stations: [ChargingStation]
            do {
                stations = try await nrel.fastChargers(
                    near: searchCoord,
                    radiusMiles: settings.corridorRadiusMiles
                )
            } catch let error as NRELError {
                // Missing/invalid key should surface immediately, not read as
                // "no chargers in the area".
                throw error
            }

            let candidates: [StopCandidate] = stations.compactMap { station in
                guard !excluding.contains(station.id) else { return nil }
                let (routeMiles, detourMiles) = path.projection(of: station.coordinate)
                // Must be ahead of us and reachable with the detour included.
                let milesToStation = (routeMiles - positionMiles) + detourMiles
                guard routeMiles > positionMiles + 1,
                      milesToStation <= reachableMiles,
                      detourMiles <= settings.corridorRadiusMiles else { return nil }

                let arrivalSOC = soc - milesToStation / settings.milesPerSOC
                guard arrivalSOC >= settings.reserveSOC * 0.5 else { return nil }

                // Charge only as much as the rest of the trip needs (plus
                // reserve), capped at the fast-charge ceiling.
                let remainingAfter = (totalMiles - routeMiles) + detourMiles
                let neededSOC = remainingAfter / settings.milesPerSOC + settings.reserveSOC
                let departureSOC = min(max(neededSOC, arrivalSOC + 0.05), settings.maxChargeSOC)

                let peakKW = min(station.estimatedPeakKWForIoniq5, 257)
                let minutes = settings.chargeMinutes(
                    fromSOC: arrivalSOC, toSOC: departureSOC, stationPeakKW: peakKW
                )

                return StopCandidate(
                    station: station,
                    routeMiles: routeMiles,
                    detourMiles: detourMiles,
                    chargingStop: ChargingStop(
                        station: station,
                        legMiles: milesToStation,
                        arrivalSOC: arrivalSOC,
                        departureSOC: departureSOC,
                        chargeMinutes: minutes
                    )
                )
            }

            // Best = quality score, minus penalties for detour and for being
            // far short of the reachable horizon (which would force extra stops).
            if let best = candidates.max(by: { lhs, rhs in
                score(lhs, positionMiles: positionMiles, reachableMiles: reachableMiles)
                    < score(rhs, positionMiles: positionMiles, reachableMiles: reachableMiles)
            }) {
                return best
            }
        }
        return nil
    }

    private func score(_ c: StopCandidate, positionMiles: Double, reachableMiles: Double) -> Double {
        let progress = (c.routeMiles - positionMiles) / max(reachableMiles, 1)  // 0–1
        return c.station.stopScore + progress * 120 - c.detourMiles * 6
    }
}

// MARK: - Route geometry

/// Downsampled route polyline with cumulative mileage, for fast
/// point-at-distance and nearest-point queries.
struct RoutePath {
    let coords: [CLLocationCoordinate2D]
    let cumulativeMiles: [Double]

    init(polyline: MKPolyline) {
        var raw = [CLLocationCoordinate2D](
            repeating: kCLLocationCoordinate2DInvalid, count: polyline.pointCount
        )
        polyline.getCoordinates(&raw, range: NSRange(location: 0, length: polyline.pointCount))

        // Downsample to ~1500 points so projection stays cheap on long trips.
        let stride = max(1, raw.count / 1500)
        var sampled: [CLLocationCoordinate2D] = []
        sampled.reserveCapacity(raw.count / stride + 2)
        for i in Swift.stride(from: 0, to: raw.count, by: stride) {
            sampled.append(raw[i])
        }
        if let last = raw.last, sampled.last.map({ $0.latitude != last.latitude || $0.longitude != last.longitude }) ?? true {
            sampled.append(last)
        }

        var cumulative: [Double] = [0]
        cumulative.reserveCapacity(sampled.count)
        for i in 1..<max(sampled.count, 1) {
            cumulative.append(cumulative[i - 1] + Self.miles(sampled[i - 1], sampled[i]))
        }
        self.coords = sampled
        self.cumulativeMiles = cumulative
    }

    var totalMiles: Double { cumulativeMiles.last ?? 0 }

    func coordinate(atMiles miles: Double) -> CLLocationCoordinate2D {
        guard let first = coords.first else { return kCLLocationCoordinate2DInvalid }
        guard miles > 0 else { return first }
        for i in 1..<coords.count where cumulativeMiles[i] >= miles {
            return coords[i]
        }
        return coords.last ?? first
    }

    /// Returns (milesAlongRoute, offRouteMiles) for the closest route point.
    func projection(of coordinate: CLLocationCoordinate2D) -> (Double, Double) {
        var bestIndex = 0
        var bestDistance = Double.greatestFiniteMagnitude
        for (i, c) in coords.enumerated() {
            let d = Self.miles(c, coordinate)
            if d < bestDistance {
                bestDistance = d
                bestIndex = i
            }
        }
        return (cumulativeMiles[bestIndex], bestDistance)
    }

    func decimated(maxPoints: Int) -> [CLLocationCoordinate2D] {
        guard coords.count > maxPoints else { return coords }
        let stride = coords.count / maxPoints + 1
        var result: [CLLocationCoordinate2D] = []
        for i in Swift.stride(from: 0, to: coords.count, by: stride) {
            result.append(coords[i])
        }
        if let last = coords.last { result.append(last) }
        return result
    }

    static func miles(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude)) / 1609.344
    }
}
