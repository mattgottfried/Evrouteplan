//
//  ChargeStopPlannerTests.swift
//  BetterBlueTests
//

import CoreLocation
import Testing
@testable import BetterBlue

/// A straight north-south route along a meridian: 1° latitude ≈ 69.09 mi.
private func straightRoute(miles: Double, step: Double = 1) -> RoutePath {
    let degreesPerMile = 1 / 69.09
    let points = stride(from: 0.0, through: miles, by: step).map {
        CLLocationCoordinate2D(latitude: 35 + $0 * degreesPerMile, longitude: -100)
    }
    return RoutePath(coordinates: points)
}

private func station(
    id: Int,
    atMile mile: Double,
    offsetMiles: Double = 0.5,
    network: String? = "Electrify America",
    dcFast: Int? = 4,
    access: String? = "public"
) -> ChargingStation {
    ChargingStation(
        id: id,
        stationName: "Station \(id)",
        streetAddress: "1 Main St",
        city: "Town",
        state: "TX",
        zip: "00000",
        latitude: 35 + mile / 69.09,
        longitude: -100 + offsetMiles / (69.09 * cos(35 * .pi / 180)),
        evNetwork: network,
        evConnectorTypes: ["J1772COMBO"],
        evDcFastNum: dcFast,
        accessCode: access
    )
}

private let profile = EVProfile(
    name: "Test", usableBatteryKWh: 80, ratedRangeMiles: 300, maxDCKW: 250
)

@Suite("RoutePath geometry")
struct RoutePathTests {
    @Test func totalDistanceMatchesStraightLine() {
        let path = straightRoute(miles: 100)
        #expect(abs(path.totalMiles - 100) < 0.5)
    }

    @Test func projectsOffsetPointOntoRoute() throws {
        let path = straightRoute(miles: 100)
        let p = try #require(path.project(station(id: 1, atMile: 42, offsetMiles: 2).coordinate))
        #expect(abs(p.routeMile - 42) < 0.3)
        #expect(abs(p.offsetMiles - 2) < 0.1)
    }

    @Test func searchWindowLimitsSegments() throws {
        let path = straightRoute(miles: 100)
        let point = station(id: 1, atMile: 80, offsetMiles: 0).coordinate
        let windowed = try #require(path.project(point, searchRange: 0..<20))
        #expect(windowed.routeMile <= 20.5)
        #expect(windowed.offsetMiles > 50)
    }

    @Test func coordinateAtMileInterpolates() throws {
        let path = straightRoute(miles: 10)
        let c = try #require(path.coordinate(atMile: 5.5))
        #expect(abs(c.latitude - (35 + 5.5 / 69.09)) < 0.001)
    }

    @Test func downsampleKeepsEndpoints() {
        let path = straightRoute(miles: 100, step: 0.1)
        let sampled = path.downsampled(spacingMiles: 10)
        #expect(sampled.count >= 10 && sampled.count <= 12)
        #expect(sampled.first?.latitude == path.coordinates.first?.latitude)
        #expect(sampled.last?.latitude == path.coordinates.last?.latitude)
    }
}

@Suite("Charge stop planning")
struct ChargeStopPlannerTests {
    let planner = ChargeStopPlanner(profile: profile, fullRangeMiles: 300)

    @Test func noStopsWhenInRange() throws {
        let stops = try planner.planStops(along: straightRoute(miles: 150), startSOC: 0.8, stations: [])
        #expect(stops.isEmpty)
    }

    @Test func singleStopOnMediumTrip() throws {
        // 0.8 SOC → 210 mi usable before 10 % reserve; trip is 350 mi.
        let stations = [station(id: 1, atMile: 60), station(id: 2, atMile: 150), station(id: 3, atMile: 190)]
        let stops = try planner.planStops(along: straightRoute(miles: 350), startSOC: 0.8, stations: stations)
        #expect(stops.count == 1)
        let stop = try #require(stops.first)
        #expect(stop.station.id != 1, "should not stop needlessly early")
        #expect(stop.arrivalSOC >= profile.arrivalReserveSOC)
        // Last stop only charges what's needed to finish (+ margin), not to 80 %.
        #expect(stop.departureSOC < profile.targetSOC)
    }

    @Test func multipleStopsOnLongTrip() throws {
        let stations = stride(from: 40.0, through: 760, by: 40).enumerated().map {
            station(id: $0.offset, atMile: $0.element)
        }
        let stops = try planner.planStops(along: straightRoute(miles: 800), startSOC: 0.9, stations: stations)
        #expect(stops.count >= 3)
        for stop in stops {
            #expect(stop.arrivalSOC >= profile.arrivalReserveSOC - 0.001)
            #expect(stop.departureSOC <= profile.targetSOC + 0.001)
        }
        #expect(zip(stops, stops.dropFirst()).allSatisfy { $0.routeMile < $1.routeMile })
    }

    @Test func prefersFasterChargerInWindow() throws {
        let stations = [
            station(id: 1, atMile: 180, network: "ChargePoint Network"),
            station(id: 2, atMile: 170, network: "Electrify America"),
        ]
        let stops = try planner.planStops(along: straightRoute(miles: 300), startSOC: 0.8, stations: stations)
        #expect(stops.first?.station.id == 2)
    }

    @Test func gapInCorridorThrows() {
        let stations = [station(id: 1, atMile: 500)]
        #expect(throws: ChargeStopPlannerError.self) {
            try planner.planStops(along: straightRoute(miles: 700), startSOC: 0.8, stations: stations)
        }
    }

    @Test func ignoresPrivateSlowAndFarStations() throws {
        let stations = [
            station(id: 1, atMile: 150, access: "private"),
            station(id: 2, atMile: 150, dcFast: 0),
            station(id: 3, atMile: 150, offsetMiles: 20),
            station(id: 4, atMile: 140),
        ]
        let stops = try planner.planStops(along: straightRoute(miles: 300), startSOC: 0.8, stations: stations)
        #expect(stops.map(\.station.id) == [4])
    }
}

@Suite("Charge time estimation")
struct ChargeTimeTests {
    let planner = ChargeStopPlanner(profile: profile, fullRangeMiles: 300)

    @Test func belowKneeUsesNearPeakPower() {
        // 0.6 × 80 kWh / (250 kW × 0.85) = 0.2259 h = 13.55 min
        let minutes = planner.estimateChargeMinutes(fromSOC: 0.2, toSOC: 0.8, stationKW: 350)
        #expect(abs(minutes - 13.55) < 0.05)
    }

    @Test func slowerAboveKnee() {
        let below = planner.estimateChargeMinutes(fromSOC: 0.6, toSOC: 0.7, stationKW: 250)
        let above = planner.estimateChargeMinutes(fromSOC: 0.8, toSOC: 0.9, stationKW: 250)
        #expect(above > below * 2)
    }

    @Test func cappedByCarMaxPower() {
        let at350 = planner.estimateChargeMinutes(fromSOC: 0.2, toSOC: 0.8, stationKW: 350)
        let at250 = planner.estimateChargeMinutes(fromSOC: 0.2, toSOC: 0.8, stationKW: 250)
        #expect(at350 == at250)
    }

    @Test func zeroWhenNoChargeNeeded() {
        #expect(planner.estimateChargeMinutes(fromSOC: 0.8, toSOC: 0.8, stationKW: 150) == 0)
    }
}

@Suite("EV profile")
struct EVProfileTests {
    @Test func liveRangeDerivesFullRange() {
        #expect(profile.fullRangeMiles(liveRangeMiles: 140, livePercent: 50) == 280)
    }

    @Test func implausibleLiveRangeFallsBack() {
        #expect(profile.fullRangeMiles(liveRangeMiles: 10, livePercent: 50) == 300)
        #expect(profile.fullRangeMiles(liveRangeMiles: 20, livePercent: 5) == 300)
        #expect(profile.fullRangeMiles(liveRangeMiles: nil, livePercent: nil) == 300)
    }

    @Test func presetFromModelName() {
        #expect(EVProfile.defaultPreset(forModel: "IONIQ 5").name.hasPrefix("Ioniq 5"))
        #expect(EVProfile.defaultPreset(forModel: "EV9").name.hasPrefix("EV9"))
        #expect(EVProfile.defaultPreset(forModel: "Kona Electric").name.hasPrefix("Kona"))
    }

    @Test func networkPowerEstimates() {
        #expect(station(id: 1, atMile: 0, network: "Electrify America").estimatedMaxKW == 350)
        #expect(station(id: 1, atMile: 0, network: "Tesla").estimatedMaxKW == 250)
        #expect(station(id: 1, atMile: 0, network: nil).estimatedMaxKW == ChargingStation.minimumDCFastKW)
    }
}

@Suite("Leg progress tracking")
struct LegProgressTrackerTests {
    private func fix(atMile mile: Double, offsetMiles: Double = 0) -> CLLocationCoordinate2D {
        station(id: 0, atMile: mile, offsetMiles: offsetMiles).coordinate
    }

    @Test func tracksProgressAlongLeg() {
        var tracker = LegProgressTracker(path: straightRoute(miles: 50))
        for mile in stride(from: 0.0, through: 20, by: 2) {
            tracker.update(with: fix(atMile: mile, offsetMiles: 0.01))
        }
        #expect(abs(tracker.progressMiles - 20) < 0.3)
        #expect(abs(tracker.remainingMiles - 30) < 0.5)
        #expect(!tracker.isOffRoute && !tracker.hasArrived)
    }

    @Test func offRouteNeedsConsecutiveFixes() {
        var tracker = LegProgressTracker(path: straightRoute(miles: 50))
        tracker.update(with: fix(atMile: 10))
        tracker.update(with: fix(atMile: 11, offsetMiles: 1))
        tracker.update(with: fix(atMile: 12, offsetMiles: 1))
        #expect(!tracker.isOffRoute, "two jittery fixes shouldn't trigger")
        tracker.update(with: fix(atMile: 13, offsetMiles: 1))
        #expect(tracker.isOffRoute)
        #expect(abs(tracker.progressMiles - 10) < 0.3, "progress holds while off route")
        tracker.update(with: fix(atMile: 14))
        #expect(!tracker.isOffRoute, "back on route clears it")
    }

    @Test func recoversAfterJumpOutsideWindow() {
        var tracker = LegProgressTracker(path: straightRoute(miles: 800, step: 0.5))
        tracker.update(with: fix(atMile: 1))
        tracker.update(with: fix(atMile: 600))
        #expect(abs(tracker.progressMiles - 600) < 0.5)
    }

    @Test func detectsArrival() {
        var tracker = LegProgressTracker(path: straightRoute(miles: 10))
        tracker.update(with: fix(atMile: 9.8))
        #expect(!tracker.hasArrived)
        tracker.update(with: fix(atMile: 9.95))
        #expect(tracker.hasArrived)
    }
}
