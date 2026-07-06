import ActivityKit
import Foundation

/// Data contract between the app (which starts/updates the Live Activity)
/// and the ChargingWidget extension (which renders it). Compiled into both
/// targets.
struct ChargingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Battery state of charge, 0–100.
        var socPercent: Int
        /// DC charge limit the car will stop at, e.g. 80. Nil if unknown.
        var limitPercent: Int?
        /// When the car expects to reach the limit — rendered as a live
        /// countdown so it stays useful even between app refreshes.
        var chargeEndDate: Date?
        /// EPA range at the current charge, miles.
        var rangeMiles: Int?
    }

    /// Vehicle nickname, fixed for the life of the activity.
    var vehicleName: String
}
