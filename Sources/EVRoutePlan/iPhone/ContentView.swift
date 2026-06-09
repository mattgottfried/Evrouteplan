import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            RoutePlanView()
                .tabItem { Label("Plan", systemImage: "map.fill") }

            VehicleStatusView()
                .tabItem { Label("Vehicle", systemImage: "bolt.car.fill") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .task {
            await appState.refreshBluelinkStatus()
        }
    }
}
