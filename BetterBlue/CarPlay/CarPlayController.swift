//
//  CarPlayController.swift
//  BetterBlue
//
//  CarPlay (EV charging category): a Route tab mirroring TripSession and a
//  Nearby tab of DC fast chargers around the car. Trips are planned on the
//  phone; selecting a stop hands off to the maps app on the car screen.
//

import BetterBlueKit
import CarPlay
import CoreLocation
import MapKit
import Observation

@MainActor
final class CarPlayController {
    private let interfaceController: CPInterfaceController
    private let routeTemplate = CPListTemplate(title: "Route", sections: [])
    private let nearbyTemplate = CPPointOfInterestTemplate(
        title: "Nearby Chargers",
        pointsOfInterest: [],
        selectedIndex: NSNotFound
    )
    private var tasks: [Task<Void, Never>] = []
    private var lastNearbyFetch: CLLocation?

    /// Re-query nearby chargers after moving this far (~5 km).
    private static let nearbyRefreshMeters: CLLocationDistance = 5000

    private var session: TripSession { .shared }

    init(interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
    }

    func connect() {
        routeTemplate.tabTitle = "Route"
        routeTemplate.tabImage = UIImage(systemName: "map.fill")
        routeTemplate.emptyViewTitleVariants = ["No Trip Planned"]
        routeTemplate.emptyViewSubtitleVariants = ["Plan a trip in BetterBlue on your iPhone."]
        nearbyTemplate.tabTitle = "Nearby"
        nearbyTemplate.tabImage = UIImage(systemName: "bolt.fill")

        let tabBar = CPTabBarTemplate(templates: [routeTemplate, nearbyTemplate])
        interfaceController.setRootTemplate(tabBar, animated: false, completion: nil)

        LocationProvider.shared.acquire(background: true)
        updateRouteTemplate()

        tasks.append(Task { [weak self] in
            let changes = Observations {
                (TripSession.shared.plannedRoute?.createdAt, TripSession.shared.planningState, TripSession.shared.activeTrip)
            }
            for await _ in changes {
                guard let self, !Task.isCancelled else { return }
                self.updateRouteTemplate()
            }
        })
        tasks.append(Task { [weak self] in
            for await location in Observations({ LocationProvider.shared.lastLocation }) {
                guard let self, !Task.isCancelled else { return }
                if let location { await self.refreshNearbyIfNeeded(at: location) }
            }
        })
    }

    func disconnect() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        LocationProvider.shared.release()
    }

    // MARK: - Route tab

    private func updateRouteTemplate() {
        switch session.planningState {
        case .planning:
            routeTemplate.updateSections([CPListSection(items: [
                CPListItem(text: "Planning route…", detailText: "Finding charging stops"),
            ])])
            return
        case .failed(let message):
            routeTemplate.updateSections([CPListSection(items: [
                CPListItem(text: "Couldn't plan route", detailText: message),
            ])])
            return
        case .idle:
            break
        }
        guard let route = session.plannedRoute else {
            routeTemplate.updateSections([])
            return
        }

        var sections: [CPListSection] = []
        if let trip = session.activeTrip, let leg = session.currentLeg {
            sections.append(CPListSection(items: [progressItem(trip: trip, leg: leg)], header: "Now", sectionIndexTitle: nil))
        }

        let summary = CPListItem(
            text: route.destination.name,
            detailText: "\(RouteFormat.distance(miles: route.totalDistanceMiles)) · \(RouteFormat.duration(minutes: route.totalMinutes)) · arrive \(RouteFormat.percent(route.arrivalSOC))"
        )
        summary.setImage(UIImage(systemName: "flag.checkered"))
        summary.handler = { _, completion in
            TripNavigator.navigate(to: route.destination, using: RoutePlanningSettings.shared.preferredMapApp)
            completion()
        }

        let stopItems: [CPListItem] = route.stops.enumerated().map { index, stop in
            let item = CPListItem(
                text: "\(index + 1). \(stop.station.stationName)",
                detailText: "\(stop.station.networkName) · arrive \(RouteFormat.percent(stop.arrivalSOC)) · ~\(RouteFormat.duration(minutes: stop.chargeMinutes)) charge"
            )
            item.setImage(UIImage(systemName: "bolt.fill"))
            let place = RoutePlace(name: stop.station.stationName, coordinate: stop.station.coordinate)
            item.handler = { _, completion in
                TripNavigator.navigate(to: place, using: RoutePlanningSettings.shared.preferredMapApp)
                completion()
            }
            return item
        }

        sections.append(CPListSection(items: [summary], header: "Destination", sectionIndexTitle: nil))
        if !stopItems.isEmpty {
            sections.append(CPListSection(items: stopItems, header: "Charging Stops", sectionIndexTitle: nil))
        }
        routeTemplate.updateSections(sections)
    }

    private func progressItem(trip: TripSession.ActiveTrip, leg: RouteLeg) -> CPListItem {
        let title: String = if trip.hasArrivedAtDestination {
            "Arrived at \(leg.end.name)"
        } else if trip.isAtStop {
            "Charging at \(leg.end.name)"
        } else {
            "\(RouteFormat.distance(miles: trip.remainingLegMiles)) to \(leg.end.name)"
        }
        var detail = "Arrive with \(RouteFormat.percent(trip.socAtLegEnd))"
        if trip.isReplanning {
            detail = "Off route — re-planning…"
        } else if trip.isOffRoute {
            detail = "Off route"
        } else if session.isLowBatteryPredicted {
            detail += " — below reserve"
        }
        let item = CPListItem(text: title, detailText: detail)
        item.setImage(UIImage(systemName: trip.isAtStop ? "bolt.car.fill" : "location.fill"))
        item.handler = { [weak self] _, completion in
            if trip.isAtStop {
                self?.session.continueToNextLeg()
            }
            self?.session.navigateCurrentLeg()
            completion()
        }
        return item
    }

    // MARK: - Nearby tab

    private func refreshNearbyIfNeeded(at location: CLLocation) async {
        if let last = lastNearbyFetch, location.distance(from: last) < Self.nearbyRefreshMeters { return }
        lastNearbyFetch = location
        let service = NRELService(apiKey: RoutePlanningSettings.shared.nrelAPIKey)
        do {
            let stations = try await service.fetchStations(near: location.coordinate, radiusMiles: 25, limit: 12)
            nearbyTemplate.setPointsOfInterest(stations.map(pointOfInterest), selectedIndex: NSNotFound)
        } catch {
            BBLogger.warning(.app, "CarPlay: nearby chargers failed: \(error)")
            lastNearbyFetch = nil
        }
    }

    private func pointOfInterest(for station: ChargingStation) -> CPPointOfInterest {
        let item = MKMapItem(location: CLLocation(latitude: station.latitude, longitude: station.longitude), address: nil)
        item.name = station.stationName
        let poi = CPPointOfInterest(
            location: item,
            title: station.stationName,
            subtitle: "\(station.networkName) · \(station.evDcFastNum ?? 0) DC fast",
            summary: station.streetAddress,
            detailTitle: station.stationName,
            detailSubtitle: station.locality,
            detailSummary: "Up to ~\(Int(station.estimatedMaxKW)) kW",
            pinImage: UIImage(systemName: "bolt.circle.fill")
        )
        let place = RoutePlace(name: station.stationName, coordinate: station.coordinate)
        poi.primaryButton = CPTextButton(title: "Navigate", textStyle: .confirm) { _ in
            TripNavigator.navigate(to: place, using: RoutePlanningSettings.shared.preferredMapApp)
        }
        return poi
    }
}
