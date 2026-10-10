//
//  WidgetStatusDebugView.swift
//  BetterBlue
//
//  Debug screen for dialing in the widget's status section (range line,
//  percentage bars, charging bar). Renders the real `VehicleStatusColumn`
//  with live controls — runs in the app under the reliable BetterBlue
//  scheme, sidestepping flaky widget-extension previews.
//

import SwiftUI

struct WidgetStatusDebugView: View {
    @State private var isPHEV = false
    @State private var isSmall = false
    @State private var isCharging = true
    @State private var battery = 60.0
    @State private var targetSOC = 80.0
    @State private var chargeKw = 50.0
    @State private var minutes = 90.0
    @State private var gas = 50.0
    @State private var locked = true
    @State private var climateOn = false
    @State private var showEVPercent = true
    @State private var showGasPercent = true

    private var data: StatusSectionData {
        StatusSectionData(
            hasElectricCapability: true,
            evRange: "\(Int(battery * 2.5)) mi",
            evBatteryPercentage: battery,
            gasRange: isPHEV ? "\(Int(gas * 3)) mi" : nil,
            gasFuelPercentage: isPHEV ? gas : nil,
            rangeText: "\(Int(battery * 2.5)) mi",
            batteryPercentage: battery,
            isCharging: isCharging,
            chargeSpeedKilowatts: isCharging ? chargeKw : nil,
            chargeTimeRemainingMinutes: isCharging ? Int(minutes) : nil,
            targetStateOfCharge: isCharging ? Int(targetSOC) : nil,
            isLocked: locked,
            isClimateOn: climateOn,
            chargingColor: .green,
            gasColor: .orange,
            showEVPercent: showEVPercent,
            showGasPercent: showGasPercent
        )
    }

    var body: some View {
        Form {
            Section("Preview") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Hyundai IONIQ 5")
                        .font(isSmall ? .caption : .headline)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                    VehicleStatusColumn(
                        data: data,
                        textColor: .white,
                        isSmall: isSmall,
                        leadingTime: isSmall ? "9:41 AM" : nil
                    )
                    .frame(width: isSmall ? 130 : 230, alignment: isSmall ? .center : .trailing)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16).fill(
                        LinearGradient(
                            colors: [Color(red: 0.11, green: 0.11, blue: 0.12),
                                     Color(red: 0.17, green: 0.17, blue: 0.18)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            }

            Section("Vehicle") {
                Picker("Fuel", selection: $isPHEV) {
                    Text("EV").tag(false)
                    Text("PHEV").tag(true)
                }
                .pickerStyle(.segmented)
                Toggle("Small (2×2) layout", isOn: $isSmall)
                Toggle("Charging", isOn: $isCharging)
                Toggle("Locked", isOn: $locked)
                Toggle("Climate on", isOn: $climateOn)
                Toggle("Show EV %", isOn: $showEVPercent)
                if isPHEV {
                    Toggle("Show gas %", isOn: $showGasPercent)
                }
            }

            Section("Values") {
                slider("Battery", $battery, 0 ... 100, "%")
                slider("Target SOC", $targetSOC, 0 ... 100, "%")
                slider("Charge speed", $chargeKw, 0 ... 250, "kW")
                slider("Time remaining", $minutes, 0 ... 600, "min")
                if isPHEV {
                    slider("Gas", $gas, 0 ... 100, "%")
                }
            }
        }
        .navigationTitle("Widget Status")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func slider(
        _ title: String,
        _ value: Binding<Double>,
        _ range: ClosedRange<Double>,
        _ unit: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value.wrappedValue)) \(unit)").foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }
}

#Preview {
    NavigationStack { WidgetStatusDebugView() }
}
