import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var showManualSOC = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Vehicle") {
                    Picker("Variant", selection: Bindable(appState).vehicleVariant) {
                        ForEach(Ioniq5Config.Variant.allCases, id: \.self) { variant in
                            Text(variant.rawValue).tag(variant)
                        }
                    }

                    LabeledContent("Battery Capacity",
                        value: String(format: "%.1f kWh", appState.vehicleVariant.batteryKWh))
                    LabeledContent("EPA Range",
                        value: String(format: "%.0f mi", appState.vehicleVariant.epaRangeMiles))
                }

                Section("State of Charge") {
                    Toggle("Manual Override", isOn: $showManualSOC)
                        .onChange(of: showManualSOC) { _, on in
                            if !on { appState.manualSOCOverride = nil }
                        }

                    if showManualSOC {
                        let binding = Binding<Double>(
                            get: { appState.manualSOCOverride ?? 0.80 },
                            set: { appState.manualSOCOverride = $0 }
                        )
                        VStack(alignment: .leading) {
                            Text("SOC: \(Int((appState.manualSOCOverride ?? 0.80) * 100))%")
                                .font(.subheadline)
                            Slider(value: binding, in: 0.05...1.0, step: 0.01)
                        }
                    }
                }

                Section("BlueLink") {
                    let state = appState.bluelinkService.connectionState
                    LabeledContent("Status", value: state.label)
                    if case .connected = state {
                        Button("Disconnect", role: .destructive) {
                            appState.bluelinkService.disconnect()
                        }
                    }
                }

                Section("About") {
                    LabeledContent("Charging Data", value: "NREL Alternative Fuel Stations API")
                    LabeledContent("Vehicle API", value: "BetterBlueKit (Hyundai BlueLink)")
                    LabeledContent("Version", value: "1.0")
                }
            }
            .navigationTitle("Settings")
        }
    }
}

extension BluelinkService.ConnectionState {
    var label: String {
        switch self {
        case .disconnected: return "Not connected"
        case .connecting:   return "Connecting…"
        case .connected:    return "Connected"
        case .refreshing:   return "Refreshing…"
        case .failed:       return "Error"
        }
    }
}
