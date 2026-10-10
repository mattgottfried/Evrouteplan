//
//  TripSession.swift
//  BetterBlue
//
//  Shared trip state for the iPhone UI and CarPlay: the planned route,
//  live GPS progress along the current leg, predicted state of charge,
//  off-route re-planning, and leg-by-leg hand-off to a maps app.
//

import BetterBlueKit
import CoreLocation
import Foundation
import MapKit
import Observation
import SwiftData
import UIKit

@MainActor
@Observable
final class TripSession {
    static let shared = TripSession()

    enum PlanningState: Equatable {
        case idle
        case planning
        case failed(String)
    }

    struct ActiveTrip: Equatable {
        var legIndex = 0
        var progressMiles = 0.0
        var remainingLegMiles = 0.0
        /// Predicted SOC right now.
        var currentSOC: Double
        /// Predicted SOC on reaching the end of the current leg.
        var socAtLegEnd: Double
        var isOffRoute = false
        var isReplanning = false
        /// At a charging stop, waiting to leave.
        var isAtStop = false
        var hasArrivedAtDestination = false
        /// When the SOC estimate was last re-anchored to live vehicle data.
        var vehicleSOCAt: Date?
        var hasFix = false
    }

    private(set) var plannedRoute: PlannedRoute?
    private(set) var planningState: PlanningState = .idle
    private(set) var activeTrip: ActiveTrip?
    private(set) var vehicleVIN: String?

    var currentLeg: RouteLeg? {
        guard let route = plannedRoute, let trip = activeTrip, route.legs.indices.contains(trip.legIndex) else {
            return plannedRoute?.legs.first
        }
        return route.legs[trip.legIndex]
    }

    /// The trip warns when the current leg is predicted to end below reserve.
    var isLowBatteryPredicted: Bool {
        guard let trip = activeTrip, let route = plannedRoute else { return false }
        return trip.socAtLegEnd < route.profile.arrivalReserveSOC - 0.02
    }

    // MARK: - Private state

    @ObservationIgnored private var destinationItem: MKMapItem?
    @ObservationIgnored private var tracker: LegProgressTracker?
    @ObservationIgnored private var socAnchor = 0.0
    @ObservationIgnored private var milesSinceAnchor = 0.0
    @ObservationIgnored private var previousFix: CLLocationCoordinate2D?
    @ObservationIgnored private var lastReplanAt: Date?
    @ObservationIgnored private var locationTask: Task<Void, Never>?
    @ObservationIgnored private var vehicleRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var planTask: Task<Void, Never>?

    private static let replanCooldown: TimeInterval = 120
    private static let vehicleRefreshInterval: Duration = .seconds(600)
    /// Leaving a charger by this much ends the stop (~300 m).
    private static let departStopMiles = 0.19

    private init() {}

    // MARK: - Planning

    func plan(to destination: MKMapItem, vehicle: BBVehicle, socOverride: Double?) {
        let inputs = PlanInputs(vehicle: vehicle, socOverride: socOverride)
        destinationItem = destination
        vehicleVIN = vehicle.vin
        planTask?.cancel()
        planTask = Task {
            await runPlan(from: nil, startSOC: inputs.startSOC, profile: inputs.profile, fullRange: inputs.fullRange)
        }
    }

    func clearRoute() {
        endTrip()
        planTask?.cancel()
        plannedRoute = nil
        destinationItem = nil
        planningState = .idle
    }

    private func runPlan(
        from origin: CLLocationCoordinate2D?,
        startSOC: Double,
        profile: EVProfile,
        fullRange: Double
    ) async {
        guard let destination = destinationItem else { return }
        planningState = .planning
        let service = RoutePlannerService(nrel: NRELService(apiKey: RoutePlanningSettings.shared.nrelAPIKey))
        do {
            let route = try await service.planRoute(
                from: origin,
                to: destination,
                startSOC: startSOC,
                profile: profile,
                fullRangeMiles: fullRange
            )
            try Task.checkCancellation()
            plannedRoute = route
            planningState = .idle
        } catch is CancellationError {
            // Superseded by a newer plan.
        } catch {
            BBLogger.error(.app, "TripSession: planning failed: \(error)")
            planningState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Trip lifecycle

    func startTrip() {
        guard let route = plannedRoute, let firstLeg = route.legs.first else { return }
        socAnchor = firstLeg.departureSOC
        milesSinceAnchor = 0
        previousFix = nil
        tracker = LegProgressTracker(path: RoutePath(coordinates: firstLeg.coordinates))
        activeTrip = ActiveTrip(
            remainingLegMiles: firstLeg.distanceMiles,
            currentSOC: firstLeg.departureSOC,
            socAtLegEnd: firstLeg.arrivalSOC
        )
        UIApplication.shared.isIdleTimerDisabled = true

        LocationProvider.shared.acquire(background: true)
        locationTask?.cancel()
        locationTask = Task { [weak self] in
            let fixes = Observations { LocationProvider.shared.lastLocation }
            for await location in fixes {
                guard let self, !Task.isCancelled else { return }
                if let location { self.handleFix(location.coordinate) }
            }
        }
        vehicleRefreshTask?.cancel()
        vehicleRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.vehicleRefreshInterval)
                await self?.refreshVehicleSOC()
            }
        }
    }

    func endTrip() {
        guard activeTrip != nil else { return }
        locationTask?.cancel()
        vehicleRefreshTask?.cancel()
        locationTask = nil
        vehicleRefreshTask = nil
        tracker = nil
        activeTrip = nil
        LocationProvider.shared.release()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    /// Leave the current charging stop and start the next leg.
    func continueToNextLeg() {
        guard let route = plannedRoute, var trip = activeTrip,
              route.legs.indices.contains(trip.legIndex + 1) else { return }
        let finished = route.legs[trip.legIndex]
        trip.legIndex += 1
        let leg = route.legs[trip.legIndex]
        // The car was charging; until live data says otherwise assume it
        // reached the planned departure SOC.
        socAnchor = max(trip.currentSOC, finished.endStop?.departureSOC ?? leg.departureSOC)
        milesSinceAnchor = 0
        tracker = LegProgressTracker(path: RoutePath(coordinates: leg.coordinates))
        trip.isAtStop = false
        trip.isOffRoute = false
        trip.progressMiles = 0
        trip.remainingLegMiles = leg.distanceMiles
        trip.currentSOC = socAnchor
        trip.socAtLegEnd = socAnchor - leg.distanceMiles / route.fullRangeMiles
        activeTrip = trip
        Task { await refreshVehicleSOC() }
    }

    func replan() {
        guard let route = plannedRoute else { return }
        let origin = LocationProvider.shared.lastLocation?.coordinate
        let soc = activeTrip?.currentSOC ?? route.legs.first?.departureSOC ?? 0.8
        replan(from: origin, soc: soc)
    }

    private func replan(from origin: CLLocationCoordinate2D?, soc: Double) {
        guard let route = plannedRoute else { return }
        lastReplanAt = .now
        activeTrip?.isReplanning = true
        planTask?.cancel()
        planTask = Task {
            await runPlan(from: origin, startSOC: soc, profile: route.profile, fullRange: route.fullRangeMiles)
            guard !Task.isCancelled else { return }
            activeTrip?.isReplanning = false
            if activeTrip != nil, case .idle = planningState { restartTripOnNewRoute(soc: soc) }
        }
    }

    private func restartTripOnNewRoute(soc: Double) {
        guard let route = plannedRoute, let leg = route.legs.first else { return }
        socAnchor = soc
        milesSinceAnchor = 0
        tracker = LegProgressTracker(path: RoutePath(coordinates: leg.coordinates))
        activeTrip?.legIndex = 0
        activeTrip?.isOffRoute = false
        activeTrip?.isAtStop = false
        activeTrip?.remainingLegMiles = leg.distanceMiles
        activeTrip?.socAtLegEnd = soc - leg.distanceMiles / route.fullRangeMiles
    }

    // MARK: - Navigation hand-off

    /// Opens the preferred maps app with driving directions for the current leg.
    func navigateCurrentLeg() {
        guard let leg = currentLeg else { return }
        TripNavigator.navigate(to: leg.end, using: RoutePlanningSettings.shared.preferredMapApp)
    }

    // MARK: - Live updates

    private func handleFix(_ fix: CLLocationCoordinate2D) {
        guard var trip = activeTrip, var tracker, let route = plannedRoute else { return }

        if let previous = previousFix {
            let step = Geo.miles(previous, fix)
            if step < 2 { milesSinceAnchor += step } // ignore GPS jumps
        }
        previousFix = fix

        tracker.update(with: fix)
        self.tracker = tracker

        trip.hasFix = true
        trip.progressMiles = tracker.progressMiles
        trip.remainingLegMiles = tracker.remainingMiles
        trip.currentSOC = socAnchor - milesSinceAnchor / route.fullRangeMiles
        trip.socAtLegEnd = trip.currentSOC - tracker.remainingMiles / route.fullRangeMiles
        trip.isOffRoute = tracker.isOffRoute

        let leg = route.legs[trip.legIndex]
        if tracker.hasArrived {
            if leg.endStop != nil {
                trip.isAtStop = true
            } else {
                trip.hasArrivedAtDestination = true
            }
        }
        activeTrip = trip

        if trip.isAtStop, Geo.miles(fix, leg.end.coordinate) > Self.departStopMiles {
            continueToNextLeg()
        } else if trip.isOffRoute, !trip.isReplanning, !trip.isAtStop,
                  lastReplanAt.map({ Date.now.timeIntervalSince($0) > Self.replanCooldown }) ?? true {
            BBLogger.info(.app, "TripSession: off route, re-planning")
            replan(from: fix, soc: trip.currentSOC)
        }
    }

    /// Re-anchors the SOC estimate to the car's own reading when BlueLink
    /// has something newer than the current anchor.
    private func refreshVehicleSOC() async {
        guard let vin = vehicleVIN, let context = appModelContainer?.mainContext,
              let vehicle = try? context.fetch(FetchDescriptor<BBVehicle>(predicate: #Predicate { $0.vin == vin })).first,
              let account = vehicle.account else { return }
        do {
            let status = try await account.fetchVehicleStatus(for: vehicle, modelContext: context)
            vehicle.updateStatus(with: status)
            try? context.save()
        } catch {
            BBLogger.warning(.app, "TripSession: vehicle refresh failed: \(error)")
            return
        }
        guard let percent = vehicle.evStatus?.evRange.percentage, percent > 0,
              let updated = vehicle.lastUpdated, var trip = activeTrip,
              updated > (trip.vehicleSOCAt ?? .distantPast) else { return }
        socAnchor = percent / 100
        milesSinceAnchor = 0
        trip.vehicleSOCAt = updated
        trip.currentSOC = socAnchor
        if let route = plannedRoute {
            trip.socAtLegEnd = socAnchor - trip.remainingLegMiles / route.fullRangeMiles
        }
        activeTrip = trip
    }
}

// MARK: - Plan inputs from a vehicle

@MainActor
struct PlanInputs {
    let profile: EVProfile
    let startSOC: Double
    let fullRange: Double

    init(vehicle: BBVehicle, socOverride: Double?) {
        profile = EVProfileStore.profile(forVIN: vehicle.vin, model: vehicle.model)
        let live = vehicle.evStatus?.evRange
        let liveMiles = live.map { $0.range.units.convert($0.range.length, to: .miles) }
        let livePercent = live?.percentage
        fullRange = profile.fullRangeMiles(liveRangeMiles: liveMiles, livePercent: livePercent)
        startSOC = socOverride ?? livePercent.map { $0 / 100 } ?? 0.8
    }

    /// Live SOC as a fraction, if BlueLink reported one.
    static func liveSOC(of vehicle: BBVehicle) -> Double? {
        guard let percent = vehicle.evStatus?.evRange.percentage, percent > 0 else { return nil }
        return percent / 100
    }
}

// MARK: - Maps hand-off

enum TripNavigator {
    @MainActor static func navigate(to place: RoutePlace, using app: MapApp) {
        let lat = place.coordinate.latitude, lon = place.coordinate.longitude
        switch app {
        case .appleMaps:
            let item = MKMapItem(location: CLLocation(latitude: lat, longitude: lon), address: nil)
            item.name = place.name
            item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
        case .googleMaps:
            let native = URL(string: "comgooglemaps://?daddr=\(lat),\(lon)&directionsmode=driving")!
            let web = URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(lat),\(lon)&travelmode=driving")!
            UIApplication.shared.open(UIApplication.shared.canOpenURL(native) ? native : web)
        case .waze:
            UIApplication.shared.open(URL(string: "https://waze.com/ul?ll=\(lat),\(lon)&navigate=yes")!)
        }
    }
}
