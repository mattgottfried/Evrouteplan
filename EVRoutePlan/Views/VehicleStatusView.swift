import CoreLocation
import MapKit
import SwiftUI

struct VehicleStatusView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        switch appState.accountState {
        case .signedOut:
            NavigationStack {
                SignInView()
                    .navigationTitle("My Car")
            }
        case .signingIn:
            VStack(spacing: 16) {
                ProgressView()
                Text("Signing in to BlueLink…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .signedIn:
            MapDashboard()
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
                VStack(spacing: 12) {
                    Image(systemName: "bolt.car.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(.tint)
                    Text("Connect your Ioniq 5")
                        .font(.title3.bold())
                    Text("Sign in with your MyHyundai / BlueLink account. Credentials never leave this phone — they're stored in the Keychain and sent only to Hyundai.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
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
                    ErrorBanner(message: error)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            Section {
                Button {
                    Task {
                        await appState.signIn(username: username, password: password, pin: pin)
                    }
                } label: {
                    Text("Sign In")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(username.isEmpty || password.isEmpty)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
    }
}

// MARK: - Map dashboard (BetterBlue-style: full-screen map + glass cards)

private struct MapDashboard: View {
    @Environment(AppState.self) private var appState
    @State private var camera: MapCameraPosition = .automatic

    private var status: BlueLinkStatus? { appState.status }

    private var carCoordinate: CLLocationCoordinate2D? {
        guard let lat = status?.latitude, let lon = status?.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $camera) {
                if let coord = carCoordinate {
                    Annotation(appState.vehicle?.nickname ?? "Ioniq 5", coordinate: coord) {
                        carMarker
                    }
                }
                UserAnnotation()
            }
            .ignoresSafeArea()

            VStack(spacing: 8) {
                if let error = appState.lastError {
                    ErrorBanner(message: error)
                }
                if hasWarnings { warningsPill }
                titlePill
                rangeCard
                chargeButton
                controlsRow
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .task {
            if appState.status == nil {
                await appState.refreshStatus(force: false)
            }
            centerOnCar()
        }
        .onChange(of: status?.latitude) {
            centerOnCar()
        }
    }

    private func centerOnCar() {
        guard let coord = carCoordinate else { return }
        // Offset south so the marker floats above the card stack.
        let center = CLLocationCoordinate2D(latitude: coord.latitude - 0.0022, longitude: coord.longitude)
        withAnimation(.easeInOut(duration: 0.8)) {
            camera = .region(MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            ))
        }
    }

    private var carMarker: some View {
        ZStack {
            Circle()
                .fill(.background)
                .frame(width: 38, height: 38)
                .shadow(radius: 3)
            Image(systemName: "bolt.car.fill")
                .font(.body)
                .foregroundStyle(.tint)
        }
    }

    // MARK: Title pill

    private var titlePill: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(appState.vehicle?.nickname ?? "My Ioniq 5")
                    .font(.headline)
                if let reported = status?.reportedAt {
                    Text("Updated \(Format.relative(reported))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if appState.isRefreshingStatus {
                ProgressView()
            } else {
                Button {
                    Task { await appState.refreshStatus(force: false) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.body.weight(.medium))
                }
                Button {
                    Task { await appState.refreshStatus(force: true) }
                } label: {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.body.weight(.medium))
                }
                .help("Wake the car for a live reading")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassCard()
    }

    // MARK: Range card

    private var rangeCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: status?.isCharging == true ? "bolt.fill" : "bolt.car.fill")
                    .font(.title2)
                    .foregroundStyle(status?.isCharging == true ? .green : .primary)
                    .symbolEffect(.pulse, isActive: status?.isCharging == true)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text("EV Range")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(status?.rangeMiles.map { "\(Int($0)) mi" } ?? "—")
                        .font(.title3.weight(.semibold))
                        .contentTransition(.numericText())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Battery")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(status?.socPercent.map { "\(Int($0))%" } ?? "—")
                        .font(.title3.weight(.semibold))
                        .contentTransition(.numericText())
                }
            }
            BatteryBar(
                percent: Int(status?.socPercent ?? 0),
                isCharging: status?.isCharging == true,
                limitPercent: status?.dcChargeLimit,
                overlayText: chargeOverlayText
            )
            HStack {
                miniStat("minus.plus.batteryblock.fill",
                         status?.twelveVoltPercent.map { "12V \(Int($0))%" } ?? "12V —")
                Spacer()
                miniStat("gauge.with.needle",
                         status?.odometerMiles.map { Format.miles($0) } ?? "— mi")
                Spacer()
                miniStat(status?.isPluggedIn == true ? "powerplug.fill" : "powerplug",
                         status?.isPluggedIn == true ? "Plugged in" : "Unplugged")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
        .glassCard()
    }

    private var chargeOverlayText: String? {
        guard status?.isCharging == true else { return nil }
        guard let minutes = status?.minutesToTargetSOC, minutes > 0 else { return "Charging" }
        if let limit = status?.dcChargeLimit {
            return "\(Format.minutes(Double(minutes))) to \(limit)%"
        }
        return "\(Format.minutes(Double(minutes))) left"
    }

    private func miniStat(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
        }
    }

    // MARK: Warnings

    private var hasWarnings: Bool {
        status?.tirePressureWarning == true || status?.anyDoorOpen == true
    }

    private var warningsPill: some View {
        VStack(alignment: .leading, spacing: 6) {
            if status?.tirePressureWarning == true {
                Label("Tire pressure warning", systemImage: "exclamationmark.triangle.fill")
            }
            if status?.anyDoorOpen == true {
                Label("A door, hood, or trunk is open", systemImage: "exclamationmark.triangle.fill")
            }
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(.orange)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: Contextual charge button (only when plugged in)

    @ViewBuilder
    private var chargeButton: some View {
        if status?.isCharging == true {
            glassButton("Stop Charging", icon: "bolt.slash.fill", tint: .red) { client, vehicle in
                try await client.stopCharge(vehicle)
            }
        } else if status?.isPluggedIn == true {
            glassButton("Start Charging", icon: "bolt.fill", tint: .green) { client, vehicle in
                try await client.startCharge(vehicle)
            }
        }
    }

    // MARK: Lock + climate

    private var controlsRow: some View {
        VStack(spacing: 8) {
            if status?.isLocked == false {
                glassButton("Lock Doors", icon: "lock.open.fill", tint: .orange) { client, vehicle in
                    try await client.lock(vehicle)
                }
            } else {
                glassButton("Unlock Doors", icon: "lock.fill", tint: .green) { client, vehicle in
                    try await client.unlock(vehicle)
                }
            }
            if status?.climateOn == true {
                glassButton("Stop Climate", icon: "fan.fill", tint: .teal) { client, vehicle in
                    try await client.stopClimate(vehicle)
                }
            } else {
                glassButton("Start Climate (70°)", icon: "fan", tint: .teal) { client, vehicle in
                    try await client.startClimate(vehicle, tempF: 70, defrost: false)
                }
            }
        }
    }

    private func glassButton(
        _ label: String,
        icon: String,
        tint: Color,
        _ operation: @escaping (BlueLinkClient, BlueLinkVehicle) async throws -> Void
    ) -> some View {
        Button {
            Task { await appState.runCommand("\(label)…", operation) }
        } label: {
            HStack {
                if appState.busyCommand == "\(label)…" {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: icon)
                        .foregroundStyle(tint)
                }
                Text(appState.busyCommand == "\(label)…" ? "Sending to car…" : label)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassCard()
        .disabled(appState.busyCommand != nil)
        .opacity(appState.busyCommand != nil && appState.busyCommand != "\(label)…" ? 0.5 : 1)
    }
}
