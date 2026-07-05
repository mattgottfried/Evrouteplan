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
                    planningView
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
                        Button("New Trip") {
                            appState.clearPlan()
                            query = ""
                            searchResults = []
                        }
                    }
                }
            }
        }
        .sensoryFeedback(.success, trigger: appState.plannedRoute?.plannedAt)
    }

    private var planningView: some View {
        VStack(spacing: 16) {
            Image(systemName: "bolt.car.fill")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
                .symbolEffect(.pulse)
            Text("Planning your trip…")
                .font(.headline)
            Text("Routing, then sizing charging stops for your battery.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Destination search

    private var searchScreen: some View {
        ScrollView {
            VStack(spacing: 14) {
                searchField
                batteryContextPill

                if case .failed(let message) = appState.planState {
                    ErrorBanner(message: message)
                }

                if isSearching {
                    ProgressView().padding(.top, 24)
                } else if !searchResults.isEmpty {
                    resultsCard
                } else if !appState.recentDestinations.isEmpty {
                    recentsCard
                } else {
                    emptyState
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .scrollDismissesKeyboard(.immediately)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Where to?", text: $query)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { Task { await search() } }
            if !query.isEmpty {
                Button {
                    query = ""
                    searchResults = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var batteryContextPill: some View {
        HStack(spacing: 8) {
            Image(systemName: appState.hasLiveSOC ? "antenna.radiowaves.left.and.right" : "slider.horizontal.3")
                .foregroundStyle(appState.hasLiveSOC ? .green : .orange)
            Text(appState.hasLiveSOC
                 ? "Live battery from car: \(Format.percent(appState.effectiveSOCFraction))"
                 : "Manual battery: \(Format.percent(appState.effectiveSOCFraction)) — set in Settings")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private var resultsCard: some View {
        Card {
            VStack(spacing: 0) {
                ForEach(Array(searchResults.enumerated()), id: \.offset) { index, item in
                    Button {
                        Task { await appState.planRoute(to: item) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name ?? "Unknown")
                                    .foregroundStyle(.primary)
                                if let address = item.placemark.title {
                                    Text(address)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if index < searchResults.count - 1 { Divider() }
                }
            }
        }
    }

    private var recentsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                Text("Recent")
                    .font(.headline)
                    .padding(.bottom, 6)
                ForEach(appState.recentDestinations) { recent in
                    Button {
                        let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(
                            latitude: recent.latitude, longitude: recent.longitude
                        ))
                        let item = MKMapItem(placemark: placemark)
                        item.name = recent.name
                        Task { await appState.planRoute(to: item) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(recent.name)
                                    .foregroundStyle(.primary)
                                if !recent.subtitle.isEmpty {
                                    Text(recent.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "map")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Plan a road trip")
                .font(.headline)
            Text("Search a destination and EV Route Plan will place DC fast-charging stops sized for your Ioniq 5's battery — then hand navigation to Apple Maps and CarPlay.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 48)
        .padding(.horizontal, 24)
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
        ScrollView {
            VStack(spacing: 14) {
                routeMap
                    .frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                summaryCard

                if route.needsCharging {
                    timelineCard
                } else {
                    Card {
                        Label("No charging needed — you'll arrive with \(Format.percent(route.arrivalSOC)).",
                              systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.green)
                    }
                }

                actionButtons
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
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

    private var summaryCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "flag.checkered")
                        .foregroundStyle(.tint)
                    Text(route.destinationName)
                        .font(.headline)
                        .lineLimit(2)
                }
                HStack(spacing: 10) {
                    StatTile(icon: "clock.fill", title: "Total time",
                             value: Format.minutes(route.totalMinutes), tint: .blue)
                    StatTile(icon: "road.lanes", title: "Distance",
                             value: Format.miles(route.totalMiles), tint: .indigo)
                    if route.needsCharging {
                        StatTile(icon: "bolt.fill", title: "Charging",
                                 value: Format.minutes(route.chargeMinutes), tint: .green)
                    } else {
                        StatTile(icon: "battery.75percent", title: "Arrive at",
                                 value: Format.percent(route.arrivalSOC), tint: .green)
                    }
                }
                if route.needsCharging {
                    HStack {
                        Label("\(route.stops.count) stop\(route.stops.count == 1 ? "" : "s")",
                              systemImage: "bolt.circle.fill")
                        Spacer()
                        Label("Arrive at \(Format.percent(route.arrivalSOC))",
                              systemImage: "battery.50percent")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Timeline

    private var timelineCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                Text("Charging Stops")
                    .font(.headline)
                    .padding(.bottom, 12)
                ForEach(Array(route.stops.enumerated()), id: \.element.id) { index, stop in
                    TimelineStopRow(index: index + 1, stop: stop, isLast: false)
                }
                destinationRow
            }
        }
    }

    private var destinationRow: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Image(systemName: "flag.checkered.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.red)
            }
            .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(route.destinationName)
                    .font(.subheadline.weight(.semibold))
                Text("Arrive with \(Format.percent(route.arrivalSOC)) battery")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: Actions

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button {
                navigateToNextStop()
            } label: {
                Label(route.needsCharging ? "Navigate to First Charging Stop" : "Navigate to Destination",
                      systemImage: "arrow.triangle.turn.up.right.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)

            if route.needsCharging {
                Button {
                    openFullRouteInMaps()
                } label: {
                    Label("Send Full Route to Apple Maps", systemImage: "map")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)

                Text("Navigation shows on CarPlay via Apple Maps. \"Full route\" adds every charging stop as a waypoint; or go stop-by-stop and tap the next stop while you charge.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
    }

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
    /// (daddr=A+to:B+to:C). MKMapItem.openMaps doesn't support >2 waypoints.
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

// MARK: - Timeline row

private struct TimelineStopRow: View {
    let index: Int
    let stop: ChargingStop
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 2) {
                Image(systemName: "\(index).circle.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
                Rectangle()
                    .fill(Color(.separator))
                    .frame(width: 1)
                    .frame(minHeight: 30)
            }
            .frame(width: 28)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stop.station.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                        HStack(spacing: 6) {
                            Text(stop.station.network)
                            if stop.station.hasNACS {
                                Text("NACS")
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.green.opacity(0.15))
                                    .clipShape(Capsule())
                                    .foregroundStyle(.green)
                            }
                            Text("\(stop.station.dcFastCount) plugs")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        let item = MKMapItem(placemark: MKPlacemark(coordinate: stop.station.coordinate))
                        item.name = stop.station.name
                        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
                    } label: {
                        Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.tint)
                    }
                    .buttonStyle(.plain)
                }

                SOCBar(fromSOC: stop.arrivalSOC, toSOC: stop.departureSOC)

                HStack(spacing: 14) {
                    Label(Format.miles(stop.legMiles), systemImage: "road.lanes")
                    Label("\(Format.percent(stop.arrivalSOC)) → \(Format.percent(stop.departureSOC))",
                          systemImage: "battery.50percent")
                    Label(Format.minutes(stop.chargeMinutes), systemImage: "clock")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.bottom, 14)
        }
    }
}
