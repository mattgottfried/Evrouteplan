import CarPlay
import MapKit
import UIKit

/// CarPlay entry point. Requires the `com.apple.developer.carplay-charging`
/// entitlement (EV charging app category) — see the README for how to
/// request it from Apple. Until it's granted, this scene simply never
/// launches; the iPhone app is unaffected.
///
/// Referenced from Info.plist as
/// `$(PRODUCT_MODULE_NAME).CarPlaySceneDelegate`.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?
    private var scene: CPTemplateApplicationScene?

    private var chargersTemplate: CPPointOfInterestTemplate?
    private var tripTemplate: CPListTemplate?
    private var batteryTemplate: CPListTemplate?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        self.scene = templateApplicationScene

        let chargers = CPPointOfInterestTemplate(
            title: "Chargers", pointsOfInterest: [], selectedIndex: NSNotFound
        )
        chargers.tabTitle = "Chargers"
        chargers.tabImage = UIImage(systemName: "bolt.fill")
        chargersTemplate = chargers

        let trip = CPListTemplate(title: "Trip Plan", sections: [])
        trip.tabTitle = "Trip"
        trip.tabImage = UIImage(systemName: "map.fill")
        tripTemplate = trip

        let battery = CPListTemplate(title: "Battery", sections: [])
        battery.tabTitle = "Battery"
        battery.tabImage = UIImage(systemName: "battery.75percent")
        batteryTemplate = battery

        let tabBar = CPTabBarTemplate(templates: [chargers, trip, battery])
        interfaceController.setRootTemplate(tabBar, animated: true, completion: nil)

        reloadAll()
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        self.interfaceController = nil
        self.scene = nil
        chargersTemplate = nil
        tripTemplate = nil
        batteryTemplate = nil
    }

    private func reloadAll() {
        Task { @MainActor in
            self.reloadTrip()
            self.reloadBattery()
            await AppState.shared.refreshStatus(force: false)
            self.reloadBattery()
            let stations = await AppState.shared.nearbyChargers()
            self.showChargers(stations)
        }
    }

    // MARK: - Chargers tab

    @MainActor
    private func showChargers(_ stations: [ChargingStation]) {
        guard let chargersTemplate else { return }
        let pois = stations.prefix(12).map { station in
            let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: station.coordinate))
            mapItem.name = station.name
            let poi = CPPointOfInterest(
                location: mapItem,
                title: station.name,
                subtitle: "\(station.network) · \(station.dcFastCount) DC plugs",
                summary: station.shortAddress,
                detailTitle: station.name,
                detailSubtitle: station.network,
                detailSummary: station.pricing ?? station.shortAddress,
                pinImage: nil
            )
            let button = CPTextButton(title: "Navigate", textStyle: .confirm) { [weak self] _ in
                self?.navigate(to: mapItem)
            }
            poi.primaryButton = button
            return poi
        }
        chargersTemplate.setPointsOfInterest(Array(pois), selectedIndex: NSNotFound)
    }

    // MARK: - Trip tab

    @MainActor
    private func reloadTrip() {
        guard let tripTemplate else { return }
        guard let route = AppState.shared.plannedRoute else {
            let item = CPListItem(
                text: "No trip planned",
                detailText: "Plan a trip in the app on your iPhone, then reopen this tab."
            )
            tripTemplate.updateSections([CPListSection(items: [item])])
            return
        }

        var items: [CPListItem] = []
        for (index, stop) in route.stops.enumerated() {
            let item = CPListItem(
                text: "\(index + 1). \(stop.station.name)",
                detailText: "\(Format.percent(stop.arrivalSOC)) → \(Format.percent(stop.departureSOC)) · \(Format.minutes(stop.chargeMinutes)) · \(stop.station.network)"
            )
            item.handler = { [weak self] _, completion in
                let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: stop.station.coordinate))
                mapItem.name = stop.station.name
                self?.navigate(to: mapItem)
                completion()
            }
            items.append(item)
        }

        let destinationItem = CPListItem(
            text: "🏁 \(route.destinationName)",
            detailText: "\(Format.miles(route.totalMiles)) total · arrive at \(Format.percent(route.arrivalSOC))"
        )
        destinationItem.handler = { [weak self] _, completion in
            let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: route.destinationCoordinate))
            mapItem.name = route.destinationName
            self?.navigate(to: mapItem)
            completion()
        }
        items.append(destinationItem)

        let header = route.needsCharging
            ? "\(route.stops.count) charging stop\(route.stops.count == 1 ? "" : "s") · \(Format.minutes(route.totalMinutes))"
            : "No charging needed · \(Format.minutes(route.totalMinutes))"
        tripTemplate.updateSections([CPListSection(items: items, header: header, sectionIndexTitle: nil)])
    }

    // MARK: - Battery tab

    @MainActor
    private func reloadBattery() {
        guard let batteryTemplate else { return }
        let state = AppState.shared
        var items: [CPListItem] = []

        if let status = state.status {
            let soc = status.socPercent.map { "\(Int($0))%" } ?? "—"
            let range = status.rangeMiles.map { " · \(Int($0)) mi" } ?? ""
            let charging: String
            if status.isCharging == true {
                if let minutes = status.minutesToTargetSOC, minutes > 0 {
                    charging = "Charging — \(Format.minutes(Double(minutes))) to limit"
                } else {
                    charging = "Charging"
                }
            } else if status.isPluggedIn == true {
                charging = "Plugged in, not charging"
            } else {
                charging = "Not plugged in"
            }
            items.append(CPListItem(text: "\(soc)\(range)", detailText: charging))
            if let reported = status.reportedAt {
                items.append(CPListItem(text: "Car reported", detailText: Format.relative(reported)))
            }
        } else {
            items.append(CPListItem(
                text: "No data",
                detailText: state.accountState == .signedIn
                    ? "Refreshing from BlueLink…"
                    : "Sign in to BlueLink on your iPhone."
            ))
        }

        let refresh = CPListItem(text: "Refresh", detailText: "Fetch latest from BlueLink")
        refresh.handler = { [weak self] _, completion in
            Task { @MainActor in
                await AppState.shared.refreshStatus(force: false)
                self?.reloadBattery()
                completion()
            }
        }
        items.append(refresh)

        batteryTemplate.updateSections([CPListSection(items: items)])
    }

    // MARK: - Navigation handoff

    /// Opens Apple Maps navigation on the CarPlay display by passing the
    /// CarPlay scene to MapKit.
    private func navigate(to mapItem: MKMapItem) {
        guard let scene else { return }
        mapItem.openInMaps(
            launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving],
            from: scene,
            completionHandler: nil
        )
    }
}
