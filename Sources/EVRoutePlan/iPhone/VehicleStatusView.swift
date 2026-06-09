import SwiftUI

struct VehicleStatusView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationStack {
            Group {
                switch appState.bluelinkService.connectionState {
                case .disconnected:
                    AccountSetupView()
                case .connecting:
                    connectingView
                case .connected, .refreshing:
                    statusView
                case .failed:
                    AccountSetupView()
                }
            }
            .navigationTitle("Vehicle")
        }
    }

    private var connectingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Connecting to BlueLink…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusView: some View {
        List {
            Section {
                vehicleHeader
            }

            if let evStatus = appState.bluelinkService.vehicleStatus?.evStatus {
                Section("Battery") {
                    BatteryGaugeView(
                        percentage: evStatus.evRange.percentage / 100.0,
                        isCharging: evStatus.charging
                    )
                    .frame(height: 100)
                    .listRowInsets(.init())

                    if let rangeMiles = appState.bluelinkService.currentRangeMiles {
                        LabeledContent("Estimated Range", value: String(format: "%.0f mi", rangeMiles))
                    }
                    LabeledContent("State of Charge", value: String(format: "%.0f%%", evStatus.evRange.percentage))
                }

                if evStatus.charging {
                    Section("Charging") {
                        if let kw = appState.bluelinkService.chargingKW {
                            LabeledContent("Charge Rate", value: String(format: "%.1f kW", kw))
                        }
                        if evStatus.chargeTime.components.seconds > 0 {
                            LabeledContent("Time Remaining", value: evStatus.chargeTime.formatted())
                        }
                    }
                }
            } else if appState.bluelinkService.vehicleStatus != nil {
                Section {
                    Text("EV status unavailable for this vehicle.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Refresh") {
                    Task { try? await appState.bluelinkService.refreshStatus() }
                }
                Button("Disconnect", role: .destructive) {
                    appState.bluelinkService.disconnect()
                }
            }
        }
    }

    private var vehicleHeader: some View {
        HStack {
            Image(systemName: "car.fill")
                .font(.largeTitle)
                .foregroundStyle(.blue)
            VStack(alignment: .leading) {
                Text(appState.bluelinkService.currentVehicle?.modelName ?? "Ioniq 5")
                    .font(.headline)
                Text(appState.vehicleVariant.rawValue)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct BatteryGaugeView: View {
    let percentage: Double  // 0–1
    let isCharging: Bool

    private var fillColor: Color {
        if isCharging { return .green }
        if percentage > 0.4 { return .green }
        if percentage > 0.2 { return .yellow }
        return .red
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.quaternary)
                RoundedRectangle(cornerRadius: 12)
                    .fill(fillColor)
                    .frame(width: geo.size.width * percentage)
                HStack {
                    Spacer()
                    if isCharging {
                        Image(systemName: "bolt.fill")
                            .foregroundStyle(.white)
                    }
                    Text(String(format: "%.0f%%", percentage * 100))
                        .bold()
                        .foregroundStyle(.white)
                    Spacer()
                }
            }
            .padding()
        }
    }
}
