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
                monthSummary
                Section("Sessions") {
                    ForEach(appState.chargeSessions) { session in
                        ChargeSessionRow(session: session)
                    }
                    .onDelete { appState.deleteChargeSessions(at: $0) }
                }
            }
        }
        .navigationTitle("Charge History")
    }

    private var monthSummary: some View {
        let calendar = Calendar.current
        let thisMonth = appState.chargeSessions.filter {
            calendar.isDate($0.startDate, equalTo: Date(), toGranularity: .month)
        }
        let totalKWh = thisMonth.compactMap(\.estKWhAdded).reduce(0, +)
        let totalCost = thisMonth.compactMap(\.cost).reduce(0, +)

        return Section("This Month") {
            HStack(spacing: 10) {
                StatTile(icon: "number", title: "Sessions",
                         value: "\(thisMonth.count)", tint: .blue)
                StatTile(icon: "bolt.fill", title: "Energy",
                         value: String(format: "%.0f kWh", totalKWh), tint: .green)
                StatTile(icon: "dollarsign.circle.fill", title: "Est. cost",
                         value: String(format: "$%.2f", totalCost), tint: .orange)
            }
            .listRowSeparator(.hidden)
        }
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
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(String(format: "+%.1f kWh", kWh))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.green)
                        if let cost = session.cost {
                            Text(String(format: "≈ $%.2f", cost))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
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
