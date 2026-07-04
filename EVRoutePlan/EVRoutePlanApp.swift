import SwiftUI

@main
struct EVRoutePlanApp: App {
    @State private var appState = AppState.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .task {
                    LocationProvider.shared.requestAuthorization()
                }
        }
    }
}

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            VehicleStatusView()
                .tabItem { Label("My Car", systemImage: "bolt.car") }
            RoutePlanView()
                .tabItem { Label("Plan", systemImage: "map") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

// MARK: - Small shared formatting helpers

enum Format {
    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    static func minutes(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        if total < 60 { return "\(total) min" }
        return "\(total / 60) hr \(total % 60) min"
    }

    static func miles(_ miles: Double) -> String {
        String(format: "%.0f mi", miles)
    }

    static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
