import Foundation

/// Vehicle state snapshot shared between the app and the widget extension
/// through the App Group container. The app writes it on every BlueLink
/// refresh; the home-screen widget reads it on each timeline reload.
struct VehicleSnapshot: Codable {
    static let appGroupID = "group.com.mattgottfried.EVRoutePlan"
    private static let key = "vehicleSnapshot"

    var socPercent: Int
    var rangeMiles: Int?
    var isCharging: Bool
    var isPluggedIn: Bool
    var vehicleName: String
    var updatedAt: Date

    func save() {
        guard let defaults = UserDefaults(suiteName: Self.appGroupID),
              let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key)
    }

    static func load() -> VehicleSnapshot? {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(VehicleSnapshot.self, from: data)
    }
}
