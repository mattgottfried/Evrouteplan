//
//  RoutePlanningSettings.swift
//  BetterBlue
//

import Foundation
import Observation

@MainActor
@Observable
final class RoutePlanningSettings {
    static let shared = RoutePlanningSettings()

    private let defaults = UserDefaults.standard
    private static let apiKeyKey = "routePlanning.nrelAPIKey"
    private static let mapAppKey = "routePlanning.mapApp"

    /// Runtime override typed into Settings; empty means "use the build key".
    var nrelAPIKeyOverride: String {
        didSet { defaults.set(nrelAPIKeyOverride, forKey: Self.apiKeyKey) }
    }

    var preferredMapApp: MapApp {
        didSet { defaults.set(preferredMapApp.rawValue, forKey: Self.mapAppKey) }
    }

    /// Key injected at build time from `NREL_API_KEY` in Config/Local.xcconfig.
    var buildAPIKey: String {
        let key = Bundle.main.object(forInfoDictionaryKey: "BBNRELAPIKey") as? String ?? ""
        return key.hasPrefix("$(") || key.hasPrefix("YOUR_") ? "" : key
    }

    var nrelAPIKey: String {
        let override = nrelAPIKeyOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        return override.isEmpty ? buildAPIKey : override
    }

    private init() {
        nrelAPIKeyOverride = defaults.string(forKey: Self.apiKeyKey) ?? ""
        preferredMapApp = defaults.string(forKey: Self.mapAppKey).flatMap(MapApp.init(rawValue:)) ?? .appleMaps
    }
}
