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
                    sliderRow("Highway range factor",
                              value: $appState.settings.rangeFactor,
                              range: 0.6...1.0, step: 0.05,
                              display: Format.percent(appState.settings.rangeFactor))
                    sliderRow("Arrival reserve",
                              value: $appState.settings.reserveSOC,
                              range: 0.05...0.30, step: 0.05,
                              display: Format.percent(appState.settings.reserveSOC))
                    sliderRow("Charge up to",
                              value: $appState.settings.maxChargeSOC,
                              range: 0.60...1.0, step: 0.05,
                              display: Format.percent(appState.settings.maxChargeSOC))
                    sliderRow("Charger detour limit",
                              value: $appState.settings.corridorRadiusMiles,
                              range: 5...30, step: 1,
                              display: Format.miles(appState.settings.corridorRadiusMiles))
                } header: {
                    Text("Route Planning")
                } footer: {
                    Text("Range factor accounts for highway speed and climate use — 85% of EPA is a good default. Charging above 80% is slow, so long trips usually plan faster with the cap at 80%.")
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
