//
//  ChargeStopPlanner.swift
//  BetterBlue
//
//  Chooses DC fast-charging stops along a route. Pure and synchronous: the
//  caller fetches the route and the corridor's stations up front (one NREL
//  request), so planning never hits the network per waypoint.
//

import CoreLocation
import Foundation

enum ChargeStopPlannerError: Error, LocalizedError, Equatable {
    /// No reachable charger before the battery would drop below reserve.
    case noReachableCharger(atMile: Double)

    var errorDescription: String? {
        switch self {
        case .noReachableCharger(let mile):
            "No reachable DC fast charger after mile \(Int(mile)). Try charging higher before you leave."
        }
    }
}

struct ChargeStopPlanner: Sendable {
    let profile: EVProfile
    let fullRangeMiles: Double
    /// Stations farther than this from the route are ignored.
    var maxDetourMiles: Double = 5
    /// Prefer stops in the back part of each reachable window, so the car
    /// isn't charged needlessly early; 0.5 = second half of the window.
    var preferredWindowStart: Double = 0.5
    /// Extra SOC to carry past what the next leg strictly needs, when a stop
    /// only charges as far as necessary.
    var finalLegMargin: Double = 0.05

    func planStops(
        along path: RoutePath,
        startSOC: Double,
        stations: [ChargingStation]
    ) throws -> [ChargingStop] {
        let total = path.totalMiles
        guard total > 0, fullRangeMiles > 0 else { return [] }

        let candidates = project(stations, onto: path)
        var stops: [ChargingStop] = []
        var positionMile = 0.0
        var soc = startSOC
        var used = Set<Int>()

        while true {
            let usableMiles = max(0, soc - profile.arrivalReserveSOC) * fullRangeMiles
            if positionMile + usableMiles >= total { break }

            // Stations ahead of us we can reach (including the detour off the
            // route) while keeping the reserve.
            let reachable = candidates.filter { candidate -> Bool in
                guard !used.contains(candidate.station.id), candidate.mile > positionMile + 1 else {
                    return false
                }
                let drive: Double = (candidate.mile - positionMile) + candidate.offset
                return drive <= usableMiles
            }
            guard !reachable.isEmpty else {
                throw ChargeStopPlannerError.noReachableCharger(atMile: positionMile)
            }

            let windowStart = positionMile + usableMiles * preferredWindowStart
            let late = reachable.filter { $0.mile >= windowStart }
            let choice: Candidate = if late.isEmpty {
                reachable.max { $0.mile < $1.mile }!
            } else {
                // Fastest charger in the window; break ties by progress.
                late.max { lhs, rhs in
                    let l = effectiveKW(lhs.station), r = effectiveKW(rhs.station)
                    return l == r ? lhs.mile < rhs.mile : l < r
                }!
            }

            let drivenMiles = (choice.mile - positionMile) + choice.offset
            let arrivalSOC = soc - drivenMiles / fullRangeMiles

            // Charge only as far as needed to finish the trip if that's
            // below the target — shortens the final stop.
            let remainingMiles = (total - choice.mile) + choice.offset
            let neededSOC = remainingMiles / fullRangeMiles + profile.arrivalReserveSOC + finalLegMargin
            let departureSOC = max(arrivalSOC, min(profile.targetSOC, neededSOC))

            stops.append(ChargingStop(
                station: choice.station,
                routeMile: choice.mile,
                detourMiles: choice.offset,
                arrivalSOC: arrivalSOC,
                departureSOC: departureSOC,
                chargeMinutes: estimateChargeMinutes(
                    fromSOC: arrivalSOC,
                    toSOC: departureSOC,
                    stationKW: choice.station.estimatedMaxKW
                ),
                distanceFromPreviousMiles: drivenMiles
            ))
            used.insert(choice.station.id)

            // Rejoin the route after driving back from the station.
            positionMile = choice.mile
            soc = departureSOC - choice.offset / fullRangeMiles

            // A stop that can't add range means we'd loop forever.
            if departureSOC <= arrivalSOC, positionMile + max(0, soc - profile.arrivalReserveSOC) * fullRangeMiles < total {
                throw ChargeStopPlannerError.noReachableCharger(atMile: positionMile)
            }
        }
        return stops
    }

    /// Charge time with a simple two-stage curve: near peak power up to 80 %,
    /// then roughly a third of it as the pack tapers.
    func estimateChargeMinutes(fromSOC: Double, toSOC: Double, stationKW: Double) -> Double {
        let kW = min(stationKW, profile.maxDCKW)
        guard toSOC > fromSOC, kW > 0 else { return 0 }
        let knee = 0.80
        let fastPortion = max(0, min(toSOC, knee) - fromSOC)
        let slowPortion = max(0, toSOC - max(fromSOC, knee))
        let fastKW = kW * 0.85, slowKW = kW * 0.35
        let hours = fastPortion * profile.usableBatteryKWh / fastKW
            + slowPortion * profile.usableBatteryKWh / slowKW
        return hours * 60
    }

    // MARK: - Private

    private struct Candidate {
        let station: ChargingStation
        let mile: Double
        let offset: Double
    }

    private func effectiveKW(_ station: ChargingStation) -> Double {
        min(station.estimatedMaxKW, profile.maxDCKW)
    }

    private func project(_ stations: [ChargingStation], onto path: RoutePath) -> [Candidate] {
        stations.compactMap { station in
            guard station.hasDCFast, station.isPublic,
                  station.estimatedMaxKW >= ChargingStation.minimumDCFastKW,
                  let projection = path.project(station.coordinate),
                  projection.offsetMiles <= maxDetourMiles
            else { return nil }
            return Candidate(station: station, mile: projection.routeMile, offset: projection.offsetMiles)
        }
    }
}
