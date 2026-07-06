import CoreLocation
import Foundation
import MapKit
import Observation

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

    /// SOC used for planning: live from the car when we have it, else manual.
    var effectiveSOCFraction: Double {
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

        var restored = PlannerSettings()
        if let trimRaw = defaults.string(forKey: "trim"),
           let trim = Ioniq5Trim(rawValue: trimRaw) {
            restored.trim = trim
        }
        if let v = defaults.object(forKey: "reserveSOC") as? Double { restored.reserveSOC = v }
        if let v = defaults.object(forKey: "maxChargeSOC") as? Double { restored.maxChargeSOC = v }
        if let v = defaults.object(forKey: "rangeFactor") as? Double { restored.rangeFactor = v }
        if let v = defaults.object(forKey: "corridorRadiusMiles") as? Double { restored.corridorRadiusMiles = v }
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
        defaults.set(settings.rangeFactor, forKey: "rangeFactor")
        defaults.set(settings.corridorRadiusMiles, forKey: "corridorRadiusMiles")
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
        } catch {
            lastError = error.localizedDescription
        }
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
            if let location = await LocationProvider.shared.currentLocation() {
                origins.append(MKMapItem(placemark: MKPlacemark(coordinate: location.coordinate)))
            }
            origins.append(MKMapItem.forCurrentLocation())
            if let lat = status?.latitude, let lon = status?.longitude {
                origins.append(MKMapItem(placemark: MKPlacemark(
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)
                )))
            }
            let route = try await planner.plan(
                from: origins,
                to: destination,
                startSOC: effectiveSOCFraction,
                settings: settings
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
