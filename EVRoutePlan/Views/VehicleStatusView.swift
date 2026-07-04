import SwiftUI

struct VehicleStatusView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationStack {
            Group {
                switch appState.accountState {
                case .signedOut:
                    SignInView()
                case .signingIn:
                    ProgressView("Signing in to BlueLink…")
                case .signedIn:
                    StatusDashboard()
                }
            }
            .navigationTitle(appState.vehicle?.nickname ?? "My Car")
        }
    }
}

// MARK: - Sign-in

private struct SignInView: View {
    @Environment(AppState.self) private var appState
    @State private var username = ""
    @State private var password = ""
    @State private var pin = ""

    var body: some View {
        Form {
            Section {
                Text("Sign in with your MyHyundai / BlueLink account — the same one BetterBlue uses. Credentials are stored only in this phone's Keychain.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("BlueLink Account") {
                TextField("Email", text: $username)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
                    .textContentType(.password)
                SecureField("BlueLink PIN (4 digits)", text: $pin)
                    .keyboardType(.numberPad)
            }
            if let error = appState.lastError {
                Section {
                    Text(error).foregroundStyle(.red).font(.footnote)
                }
            }
            Section {
                Button("Sign In") {
                    Task {
                        await appState.signIn(username: username, password: password, pin: pin)
                    }
                }
                .disabled(username.isEmpty || password.isEmpty)
            }
        }
    }
}

// MARK: - Dashboard

private struct StatusDashboard: View {
    @Environment(AppState.self) private var appState

    private var status: BlueLinkStatus? { appState.status }

    var body: some View {
        List {
            batterySection
            carSection
            commandSection
            if let error = appState.lastError {
                Section {
                    Text(error).foregroundStyle(.red).font(.footnote)
                }
            }
        }
        .refreshable { await appState.refreshStatus(force: false) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await appState.refreshStatus(force: true) }
                } label: {
                    if appState.isRefreshingStatus {
                        ProgressView()
                    } else {
                        Label("Wake Car", systemImage: "antenna.radiowaves.left.and.right")
                    }
                }
                .disabled(appState.isRefreshingStatus)
            }
        }
        .task {
            if appState.status == nil {
                await appState.refreshStatus(force: false)
            }
        }
    }

    private var batterySection: some View {
        Section("Battery") {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: batterySymbol)
                    .font(.system(size: 40))
                    .foregroundStyle(batteryColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text(status?.socPercent.map { "\(Int($0))%" } ?? "—")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                    if let range = status?.rangeMiles {
                        Text("\(Int(range)) mi range")
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 4)

            if status?.isCharging == true {
                LabeledContent("Charging", value: chargingDetail)
            } else if status?.isPluggedIn == true {
                LabeledContent("Plugged in", value: "not charging")
            }
            if let dc = status?.dcChargeLimit, let ac = status?.acChargeLimit {
                LabeledContent("Charge limits", value: "DC \(dc)% · AC \(ac)%")
            }
            if let reported = status?.reportedAt {
                LabeledContent("Car reported", value: Format.relative(reported))
            }
        }
    }

    private var chargingDetail: String {
        if let minutes = status?.minutesToTargetSOC, minutes > 0 {
            return "\(Format.minutes(Double(minutes))) to limit"
        }
        return "in progress"
    }

    private var batterySymbol: String {
        if status?.isCharging == true { return "bolt.batteryblock.fill" }
        guard let soc = status?.socPercent else { return "battery.50percent" }
        if soc <= 20 { return "battery.25percent" }
        if soc <= 60 { return "battery.50percent" }
        return "battery.100percent"
    }

    private var batteryColor: Color {
        if status?.isCharging == true { return .green }
        guard let soc = status?.socPercent else { return .secondary }
        if soc <= 20 { return .red }
        if soc <= 40 { return .orange }
        return .green
    }

    private var carSection: some View {
        Section("Vehicle") {
            LabeledContent("Doors", value: doorText)
            if let climate = status?.climateOn {
                LabeledContent("Climate", value: climate ? "On" : "Off")
            }
            if let twelveV = status?.twelveVoltPercent {
                LabeledContent("12 V battery", value: "\(Int(twelveV))%")
            }
            if let odometer = status?.odometerMiles {
                LabeledContent("Odometer", value: Format.miles(odometer))
            }
            if status?.tirePressureWarning == true {
                Label("Tire pressure warning", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            if status?.anyDoorOpen == true {
                Label("A door, hood, or trunk is open", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
    }

    private var doorText: String {
        guard let locked = status?.isLocked else { return "—" }
        return locked ? "Locked" : "Unlocked"
    }

    private var commandSection: some View {
        Section("Remote") {
            if let busy = appState.busyCommand {
                HStack {
                    ProgressView()
                    Text(busy).padding(.leading, 8).foregroundStyle(.secondary)
                }
            }
            HStack {
                commandButton("Lock", "lock.fill") { client, vehicle in
                    try await client.lock(vehicle)
                }
                commandButton("Unlock", "lock.open.fill") { client, vehicle in
                    try await client.unlock(vehicle)
                }
            }
            HStack {
                commandButton("Climate On", "fan.fill") { client, vehicle in
                    try await client.startClimate(vehicle, tempF: 70, defrost: false)
                }
                commandButton("Climate Off", "fan.slash.fill") { client, vehicle in
                    try await client.stopClimate(vehicle)
                }
            }
            HStack {
                commandButton("Start Charge", "bolt.fill") { client, vehicle in
                    try await client.startCharge(vehicle)
                }
                commandButton("Stop Charge", "bolt.slash.fill") { client, vehicle in
                    try await client.stopCharge(vehicle)
                }
            }
        }
    }

    private func commandButton(
        _ label: String,
        _ symbol: String,
        _ operation: @escaping (BlueLinkClient, BlueLinkVehicle) async throws -> Void
    ) -> some View {
        Button {
            Task { await appState.runCommand("\(label)…", operation) }
        } label: {
            Label(label, systemImage: symbol)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(appState.busyCommand != nil)
    }
}
