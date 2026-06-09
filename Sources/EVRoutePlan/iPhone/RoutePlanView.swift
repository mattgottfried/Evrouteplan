import MapKit
import SwiftUI

struct RoutePlanView: View {
    @Environment(AppState.self) private var appState
    @State private var searchText = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var isSearching = false
    @State private var selectedItem: MKMapItem?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                routeMapView
                    .frame(maxHeight: .infinity)

                Divider()

                planningPanel
                    .background(.regularMaterial)
            }
            .navigationTitle("Route Planner")
            .searchable(text: $searchText, prompt: "Where to?")
            .onSubmit(of: .search) { Task { await search() } }
            .onChange(of: searchText) { _, new in
                if new.isEmpty { searchResults = [] }
            }
            .searchSuggestions {
                ForEach(searchResults, id: \.self) { item in
                    Label(item.name ?? "Unknown", systemImage: "mappin")
                        .searchCompletion(item.name ?? "")
                        .onTapGesture { selectDestination(item) }
                }
            }
        }
    }

    // MARK: - Subviews

    private var routeMapView: some View {
        Map {
            if let route = appState.plannedRoute {
                MapPolyline(coordinates: route.routeCoordinates)
                    .stroke(.blue, lineWidth: 4)

                ForEach(route.stops) { stop in
                    Annotation(stop.station.stationName, coordinate: stop.station.coordinate) {
                        Image(systemName: "bolt.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white, .green)
                    }
                }

                Annotation(route.destination.name, coordinate: route.destination.coordinate) {
                    Image(systemName: "flag.checkered.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white, .blue)
                }
            }
        }
    }

    private var planningPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            socRow

            if case .planning = appState.routePlanningState {
                ProgressView("Planning route…")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            } else if case .failed(let msg) = appState.routePlanningState {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if let route = appState.plannedRoute {
                routeSummary(route)
            }
        }
        .padding()
    }

    private var socRow: some View {
        HStack {
            Image(systemName: "battery.75percent")
            Text("Current charge: \(Int(appState.effectiveSOCFraction * 100))%")
                .font(.subheadline)

            if appState.bluelinkService.connectionState == .disconnected {
                Spacer()
                Text("(manual)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func routeSummary(_ route: PlannedRoute) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(route.destination.name, systemImage: "mappin.circle.fill")
                    .font(.headline)
                Spacer()
                Text(String(format: "%.0f mi", route.totalDistanceMiles))
                    .foregroundStyle(.secondary)
            }

            Label(
                route.requiresCharging
                    ? "\(route.stops.count) charging stop\(route.stops.count == 1 ? "" : "s") · \(formatMinutes(route.estimatedTotalMinutes))"
                    : "Direct · \(formatMinutes(route.estimatedDriveMinutes))",
                systemImage: route.requiresCharging ? "bolt.car" : "checkmark.circle"
            )
            .font(.subheadline)
            .foregroundStyle(route.requiresCharging ? .orange : .green)

            if route.requiresCharging {
                ForEach(route.stops) { stop in
                    ChargingStopRow(stop: stop)
                }
            }
        }
    }

    // MARK: - Actions

    private func search() async {
        guard !searchText.isEmpty else { return }
        isSearching = true
        defer { isSearching = false }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchText
        let results = try? await MKLocalSearch(request: request).start()
        searchResults = results?.mapItems ?? []
    }

    private func selectDestination(_ item: MKMapItem) {
        selectedItem = item
        searchResults = []
        searchText = item.name ?? ""
        Task { await appState.planRoute(to: item) }
    }

    private func formatMinutes(_ mins: Double) -> String {
        let h = Int(mins) / 60
        let m = Int(mins) % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

struct ChargingStopRow: View {
    let stop: ChargingStop

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.fill")
                .foregroundStyle(.green)
            VStack(alignment: .leading) {
                Text(stop.station.stationName)
                    .font(.caption)
                    .lineLimit(1)
                Text("\(stop.station.city), \(stop.station.state) · Arrive \(Int(stop.arrivalSOC * 100))% · ~\(Int(stop.estimatedChargeTimeMinutes)) min charge")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
