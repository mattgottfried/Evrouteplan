import SwiftUI

struct AccountSetupView: View {
    @Environment(AppState.self) private var appState
    @State private var username = ""
    @State private var password = ""
    @State private var pin = ""
    @State private var isConnecting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Hyundai BlueLink Credentials") {
                    TextField("Email", text: $username)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    SecureField("Password", text: $password)
                    SecureField("PIN", text: $pin)
                        .keyboardType(.numberPad)
                }

                Section {
                    Button(action: connect) {
                        if isConnecting {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Connect")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(username.isEmpty || password.isEmpty || pin.isEmpty || isConnecting)
                }

                if case .failed(let msg) = appState.bluelinkService.connectionState {
                    Section {
                        Text(msg)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                Section {
                    Text("Your credentials are stored only on this device and sent directly to Hyundai's BlueLink servers.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("BlueLink Sign In")
        }
    }

    private func connect() {
        isConnecting = true
        Task { @MainActor in
            await appState.bluelinkService.connect(
                username: username,
                password: password,
                pin: pin
            )
            isConnecting = false
        }
    }
}
