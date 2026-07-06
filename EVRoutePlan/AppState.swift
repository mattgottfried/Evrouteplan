import CoreLocation
import Foundation
import MapKit
import Observation
import WeatherKit

@MainActor
@Observable
final class AppState {
    /// Single shared instance so the CarPlay scene and the SwiftUI app see
    /// the same data.
    static let shared = AppState()

    // MARK: - Services

    let blueLink = BlueLinkClient()
    let nrel = NRELClient()
    var planner: RoutePlanner { RoutePlanner(nrel: nrel) }

    // MARK: - Sign-in / vehicle state

    enum AccountState: Equatable {
        case signedOut
        case signingIn
        case signedIn
    }

    private(set) var accountState: AccountState = .signedOut
    private(set) var vehicle: BlueLinkVehicle?
    private(set) var status: BlueLinkStatus?
    private(set) var isRefreshingStatus = false
    private(set) var busyCommand: String?   // e.g. "Locking…" while a remote command runs
    var lastError: String?

    // MARK: - Route planning state

    enum PlanState: Equatable {
        case idle
        case planning
        case planned
        case failed(String)
    }

    private(set) var planState: PlanState = .idle
    private(set) var plannedRoute: PlannedRoute?
    private(set) var recentDestinations: [RecentDestination] = []
    private(set) var savedPlaces: [SavedPlace] = []
    private(set) var savedPlans: [SavedPlan] = []
    private(set) var chargeSessions: [ChargeSession] = []
    /// Ambient °F used for the last plan, for display. Nil = no adjustment.
    private(set) var lastPlanTempF: Double?
    /// One-shot per-trip battery override set from the Options sheet.
    var departureSOCOverride: Double?

    // MARK: - Settings (persisted)

    var settings = PlannerSettings() {
        didSet { persistSettings() }
    }

    /// Used when BlueLink is unavailable; set from the status when it arrives.
    var manualSOCPercent: Double {
        didSet { UserDefaults.standard.set(manualSOCPercent, forKey: "manualSOCPercent") }
    }

    var nrelAPIKey: String {
        didSet { UserDefaults.standard.set(nrelAPIKey, forKey: "nrelAPIKey") }
    }

    /// SOC used for planning: per-trip override first, then live from the
    /// car, then the manual slider.
    var effectiveSOCFraction: Double {
        if let override = departureSOCOverride { return override }
        if let live = status?.socFraction, let fetched = status?.fetchedAt,
           fetched.timeIntervalSinceNow > -3600 {
            return live
        }
        return manualSOCPercent / 100.0
    }

    var hasLiveSOC: Bool {
        status?.socFraction != nil
    }

    // MARK: - Init

    private init() {
        let defaults = UserDefaults.standard
        manualSOCPercent = defaults.object(forKey: "manualSOCPercent") as? Double ?? 80
        nrelAPIKey = defaults.string(forKey: "nrelAPIKey") ?? ""

        if let data = defaults.data(forKey: "recentDestinations"),
           let recents = try? JSONDecoder().decode([RecentDestination].self, from: data) {
            recentDestinations = recents
        }
        if let data = defaults.data(forKey: "savedPlaces"),
           let places = try? JSONDecoder().decode([SavedPlace].self, from: data) {
            savedPlaces = places
        }
        if let data = defaults.data(forKey: "savedPlans"),
           let plans = try? JSONDecoder().decode([SavedPlan].self, from: data) {
            savedPlans = plans
        }
        if let data = defaults.data(forKey: "chargeSessions"),
           let sessions = try? JSONDecoder().decode([ChargeSession].self, from: data) {
            chargeSessions = sessions
        }

        var restored = PlannerSettings()
        if let trimRaw = defaults.string(forKey: "trim"),
           let trim = Ioniq5Trim(rawValue: trimRaw) {
            restored.trim = trim
        }
        if let v = defaults.object(forKey: "reserveSOC") as? Double { restored.reserveSOC = v }
        if let v = defaults.object(forKey: "maxChargeSOC") as? Double { restored.maxChargeSOC = v }
        if let v = defaults.object(forKey: "corridorRadiusMiles") as? Double { restored.corridorRadiusMiles = v }
        if let v = defaults.object(forKey: "referenceWhPerMi") as? Double { restored.referenceWhPerMi = v }
        if let v = defaults.object(forKey: "maxSpeedMph") as? Double { restored.maxSpeedMph = v }
        if let v = defaults.object(forKey: "weatherAdjustEnabled") as? Bool { restored.weatherAdjustEnabled = v }
        if let v = defaults.object(forKey: "minChargerKW") as? Double { restored.minChargerKW = v }
        if let v = defaults.object(forKey: "preferNACS") as? Bool { restored.preferNACS = v }
        if let v = defaults.object(forKey: "avoidTolls") as? Bool { restored.avoidTolls = v }
        if let v = defaults.object(forKey: "avoidHighways") as? Bool { restored.avoidHighways = v }
        settings = restored

        // Restore a previous BlueLink session, if any.
        if let username = KeychainStore.load(forKey: "username"),
           let password = KeychainStore.load(forKey: "password") {
            let pin = KeychainStore.load(forKey: "pin") ?? ""
            Task { await signIn(username: username, password: password, pin: pin, interactive: false) }
        }
    }

    private func persistSettings() {
        let defaults = UserDefaults.standard
        defaults.set(settings.trim.rawValue, forKey: "trim")
        defaults.set(settings.reserveSOC, forKey: "reserveSOC")
        defaults.set(settings.maxChargeSOC, forKey: "maxChargeSOC")
        defaults.set(settings.corridorRadiusMiles, forKey: "corridorRadiusMiles")
        defaults.set(settings.referenceWhPerMi, forKey: "referenceWhPerMi")
        defaults.set(settings.maxSpeedMph, forKey: "maxSpeedMph")
        defaults.set(settings.weatherAdjustEnabled, forKey: "weatherAdjustEnabled")
        defaults.set(settings.minChargerKW, forKey: "minChargerKW")
        defaults.set(settings.preferNACS, forKey: "preferNACS")
        defaults.set(settings.avoidTolls, forKey: "avoidTolls")
        defaults.set(settings.avoidHighways, forKey: "avoidHighways")
    }

    private func persist<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    // MARK: - BlueLink actions

    func signIn(username: String, password: String, pin: String, interactive: Bool = true) async {
        accountState = .signingIn
        lastError = nil
        await blueLink.setCredentials(username: username, password: password, pin: pin)
        do {
            try await blueLink.login()
            let vehicles = try await blueLink.fetchVehicles()
            // Prefer the EV if the account has several cars.
            vehicle = vehicles.first(where: { $0.isEV }) ?? vehicles[0]
            accountState = .signedIn
            KeychainStore.save(username, forKey: "username")
            KeychainStore.save(password, forKey: "password")
            KeychainStore.save(pin, forKey: "pin")
            await refreshStatus(force: false)
        } catch {
            accountState = .signedOut
            vehicle = nil
            if interactive {
                lastError = error.localizedDescription
            }
        }
    }

    func signOut() async {
        await blueLink.clearCredentials()
        KeychainStore.delete(forKey: "username")
        KeychainStore.delete(forKey: "password")
        KeychainStore.delete(forKey: "pin")
        accountState = .signedOut
        vehicle = nil
        status = nil
    }

    func refreshStatus(force: Bool) async {
        guard let vehicle, accountState == .signedIn, !isRefreshingStatus else { return }
        isRefreshingStatus = true
        defer { isRefreshingStatus = false }
        do {
            let fresh = try await blueLink.fetchStatus(for: vehicle, forceRefresh: force)
            status = fresh
            lastError = nil
            if let soc = fresh.socPercent {
                manualSOCPercent = soc  // keep the fallback in sync with reality
            }
            ChargingActivityController.sync(status: fresh, vehicleName: vehicle.nickname)
            recordChargeTransition(fresh)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Opens/closes charge-history sessions on charging state transitions.
    private func recordChargeTransition(_ fresh: BlueLinkStatus) {
        let charging = fresh.isCharging == true
        let openIndex = chargeSessions.firstIndex(where: { $0.isActive })

        if charging, openIndex == nil {
            chargeSessions.insert(ChargeSession(
                startDate: fresh.reportedAt ?? Date(),
                startSOC: fresh.socPercent ?? manualSOCPercent,
                batteryKWh: settings.trim.usableBatteryKWh
            ), at: 0)
        } else if !charging, let openIndex {
            chargeSessions[openIndex].endDate = fresh.reportedAt ?? Date()
            chargeSessions[openIndex].endSOC = fresh.socPercent
        } else if charging, let openIndex {
            // Refresh mid-charge: keep the running end SOC current so an
            // abandoned session still shows a sane final value.
            chargeSessions[openIndex].endSOC = fresh.socPercent
        } else {
            return
        }
        chargeSessions = Array(chargeSessions.prefix(100))
        persist(chargeSessions, key: "chargeSessions")
    }

    func deleteChargeSessions(at offsets: IndexSet) {
        chargeSessions.remove(atOffsets: offsets)
        persist(chargeSessions, key: "chargeSessions")
    }

    /// Runs a remote command with busy-state bookkeeping, then re-reads status.
    func runCommand(_ label: String, _ operation: @escaping (BlueLinkClient, BlueLinkVehicle) async throws -> Void) async {
        guard let vehicle, busyCommand == nil else { return }
        busyCommand = label
        lastError = nil
        do {
            try await operation(blueLink, vehicle)
            // The car takes a moment to act; give it a beat, then re-poll.
            try? await Task.sleep(for: .seconds(8))
            busyCommand = nil
            await refreshStatus(force: false)
        } catch {
            busyCommand = nil
            lastError = error.localizedDescription
        }
    }

    // MARK: - Route planning

    func planRoute(to destination: MKMapItem) async {
        planState = .planning
        plannedRoute = nil
        do {
            // Candidate origins, best first; the planner tries each until
            // Apple Maps produces a route.
            var origins: [MKMapItem] = []
            let currentLocation = await LocationProvider.shared.currentLocation()
            if let currentLocation {
                origins.append(MKMapItem(placemark: MKPlacemark(coordinate: currentLocation.coordinate)))
            }
            origins.append(MKMapItem.forCurrentLocation())
            if let lat = status?.latitude, let lon = status?.longitude {
                origins.append(MKMapItem(placemark: MKPlacemark(
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)
                )))
            }
            let weatherMult = await weatherMultiplier(near: currentLocation)
            let route = try await planner.plan(
                from: origins,
                to: destination,
                startSOC: effectiveSOCFraction,
                settings: settings,
                weatherMultiplier: weatherMult
            )
            plannedRoute = route
            planState = .planned
            rememberDestination(destination)
        } catch {
            planState = .failed(error.localizedDescription)
        }
    }

    private func rememberDestination(_ destination: MKMapItem) {
        let coord = destination.placemark.coordinate
        let recent = RecentDestination(
            name: destination.name ?? "Destination",
            subtitle: destination.placemark.title ?? "",
            latitude: coord.latitude,
            longitude: coord.longitude
        )
        var recents = recentDestinations.filter { $0.name != recent.name }
        recents.insert(recent, at: 0)
        recentDestinations = Array(recents.prefix(6))
        if let data = try? JSONEncoder().encode(recentDestinations) {
            UserDefaults.standard.set(data, forKey: "recentDestinations")
        }
    }

    func clearPlan() {
        plannedRoute = nil
        planState = .idle
        departureSOCOverride = nil
    }

    /// Ambient-temperature consumption multiplier via WeatherKit; 1.0 when
    /// disabled, unavailable, or not yet entitled.
    private func weatherMultiplier(near location: CLLocation?) async -> Double {
        lastPlanTempF = nil
        guard settings.weatherAdjustEnabled, let location else { return 1.0 }
        guard let weather = try? await WeatherService.shared.weather(for: location, including: .current) else {
            return 1.0
        }
        let tempF = weather.temperature.converted(to: .fahrenheit).value
        lastPlanTempF = tempF
        return PlannerSettings.weatherMultiplier(tempF: tempF)
    }

    // MARK: - Saved places & plans

    func place(_ kind: SavedPlace.Kind) -> SavedPlace? {
        savedPlaces.first { $0.kind == kind }
    }

    func setPlace(_ place: SavedPlace) {
        savedPlaces.removeAll { $0.kind == place.kind }
        savedPlaces.append(place)
        persist(savedPlaces, key: "savedPlaces")
    }

    func removePlace(_ kind: SavedPlace.Kind) {
        savedPlaces.removeAll { $0.kind == kind }
        persist(savedPlaces, key: "savedPlaces")
    }

    /// Snapshots the current planned route into Saved Plans.
    func saveCurrentPlan() {
        guard let route = plannedRoute else { return }
        let plan = SavedPlan(
            destinationName: route.destinationName,
            subtitle: "",
            latitude: route.destinationCoordinate.latitude,
            longitude: route.destinationCoordinate.longitude,
            savedAt: Date(),
            snapshotTotalMiles: route.totalMiles,
            snapshotStopCount: route.stops.count,
            snapshotTotalMinutes: route.totalMinutes
        )
        var plans = savedPlans.filter { $0.destinationName != plan.destinationName }
        plans.insert(plan, at: 0)
        savedPlans = Array(plans.prefix(20))
        persist(savedPlans, key: "savedPlans")
    }

    func deleteSavedPlans(at offsets: IndexSet) {
        savedPlans.remove(atOffsets: offsets)
        persist(savedPlans, key: "savedPlans")
    }

    /// Plans a trip to a stored coordinate (saved place / plan / recent).
    func planRoute(toName name: String, latitude: Double, longitude: Double) async {
        let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
        let item = MKMapItem(placemark: placemark)
        item.name = name
        await planRoute(to: item)
    }

    // MARK: - Map chargers

    /// Chargers for the plan map's pin layer.
    func mapChargers(near center: CLLocationCoordinate2D, radiusMiles: Double) async -> [ChargingStation] {
        (try? await nrel.fastChargers(near: center, radiusMiles: min(radiusMiles, 100), limit: 100)) ?? []
    }

    // MARK: - Nearby chargers (used by CarPlay and the map)

    func nearbyChargers() async -> [ChargingStation] {
        guard let location = await LocationProvider.shared.currentLocation() else { return [] }
        let stations = (try? await nrel.fastChargers(
            near: location.coordinate,
            radiusMiles: 25
        )) ?? []
        let here = location.coordinate
        return stations.sorted {
            RoutePath.miles($0.coordinate, here) < RoutePath.miles($1.coordinate, here)
        }
    }
}
