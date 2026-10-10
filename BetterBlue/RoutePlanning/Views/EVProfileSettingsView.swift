//
//  EVProfileSettingsView.swift
//  BetterBlue
//

import SwiftUI

struct EVProfileSettingsView: View {
    let vin: String
    let model: String

    @State private var profile: EVProfile

    init(vin: String, model: String) {
        self.vin = vin
        self.model = model
        _profile = State(initialValue: EVProfileStore.profile(forVIN: vin, model: model))
    }

    var body: some View {
        Form {
            Section {
                Picker("Preset", selection: presetBinding) {
                    ForEach(EVProfile.presets, id: \.name) { preset in
                        Text(preset.name).tag(preset.name)
                    }
                    if !EVProfile.presets.contains(where: { $0.name == profile.name }) {
                        Text(profile.name).tag(profile.name)
                    }
                }
            } footer: {
                Text("Start from the closest match, then adjust below if your car differs.")
            }

            Section("Battery & Charging") {
                numberRow("Usable battery", value: $profile.usableBatteryKWh, unit: "kWh", range: 20...150)
                numberRow("Rated range", value: $profile.ratedRangeMiles, unit: "mi", range: 50...600)
                numberRow("Max DC charging", value: $profile.maxDCKW, unit: "kW", range: 20...400)
            }

            Section {
                percentRow("Charge to at stops", value: $profile.targetSOC, range: 0.5...1)
                percentRow("Arrival reserve", value: $profile.arrivalReserveSOC, range: 0.05...0.3)
            } header: {
                Text("Planning")
            } footer: {
                Text("Range is taken from the car's live estimate when available, which accounts for weather and driving style; the rated range is the fallback.")
            }
        }
        .navigationTitle("Vehicle Profile")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: profile) { _, new in EVProfileStore.save(new, forVIN: vin) }
    }

    private var presetBinding: Binding<String> {
        Binding {
            profile.name
        } set: { name in
            guard let preset = EVProfile.presets.first(where: { $0.name == name }) else { return }
            var updated = preset
            updated.targetSOC = profile.targetSOC
            updated.arrivalReserveSOC = profile.arrivalReserveSOC
            profile = updated
        }
    }

    private func numberRow(_ title: String, value: Binding<Double>, unit: String, range: ClosedRange<Double>) -> some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField(title, value: value, format: .number.precision(.fractionLength(0...1)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 80)
                    .onChange(of: value.wrappedValue) { _, new in
                        let clamped = min(max(new, range.lowerBound), range.upperBound)
                        if clamped != new { value.wrappedValue = clamped }
                    }
                Text(unit).foregroundStyle(.secondary)
            }
        }
    }

    private func percentRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading) {
            LabeledContent(title, value: RouteFormat.percent(value.wrappedValue))
            Slider(value: value, in: range, step: 0.05)
        }
    }
}
