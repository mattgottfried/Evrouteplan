import Foundation
import MapKit
import Observation

@MainActor
@Observable
final class AppState {
    static let shared = AppState()

    enum RoutePlanningState: Equatable {
        case idle
        case planning
        case done
        case failed(String)
    }

    // Services
    let bluelinkService: BluelinkService
    let nrelService: NRELService
    let routePlannerService: RoutePlannerService

    // Route planning
    var plannedRoute: PlannedRoute?
    var routePlanningState: RoutePlanningState = .idle
    var nearbyStations: [ChargingStation] = []

    // User preferences (persisted in UserDefaults)
    var vehicleVariant: Ioniq5Config.Variant {
        didSet { UserDefaults.standard.set(vehicleVariant.rawValue, forKey: "vehicleVariant") }
    }
    var manualSOCOverride: Double? {
        didSet {
            if let v = manualSOCOverride {
                UserDefaults.standard.set(v, forKey: "manualSOC")
            } else {
                UserDefaults.standard.removeObject(forKey: "manualSOC")
            }
        }
    }

    var effectiveSOCFraction: Double {
        if let override = manualSOCOverride { return override }
        return bluelinkService.currentSOCFraction ?? 0.80
    }

    private init() {
        let apiKey = Bundle.main.infoDictionary?["NREL_API_KEY"] as? String ?? ""
        let nrel = NRELService(apiKey: apiKey)
        self.bluelinkService = BluelinkService()
        self.nrelService = nrel
        self.routePlannerService = RoutePlannerService(nrelService: nrel)

        let savedVariant = UserDefaults.standard.string(forKey: "vehicleVariant")
            .flatMap(Ioniq5Config.Variant.init(rawValue:)) ?? Ioniq5Config.defaultVariant
        self.vehicleVariant = savedVariant

        let savedSOC = UserDefaults.standard.object(forKey: "manualSOC") as? Double
        self.manualSOCOverride = savedSOC
    }

    func planRoute(to destination: MKMapItem) async {
        routePlanningState = .planning
        do {
            let route = try await routePlannerService.planRoute(
                to: destination,
                currentSOCFraction: effectiveSOCFraction,
                variant: vehicleVariant
            )
            self.plannedRoute = route
            routePlanningState = .done
        } catch {
            routePlanningState = .failed(error.localizedDescription)
        }
    }

    func refreshBluelinkStatus() async {
        guard case .connected = bluelinkService.connectionState else { return }
        try? await bluelinkService.refreshStatus()
    }
}
