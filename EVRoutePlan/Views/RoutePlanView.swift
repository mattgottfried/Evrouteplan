import MapKit
import SwiftUI
import UIKit

struct RoutePlanView: View {
    @Environment(AppState.self) private var appState
    @State private var query = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var isSearching = false

    var body: some View {
        NavigationStack {
            Group {
                switch appState.planState {
                case .planning:
                    ProgressView("Planning route and charging stops…")
                case .planned:
                    if let route = appState.plannedRoute {
                        PlannedRouteView(route: route)
                    }
                default:
                    searchScreen
                }
            }
            .navigationTitle("Trip Planner")
            .toolbar {
                if appState.plannedRoute != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("New Trip") { appState.clearPlan() }
                    }
                }
            }
        }
    }

    // MARK: - Destination search

    private var searchScreen: some View {
        List {
            Section {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Where to?", text: $query)
                        .autocorrectionDisabled()
                        .onSubmit { Task { await search() } }
                        .submitLabel(.search)
                }
            } footer: {
                Text(startingSOCFooter)
            }

            if case .failed(let message) = appState.planState {
                Section {
                    Text(message).foregroundStyle(.red).font(.footnote)
                }
            }

            if isSearching {
                ProgressView()
            } else {
                ForEach(searchResults, id: \.self) { item in
                    Button {
                        Task { await appState.planRoute(to: item) }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name ?? "Unknown")
                                .foregroundStyle(.primary)
                            if let address = item.placemark.title {
                                Text(address)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var startingSOCFooter: String {
        let soc = Format.percent(appState.effectiveSOCFraction)
        return appState.hasLiveSOC
            ? "Planning with live battery level from the car: \(soc)."
            : "Planning with manual battery level \(soc) — set it in Settings, or sign in to BlueLink for live data."
    }

    private func search() async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching = true
        defer { isSearching = false }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if let location = await LocationProvider.shared.currentLocation() {
            request.region = MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 4, longitudeDelta: 4)
            )
        }
        let response = try? await MKLocalSearch(request: request).start()
        searchResults = response?.mapItems ?? []
    }
}

// MARK: - Planned route display

private struct PlannedRouteView: View {
    let route: PlannedRoute

    var body: some View {
        List {
            Section {
                routeMap
                    .frame(height: 260)
                    .listRowInsets(EdgeInsets())
            }

            Section {
                LabeledContent("Distance", value: Format.miles(route.totalMiles))
                LabeledContent("Driving", value: Format.minutes(route.driveMinutes))
                if route.needsCharging {
                    LabeledContent("Charging", value: Format.minutes(route.chargeMinutes))
                }
                LabeledContent("Total", value: Format.minutes(route.totalMinutes))
                LabeledContent("Arrival battery", value: Format.percent(route.arrivalSOC))
            } header: {
                Text(route.destinationName)
            }

            if route.needsCharging {
                Section("Charging Stops") {
                    ForEach(Array(route.stops.enumerated()), id: \.element.id) { index, stop in
                        ChargingStopRow(index: index + 1, stop: stop)
                    }
                }
            } else {
                Section {
                    Label("No charging needed — you can make it on the current battery.",
                          systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            Section {
                Button {
                    navigateToNextStop()
                } label: {
                    Label(route.needsCharging ? "Navigate to First Charging Stop" : "Navigate to Destination",
                          systemImage: "arrow.triangle.turn.up.right.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                if route.needsCharging {
                    Button {
                        openFullRouteInMaps()
                    } label: {
                        Label("Send Full Route to Apple Maps", systemImage: "map")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            } footer: {
                if route.needsCharging {
                    Text("Navigation shows on CarPlay via Apple Maps. \"Full route\" adds every charging stop as a waypoint in one go; or navigate stop-by-stop and tap the next stop while you charge.")
                }
            }
        }
    }

    private var routeMap: some View {
        Map {
            MapPolyline(coordinates: route.polylineCoordinates)
                .stroke(.blue, lineWidth: 4)
            ForEach(Array(route.stops.enumerated()), id: \.element.id) { index, stop in
                Marker("\(index + 1). \(stop.station.name)",
                       systemImage: "bolt.fill",
                       coordinate: stop.station.coordinate)
                    .tint(.green)
            }
            Marker(route.destinationName, coordinate: route.destinationCoordinate)
                .tint(.red)
        }
        .allowsHitTesting(false)
    }

    /// Directions from the current location to the first waypoint — the
    /// most reliable Apple Maps handoff (single destination).
    private func navigateToNextStop() {
        let item: MKMapItem
        if let first = route.stops.first {
            item = MKMapItem(placemark: MKPlacemark(coordinate: first.station.coordinate))
            item.name = first.station.name
        } else {
            item = MKMapItem(placemark: MKPlacemark(coordinate: route.destinationCoordinate))
            item.name = route.destinationName
        }
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }

    /// Multi-stop handoff via the Apple Maps URL scheme
    /// (daddr=A+to:B+to:C), which builds one route with every charging stop
    /// as a waypoint. MKMapItem.openMaps doesn't support >2 waypoints.
    private func openFullRouteInMaps() {
        var waypoints = route.stops.map { stop in
            String(format: "%.5f,%.5f", stop.station.latitude, stop.station.longitude)
        }
        waypoints.append(String(format: "%.5f,%.5f",
                                route.destinationCoordinate.latitude,
                                route.destinationCoordinate.longitude))
        let daddr = waypoints.joined(separator: "+to:")
        var components = URLComponents(string: "https://maps.apple.com/")!
        // No saddr → Apple Maps starts from the current location.
        components.queryItems = [
            URLQueryItem(name: "daddr", value: daddr),
            URLQueryItem(name: "dirflg", value: "d"),
        ]
        if let url = components.url {
            UIApplication.shared.open(url)
        }
    }
}

private struct ChargingStopRow: View {
    let index: Int
    let stop: ChargingStop

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "\(index).circle.fill")
                    .foregroundStyle(.green)
                VStack(alignment: .leading) {
                    Text(stop.station.name).font(.headline)
                    Text("\(stop.station.network) · \(stop.station.dcFastCount) DC plugs\(stop.station.hasNACS ? " · NACS" : "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(stop.station.shortAddress)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Label(Format.miles(stop.legMiles), systemImage: "road.lanes")
                Label("\(Format.percent(stop.arrivalSOC)) → \(Format.percent(stop.departureSOC))",
                      systemImage: "battery.50percent")
                Label(Format.minutes(stop.chargeMinutes), systemImage: "clock")
            }
            .font(.caption)

            Button {
                let item = MKMapItem(placemark: MKPlacemark(coordinate: stop.station.coordinate))
                item.name = stop.station.name
                item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
            } label: {
                Label("Navigate to this stop", systemImage: "arrow.triangle.turn.up.right.circle")
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}
