//
//  LegProgressTracker.swift
//  BetterBlue
//
//  Matches GPS fixes to the current leg's polyline: progress along it,
//  off-route detection with hysteresis, and arrival at the leg's end.
//  Pure value type — unit tested with synthetic fixes.
//

import CoreLocation
import Foundation

struct LegProgressTracker: Sendable {
    /// Farther than this from the route counts as an off-route fix (~400 m).
    static let offRouteMiles = 0.25
    /// Consecutive off-route fixes before declaring the driver off route —
    /// absorbs GPS jitter and urban-canyon multipath.
    static let offRouteFixesRequired = 3
    /// Within this of the leg's end counts as arrived (~150 m).
    static let arrivalMiles = 0.093

    let path: RoutePath
    private(set) var progressMiles = 0.0
    private(set) var offsetMiles = 0.0
    private(set) var isOffRoute = false
    private(set) var hasArrived = false
    private var lastSegment = 0
    private var offRouteStreak = 0

    init(path: RoutePath) {
        self.path = path
    }

    var remainingMiles: Double { max(0, path.totalMiles - progressMiles) }

    mutating func update(with fix: CLLocationCoordinate2D) {
        guard !path.isEmpty else { return }

        // Search a window around the last match first (cheap); fall back to
        // the whole leg when that window doesn't contain the fix, e.g. after
        // a tunnel or a GPS jump.
        let window = max(0, lastSegment - 20)..<(lastSegment + 400)
        var projection = path.project(fix, searchRange: window)
        if projection == nil || projection!.offsetMiles > Self.offRouteMiles {
            if let full = path.project(fix), full.offsetMiles < (projection?.offsetMiles ?? .infinity) {
                projection = full
            }
        }
        guard let projection else { return }

        offsetMiles = projection.offsetMiles
        if projection.offsetMiles > Self.offRouteMiles {
            offRouteStreak += 1
        } else {
            offRouteStreak = 0
            lastSegment = projection.segmentIndex
            progressMiles = projection.routeMile
        }
        isOffRoute = offRouteStreak >= Self.offRouteFixesRequired

        if let end = path.coordinates.last, Geo.miles(fix, end) <= Self.arrivalMiles {
            hasArrived = true
        }
    }
}
