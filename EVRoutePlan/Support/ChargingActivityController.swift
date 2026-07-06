import ActivityKit
import Foundation

/// Starts, updates, and ends the charging Live Activity from vehicle status.
/// Called on every BlueLink status refresh — the activity begins when the
/// car reports charging and ends when it stops.
///
/// Updates arrive when the app refreshes status (there's no push backend),
/// so the countdown timer carries the live information between refreshes;
/// staleDate dims the activity if it hasn't been refreshed in a while.
@MainActor
enum ChargingActivityController {
    static func sync(status: BlueLinkStatus, vehicleName: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let existing = Activity<ChargingActivityAttributes>.activities.first

        guard status.isCharging == true else {
            if let existing {
                let finalContent = existing.content
                Task { await existing.end(finalContent, dismissalPolicy: .default) }
            }
            return
        }

        let state = ChargingActivityAttributes.ContentState(
            socPercent: Int(status.socPercent ?? 0),
            limitPercent: status.dcChargeLimit,
            chargeEndDate: status.minutesToTargetSOC.flatMap { minutes in
                minutes > 0 ? Date().addingTimeInterval(Double(minutes) * 60) : nil
            },
            rangeMiles: status.rangeMiles.map { Int($0) }
        )
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(90 * 60))

        if let existing {
            Task { await existing.update(content) }
        } else {
            let attributes = ChargingActivityAttributes(vehicleName: vehicleName)
            _ = try? Activity<ChargingActivityAttributes>.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
        }
    }
}
