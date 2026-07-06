import SwiftUI

/// Drive & charge history — charging sessions observed via BlueLink.
struct HistoryView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        List {
            if appState.chargeSessions.isEmpty {
                ContentUnavailableView(
                    "No charging sessions yet",
                    systemImage: "bolt.batteryblock",
                    description: Text("Sessions are recorded automatically whenever the app sees the car charging via BlueLink.")
                )
            } else {
                ForEach(appState.chargeSessions) { session in
                    ChargeSessionRow(session: session)
                }
                .onDelete { appState.deleteChargeSessions(at: $0) }
            }
        }
        .navigationTitle("Charge History")
    }
}

private struct ChargeSessionRow: View {
    let session: ChargeSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(session.startDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if session.isActive {
                    Label("In progress", systemImage: "bolt.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                } else if let kWh = session.estKWhAdded {
                    Text(String(format: "+%.1f kWh", kWh))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }
            SOCBar(
                fromSOC: session.startSOC / 100,
                toSOC: (session.endSOC ?? session.startSOC) / 100
            )
            HStack(spacing: 14) {
                Label("\(Int(session.startSOC))% → \(session.endSOC.map { "\(Int($0))%" } ?? "…")",
                      systemImage: "battery.50percent")
                if let minutes = session.durationMinutes {
                    Label(Format.minutes(minutes), systemImage: "clock")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
