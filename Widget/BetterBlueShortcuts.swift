//
//  BetterBlueShortcuts.swift
//  BetterBlueWidget
//
//  AppShortcutsProvider — registers default Siri voice phrases for
//  every user-facing vehicle command. This is what makes "Hey Siri,
//  lock my car" work without the user having to manually create a
//  Shortcut and assign a phrase first.
//
//  Per Apple's design, each AppShortcut needs:
//    1. An intent to perform
//    2. One or more `phrases` — the EXACT Siri trigger phrases.
//       `\(.applicationName)` is required somewhere in each phrase
//       (we accept either "BetterBlue", "Better Blue", or any
//       localized app name the user has set).
//    3. A short title + system image, used in the in-app Shortcuts
//       gallery and in Spotlight.
//
//  We deliberately ship MANY phrasing variants so single-vehicle
//  users get one-shot voice control without thinking — Siri matches
//  whichever the user happens to say. The `\(\.$vehicle)` form is
//  the parameterized variant that lets multi-vehicle users say
//  "lock my Hyundai" / "lock the Kia."
//

import AppIntents

struct BetterBlueShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        // MARK: - Lock / Unlock
        AppShortcut(
            intent: LockVehicleControlIntent(),
            phrases: [
                "Lock my car in \(.applicationName)",
                "Lock the car in \(.applicationName)",
                "Lock the doors in \(.applicationName)",
                "Lock my \(\.$vehicle) in \(.applicationName)",
                "Lock \(\.$vehicle) in \(.applicationName)"
            ],
            shortTitle: "Lock Vehicle",
            systemImageName: "lock.fill"
        )
        AppShortcut(
            intent: UnlockVehicleControlIntent(),
            phrases: [
                "Unlock my car in \(.applicationName)",
                "Unlock the car in \(.applicationName)",
                "Unlock the doors in \(.applicationName)",
                "Unlock my \(\.$vehicle) in \(.applicationName)",
                "Unlock \(\.$vehicle) in \(.applicationName)"
            ],
            shortTitle: "Unlock Vehicle",
            systemImageName: "lock.open.fill"
        )

        // MARK: - Climate
        // No default-vehicle `StartClimate` phrase — `StartClimateControlIntent`
        // takes a `ClimatePresetEntity`, not a vehicle, so Siri has to
        // disambiguate by preset name. The phrasings reflect that.
        AppShortcut(
            intent: StartClimateControlIntent(),
            phrases: [
                "Start the AC in \(.applicationName)",
                "Start climate in \(.applicationName)",
                "Turn on climate in \(.applicationName)",
                "Warm up my car in \(.applicationName)",
                "Cool down my car in \(.applicationName)",
                "Pre-condition my car in \(.applicationName)",
                "Start \(\.$preset) in \(.applicationName)"
            ],
            shortTitle: "Start Climate",
            systemImageName: "fan"
        )
        AppShortcut(
            intent: StopClimateControlIntent(),
            phrases: [
                "Stop the climate in \(.applicationName)",
                "Turn off climate in \(.applicationName)",
                "Stop the AC in \(.applicationName)",
                "Stop \(\.$vehicle) climate in \(.applicationName)"
            ],
            shortTitle: "Stop Climate",
            systemImageName: "fan.slash"
        )

        // MARK: - Charging
        AppShortcut(
            intent: StartChargeControlIntent(),
            phrases: [
                "Start charging in \(.applicationName)",
                "Start charging my car in \(.applicationName)",
                "Begin charging in \(.applicationName)",
                "Charge my car in \(.applicationName)",
                "Charge \(\.$vehicle) in \(.applicationName)"
            ],
            shortTitle: "Start Charging",
            systemImageName: "bolt.fill"
        )
        AppShortcut(
            intent: StopChargeControlIntent(),
            phrases: [
                "Stop charging in \(.applicationName)",
                "Stop charging my car in \(.applicationName)",
                "Stop charging \(\.$vehicle) in \(.applicationName)"
            ],
            shortTitle: "Stop Charging",
            systemImageName: "bolt.slash"
        )

        // MARK: - Status
        AppShortcut(
            intent: GetVehicleStatusIntent(),
            phrases: [
                "Check my car in \(.applicationName)",
                "Car status in \(.applicationName)",
                "Vehicle status in \(.applicationName)",
                "Is my car locked in \(.applicationName)",
                "Is my car charging in \(.applicationName)",
                "What's my battery level in \(.applicationName)",
                "How much battery is left in \(.applicationName)",
                "What's my range in \(.applicationName)",
                "Check \(\.$vehicle) in \(.applicationName)"
            ],
            shortTitle: "Get Vehicle Status",
            systemImageName: "car.fill"
        )
        AppShortcut(
            intent: RefreshVehicleStatusIntent(),
            phrases: [
                "Refresh my car in \(.applicationName)",
                "Refresh vehicle status in \(.applicationName)",
                "Update my car status in \(.applicationName)",
                "Refresh \(\.$vehicle) in \(.applicationName)"
            ],
            shortTitle: "Refresh Vehicle",
            systemImageName: "arrow.clockwise"
        )

        // MARK: - Property queries
        //
        // Apple caps AppShortcutsProvider at 10 entries per app, so
        // only the two most-commonly-spoken status queries get
        // default Siri phrases registered here. The remaining
        // direct-property intents (IsCharging, IsLocked,
        // GetVehicleRange, GetChargeTimeRemaining, IsClimateOn)
        // still appear as first-class actions in the Shortcuts
        // library — users can add their own custom Siri phrase to
        // any of them via Shortcuts → "Add to Siri."
        AppShortcut(
            intent: IsVehiclePluggedInIntent(),
            phrases: [
                "Is my car plugged in in \(.applicationName)",
                "Is the car plugged in in \(.applicationName)",
                "Is \(\.$vehicle) plugged in in \(.applicationName)"
            ],
            shortTitle: "Is Plugged In",
            systemImageName: "powerplug.fill"
        )
        AppShortcut(
            intent: GetBatteryPercentageIntent(),
            phrases: [
                "Get my battery level in \(.applicationName)",
                "What's my battery in \(.applicationName)",
                "Get battery for \(\.$vehicle) in \(.applicationName)"
            ],
            shortTitle: "Battery Percentage",
            systemImageName: "battery.75percent"
        )
    }
}
