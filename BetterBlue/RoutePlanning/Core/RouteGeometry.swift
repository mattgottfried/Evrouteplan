//
//  RouteGeometry.swift
//  BetterBlue
//
//  Pure polyline math shared by the charge-stop planner and the live trip
//  tracker: distances along a route, snapping a GPS fix onto it, and
//  downsampling for API queries. No MapKit, no networking — unit tested.
//

import CoreLocation
import Foundation

enum Geo {
    static let metersPerMile = 1609.344
    private static let earthRadiusMiles = 3958.7613

    /// Great-circle distance in miles.
    static func miles(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadiusMiles * asin(min(1, sqrt(h)))
    }
}

/// A route polyline with precomputed cumulative distances, so "how far along
/// is this point" and "where is mile N" are cheap.
struct RoutePath: Sendable {
    let coordinates: [CLLocationCoordinate2D]
    /// `cumulativeMiles[i]` = distance from the start to `coordinates[i]`.
    let cumulativeMiles: [Double]

    init(coordinates: [CLLocationCoordinate2D]) {
        self.coordinates = coordinates
        var cumulative = [Double]()
        cumulative.reserveCapacity(coordinates.count)
        var total = 0.0
        for (i, coord) in coordinates.enumerated() {
            if i > 0 { total += Geo.miles(coordinates[i - 1], coord) }
            cumulative.append(total)
        }
        self.cumulativeMiles = cumulative
    }

    var totalMiles: Double { cumulativeMiles.last ?? 0 }
    var isEmpty: Bool { coordinates.count < 2 }

    /// Where a point sits relative to the route.
    struct Projection: Equatable, Sendable {
        /// Distance along the route of the closest point on it.
        var routeMile: Double
        /// Perpendicular distance from the route, in miles.
        var offsetMiles: Double
        /// Index of the segment start the point projected onto.
        var segmentIndex: Int
    }

    /// Projects `point` onto the route. `searchRange` limits which segments
    /// are considered — the trip tracker passes a window around the last
    /// match so each fix costs O(window) instead of O(route).
    func project(
        _ point: CLLocationCoordinate2D,
        searchRange: Range<Int>? = nil
    ) -> Projection? {
        guard !isEmpty else { return nil }
        let lastSegment = coordinates.count - 1
        let range = (searchRange ?? 0..<lastSegment).clamped(to: 0..<lastSegment)
        guard !range.isEmpty else { return nil }

        var best: Projection?
        // Equirectangular projection around the point — accurate to well
        // under 1% at the segment lengths MapKit returns (tens to hundreds
        // of meters), and far cheaper than spherical cross-track math.
        let cosLat = cos(point.latitude * .pi / 180)
        func xy(_ c: CLLocationCoordinate2D) -> (Double, Double) {
            ((c.longitude - point.longitude) * cosLat, c.latitude - point.latitude)
        }

        for i in range {
            let a = coordinates[i], b = coordinates[i + 1]
            let (ax, ay) = xy(a), (bx, by) = xy(b)
            let dx = bx - ax, dy = by - ay
            let lengthSq = dx * dx + dy * dy
            var t = lengthSq > 0 ? -(ax * dx + ay * dy) / lengthSq : 0
            t = min(1, max(0, t))
            let foot = CLLocationCoordinate2D(
                latitude: a.latitude + (b.latitude - a.latitude) * t,
                longitude: a.longitude + (b.longitude - a.longitude) * t
            )
            let offset = Geo.miles(point, foot)
            if best == nil || offset < best!.offsetMiles {
                let segmentMiles = cumulativeMiles[i + 1] - cumulativeMiles[i]
                best = Projection(
                    routeMile: cumulativeMiles[i] + segmentMiles * t,
                    offsetMiles: offset,
                    segmentIndex: i
                )
            }
        }
        return best
    }

    /// Coordinate at a distance along the route.
    func coordinate(atMile mile: Double) -> CLLocationCoordinate2D? {
        guard let first = coordinates.first else { return nil }
        if mile <= 0 { return first }
        guard let upper = cumulativeMiles.firstIndex(where: { $0 >= mile }) else {
            return coordinates.last
        }
        if upper == 0 { return first }
        let lower = upper - 1
        let span = cumulativeMiles[upper] - cumulativeMiles[lower]
        let t = span > 0 ? (mile - cumulativeMiles[lower]) / span : 0
        let a = coordinates[lower], b = coordinates[upper]
        return CLLocationCoordinate2D(
            latitude: a.latitude + (b.latitude - a.latitude) * t,
            longitude: a.longitude + (b.longitude - a.longitude) * t
        )
    }

    /// Roughly one point every `spacingMiles`, always keeping both ends.
    /// Used to keep the NREL corridor query's WKT linestring small.
    func downsampled(spacingMiles: Double) -> [CLLocationCoordinate2D] {
        guard let first = coordinates.first, let last = coordinates.last else { return [] }
        var result = [first]
        var nextMile = spacingMiles
        for (i, coord) in coordinates.enumerated().dropFirst() where cumulativeMiles[i] >= nextMile {
            result.append(coord)
            nextMile = cumulativeMiles[i] + spacingMiles
        }
        if result.count == 1 || !Self.same(result.last!, last) { result.append(last) }
        return result
    }

    private static func same(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Bool {
        a.latitude == b.latitude && a.longitude == b.longitude
    }
}
