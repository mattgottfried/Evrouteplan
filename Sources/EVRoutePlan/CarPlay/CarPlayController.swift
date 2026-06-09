import CarPlay
import CoreLocation

@MainActor
final class CarPlayController {
    private let interfaceController: CPInterfaceController
    private let appState: AppState
    private var observationTask: Task<Void, Never>?

    private var routeTemplate: CPListTemplate?
    private var nearbyTemplate: CPPointOfInterestTemplate?

    init(interfaceController: CPInterfaceController, appState: AppState) {
        self.interfaceController = interfaceController
        self.appState = appState
    }

    func connect() {
        let routeTpl = buildRouteListTemplate()
        let nearbyTpl = buildNearbyChargersTemplate(stations: [])

        routeTpl.tabTitle = "Route"
        routeTpl.tabImage = UIImage(systemName: "map.fill")
        nearbyTpl.tabTitle = "Nearby"
        nearbyTpl.tabImage = UIImage(systemName: "bolt.fill")

        self.routeTemplate = routeTpl
        self.nearbyTemplate = nearbyTpl

        let tabBar = CPTabBarTemplate(templates: [routeTpl, nearbyTpl])
        interfaceController.setRootTemplate(tabBar, animated: false, completion: nil)

        startObserving()
    }

    func disconnect() {
        observationTask?.cancel()
        observationTask = nil
    }

    // MARK: - Observation

    private func startObserving() {
        observationTask?.cancel()
        observationTask = Task { @MainActor [weak self] in
            await self?.observeLoop()
        }
    }

    private func observeLoop() async {
        withObservationTracking {
            _ = appState.plannedRoute
            _ = appState.routePlanningState
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.updateRouteTemplate()
                self?.observeLoop()
            }
        }
    }

    // MARK: - Template updates

    private func updateRouteTemplate() {
        let newTpl = buildRouteListTemplate()
        newTpl.tabTitle = routeTemplate?.tabTitle
        newTpl.tabImage = routeTemplate?.tabImage

        if let root = interfaceController.rootTemplate as? CPTabBarTemplate,
           let idx = root.templates.firstIndex(where: { $0 === routeTemplate }) {
            var templates = root.templates
            templates[idx] = newTpl
            interfaceController.setRootTemplate(
                CPTabBarTemplate(templates: templates),
                animated: false,
                completion: nil
            )
        }
        routeTemplate = newTpl
    }

    // MARK: - Route list

    private func buildRouteListTemplate() -> CPListTemplate {
        switch appState.routePlanningState {
        case .idle:
            return idleRouteTemplate()
        case .planning:
            return loadingRouteTemplate()
        case .failed(let msg):
            return errorRouteTemplate(message: msg)
        case .done:
            if let route = appState.plannedRoute {
                return plannedRouteTemplate(route)
            }
            return idleRouteTemplate()
        }
    }

    private func idleRouteTemplate() -> CPListTemplate {
        let item = CPListItem(text: "No route planned", detailText: "Plan a route on your iPhone")
        return CPListTemplate(title: "Route", sections: [CPListSection(items: [item])])
    }

    private func loadingRouteTemplate() -> CPListTemplate {
        let item = CPListItem(text: "Planning route…", detailText: "Finding charging stops")
        return CPListTemplate(title: "Route", sections: [CPListSection(items: [item])])
    }

    private func errorRouteTemplate(message: String) -> CPListTemplate {
        let item = CPListItem(text: "Route Error", detailText: message)
        return CPListTemplate(title: "Route", sections: [CPListSection(items: [item])])
    }

    private func plannedRouteTemplate(_ route: PlannedRoute) -> CPListTemplate {
        let h = Int(route.estimatedTotalMinutes) / 60
        let m = Int(route.estimatedTotalMinutes) % 60
        let timeStr = h > 0 ? "\(h)h \(m)m" : "\(m)m"

        let summaryItem = CPListItem(
            text: route.destination.name,
            detailText: String(format: "%.0f mi · %@ · %d stop%@",
                route.totalDistanceMiles,
                timeStr,
                route.stops.count,
                route.stops.count == 1 ? "" : "s"
            )
        )
        summaryItem.image = UIImage(systemName: "flag.checkered")
        let summarySection = CPListSection(items: [summaryItem], header: "Destination", sectionIndexTitle: nil)

        var sections: [CPListSection] = [summarySection]
        for (i, stop) in route.stops.enumerated() {
            let item = CPListItem(
                text: stop.station.stationName,
                detailText: String(format: "Arrive %d%% · ~%.0f min charge",
                    Int(stop.arrivalSOC * 100),
                    stop.estimatedChargeTimeMinutes
                )
            )
            item.image = UIImage(systemName: "bolt.fill")
            let header = "Stop \(i + 1) — \(stop.station.city), \(stop.station.state)"
            sections.append(CPListSection(items: [item], header: header, sectionIndexTitle: nil))
        }

        return CPListTemplate(title: "Route", sections: sections)
    }
}
