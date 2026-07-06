import AppIntents
import Foundation

/// Siri / Shortcuts / Action Button support. In-app intents: the system
/// launches the app in the background and runs these against the live
/// AppState + BlueLink client.

/// AppState kicks off an automatic sign-in at launch; give it a moment to
/// settle before commands run.
@MainActor
private func readyAppState() async -> AppState {
    let state = AppState.shared
    for _ in 0..<20 {
        if state.accountState != .signingIn { break }
        try? await Task.sleep(for: .milliseconds(500))
    }
    return state
}

@MainActor
private func performCarCommand(
    success: String,
    _ operation: (BlueLinkClient, BlueLinkVehicle) async throws -> Void
) async -> String {
    let state = await readyAppState()
    guard state.accountState == .signedIn, let vehicle = state.vehicle else {
        return "You're not signed in to BlueLink — open EV Route Plan first."
    }
    do {
        try await operation(state.blueLink, vehicle)
        return success
    } catch {
        return "That didn't work: \(error.localizedDescription)"
    }
}

// MARK: - Intents

struct GetBatteryIntent: AppIntent {
    static let title: LocalizedStringResource = "Check Battery"
    static let description = IntentDescription("Reads the car's battery level, range, and charging state from BlueLink.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let state = await readyAppState()
        guard state.accountState == .signedIn else {
            return .result(dialog: "You're not signed in to BlueLink — open EV Route Plan first.")
        }
        await state.refreshStatus(force: false)
        guard let status = state.status, let soc = status.socPercent else {
            return .result(dialog: "I couldn't reach the car right now.")
        }
        var parts = ["Battery is at \(Int(soc)) percent"]
        if let range = status.rangeMiles { parts.append("\(Int(range)) miles of range") }
        if status.isCharging == true {
            parts.append("charging now")
        } else if status.isPluggedIn == true {
            parts.append("plugged in")
        }
        return .result(dialog: IntentDialog(stringLiteral: parts.joined(separator: ", ") + "."))
    }
}

struct LockCarIntent: AppIntent {
    static let title: LocalizedStringResource = "Lock Car"
    static let description = IntentDescription("Locks the car's doors via BlueLink.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await performCarCommand(success: "Lock command sent to the car.") { client, vehicle in
            try await client.lock(vehicle)
        }
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct UnlockCarIntent: AppIntent {
    static let title: LocalizedStringResource = "Unlock Car"
    static let description = IntentDescription("Unlocks the car's doors via BlueLink.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await performCarCommand(success: "Unlock command sent to the car.") { client, vehicle in
            try await client.unlock(vehicle)
        }
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct StartClimateIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Climate"
    static let description = IntentDescription("Starts remote climate using your first preset.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let preset = AppState.shared.climatePresets.first
            ?? ClimatePreset(name: "Comfort", tempF: 70, defrost: false)
        let message = await performCarCommand(
            success: "Starting climate at \(preset.tempF) degrees."
        ) { client, vehicle in
            try await client.startClimate(vehicle, tempF: preset.tempF, defrost: preset.defrost)
        }
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct StopClimateIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Climate"
    static let description = IntentDescription("Stops remote climate.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await performCarCommand(success: "Climate stopped.") { client, vehicle in
            try await client.stopClimate(vehicle)
        }
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct StartChargeIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Charging"
    static let description = IntentDescription("Starts charging if the car is plugged in.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await performCarCommand(success: "Charging started.") { client, vehicle in
            try await client.startCharge(vehicle)
        }
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct StopChargeIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Charging"
    static let description = IntentDescription("Stops an active charging session.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await performCarCommand(success: "Charging stopped.") { client, vehicle in
            try await client.stopCharge(vehicle)
        }
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

// MARK: - Siri phrases

struct CarShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetBatteryIntent(),
            phrases: [
                "Check my battery in \(.applicationName)",
                "What's my battery in \(.applicationName)",
                "Check my car in \(.applicationName)",
            ],
            shortTitle: "Battery",
            systemImageName: "bolt.batteryblock.fill"
        )
        AppShortcut(
            intent: LockCarIntent(),
            phrases: ["Lock my car in \(.applicationName)"],
            shortTitle: "Lock",
            systemImageName: "lock.fill"
        )
        AppShortcut(
            intent: StartClimateIntent(),
            phrases: [
                "Start climate in \(.applicationName)",
                "Warm up my car in \(.applicationName)",
                "Cool down my car in \(.applicationName)",
            ],
            shortTitle: "Climate",
            systemImageName: "fan.fill"
        )
        AppShortcut(
            intent: StartChargeIntent(),
            phrases: ["Start charging in \(.applicationName)"],
            shortTitle: "Charge",
            systemImageName: "bolt.fill"
        )
    }
}
