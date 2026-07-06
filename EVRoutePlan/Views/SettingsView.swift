import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        NavigationStack {
            Form {
                Section("Vehicle") {
                    Picker("Trim", selection: $appState.settings.trim) {
                        ForEach(Ioniq5Trim.allCases) { trim in
                            Text(trim.rawValue).tag(trim)
                        }
                    }
                    LabeledContent("EPA range", value: Format.miles(appState.settings.trim.epaRangeMiles))
                    LabeledContent("Planning range",
                                   value: Format.miles(appState.settings.usableRangeMiles))
                }

                Section {
                    sliderRow("Consumption",
                              value: whPerMiBinding,
                              range: 200...400, step: 1,
                              display: "\(Int(appState.settings.effectiveWhPerMi)) Wh/mi")
                    sliderRow("Max cruise speed",
                              value: $appState.settings.maxSpeedMph,
                              range: 65...85, step: 1,
                              display: "\(Int(appState.settings.maxSpeedMph)) mph")
                    Toggle("Weather-adjusted range", isOn: $appState.settings.weatherAdjustEnabled)
                    Button("Reset consumption to EPA default") {
                        appState.settings.referenceWhPerMi = 0
                    }
                    .font(.subheadline)
                } header: {
                    Text("Consumption Model")
                } footer: {
                    Text("Reference consumption at 65 mph, 70°F — the EPA default for your trim is \(Int(appState.settings.trim.defaultWhPerMi)) Wh/mi (ABRP uses 257 for the Ioniq 5). Speed and weather scale it: higher cruise speed and extreme temperatures shrink planning range. Reserve, charge ceiling, and charger rules live in the Plan tab's Options.")
                }

                Section("History") {
                    NavigationLink {
                        HistoryView()
                    } label: {
                        Label("Drive & Charge History", systemImage: "clock.arrow.circlepath")
                    }
                }

                Section {
                    sliderRow("Battery now",
                              value: $appState.manualSOCPercent,
                              range: 5...100, step: 5,
                              display: "\(Int(appState.manualSOCPercent))%")
                } header: {
                    Text("Manual Battery Level")
                } footer: {
                    Text(appState.hasLiveSOC
                         ? "BlueLink is connected — the live battery level is used automatically and this slider only acts as a fallback."
                         : "Used for planning until BlueLink reports the live level.")
                }

                Section {
                    SecureField("NREL API key", text: $appState.nrelAPIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Charging Station Data")
                } footer: {
                    Text("Free instant key from developer.nlr.gov/signup — powers the US DOE charger database (same source ABRP uses for US chargers). Keys issued on the old developer.nrel.gov domain keep working.")
                }

                if appState.accountState == .signedIn {
                    Section("BlueLink") {
                        if let vehicle = appState.vehicle {
                            LabeledContent("Vehicle", value: vehicle.nickname)
                            LabeledContent("VIN", value: vehicle.vin)
                        }
                        Button("Sign Out", role: .destructive) {
                            Task { await appState.signOut() }
                        }
                    }
                }

                Section {
                    LabeledContent("Version", value: appVersion)
                } footer: {
                    Text("Personal-use EV companion for the 2026 Ioniq 5. Vehicle data via Hyundai BlueLink; charger data via the US DOE/NREL station database.")
                }
            }
            .navigationTitle("Settings")
        }
    }

    /// 0 means "EPA default" in storage; expose the resolved value to the slider.
    private var whPerMiBinding: Binding<Double> {
        Binding(
            get: { appState.settings.effectiveWhPerMi },
            set: { appState.settings.referenceWhPerMi = $0 }
        )
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func sliderRow(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        display: String
    ) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title)
                Spacer()
                Text(display).foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
        }
    }
}
