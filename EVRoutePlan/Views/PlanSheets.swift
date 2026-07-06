import CoreLocation
import MapKit
import SwiftUI
import UIKit

// MARK: - Planned route result (inside the bottom sheet; map shows behind)

struct PlanResultSheet: View {
    @Environment(AppState.self) private var appState
    let route: PlannedRoute
    @State private var saved = false

    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: "flag.checkered")
                        .foregroundStyle(.tint)
                    Text(route.destinationName)
                        .font(.headline)
                        .lineLimit(2)
                    Spacer()
                    Button("New Trip") { appState.clearPlan() }
                        .buttonStyle(.bordered)
                        .font(.subheadline)
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
                .listRowSeparator(.hidden)
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

            if route.needsCharging {
                Section("Charging Stops") {
                    ForEach(Array(route.stops.enumerated()), id: \.element.id) { index, stop in
                        TimelineStopRow(index: index + 1, stop: stop)
                    }
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "flag.checkered.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.red)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(route.destinationName)
                                .font(.subheadline.weight(.semibold))
                            Text("Arrive with \(Format.percent(route.arrivalSOC)) battery")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                Section {
                    Label("No charging needed — you'll arrive with \(Format.percent(route.arrivalSOC)).",
                          systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.green)
                }
            }

            Section {
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
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                if route.needsCharging {
                    Button {
                        openFullRouteInMaps()
                    } label: {
                        Label("Send Full Route to Apple Maps", systemImage: "map")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                Button {
                    appState.saveCurrentPlan()
                    saved = true
                } label: {
                    Label(saved ? "Saved" : "Save Plan",
                          systemImage: saved ? "heart.fill" : "heart")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .tint(.pink)
                .disabled(saved)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } footer: {
                if route.needsCharging {
                    Text("Navigation shows on CarPlay via Apple Maps. \"Full route\" adds every charging stop as a waypoint; or go stop-by-stop and tap the next stop while you charge.")
                }
            }
        }
        .listStyle(.insetGrouped)
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

    /// Multi-stop handoff via the Apple Maps URL scheme (daddr=A+to:B+to:C).
    /// MKMapItem.openMaps doesn't support >2 waypoints.
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

// MARK: - Timeline row (shared with result sheet)

struct TimelineStopRow: View {
    let index: Int
    let stop: ChargingStop

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "\(index).circle.fill")
                .font(.title3)
                .foregroundStyle(.green)
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
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Charger detail (tapped pin)

struct ChargerDetailView: View {
    let station: ChargingStation
    let onClose: () -> Void

    var body: some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(station.name).font(.headline)
                        HStack(spacing: 6) {
                            Text(station.network)
                            if station.hasNACS {
                                Text("NACS")
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.green.opacity(0.15))
                                    .clipShape(Capsule())
                                    .foregroundStyle(.green)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            Section {
                LabeledContent("DC fast plugs", value: "\(station.dcFastCount)")
                LabeledContent("Est. peak for Ioniq 5", value: "\(Int(station.estimatedPeakKWForIoniq5)) kW")
                LabeledContent("Connectors", value: station.connectorTypes.joined(separator: ", "))
                if let pricing = station.pricing, !pricing.isEmpty {
                    LabeledContent("Pricing", value: pricing)
                }
                LabeledContent("Address", value: station.shortAddress)
            }
            Section {
                Button {
                    let item = MKMapItem(placemark: MKPlacemark(coordinate: station.coordinate))
                    item.name = station.name
                    item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
                } label: {
                    Label("Navigate Here", systemImage: "arrow.triangle.turn.up.right.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - Trip options (ABRP "Options")

struct TripOptionsSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var appState = appState

        NavigationStack {
            Form {
                Section("Battery") {
                    sliderRow("Arrival reserve",
                              value: $appState.settings.reserveSOC,
                              range: 0.05...0.30, step: 0.05,
                              display: Format.percent(appState.settings.reserveSOC))
                    sliderRow("Charge up to",
                              value: $appState.settings.maxChargeSOC,
                              range: 0.60...1.0, step: 0.05,
                              display: Format.percent(appState.settings.maxChargeSOC))
                }
                Section("Route") {
                    Toggle("Avoid tolls", isOn: $appState.settings.avoidTolls)
                    Toggle("Avoid highways", isOn: $appState.settings.avoidHighways)
                }
                Section {
                    sliderRow("Minimum charger power",
                              value: $appState.settings.minChargerKW,
                              range: 50...350, step: 25,
                              display: "\(Int(appState.settings.minChargerKW)) kW")
                    Toggle("Prefer NACS / Superchargers", isOn: $appState.settings.preferNACS)
                    sliderRow("Charger detour limit",
                              value: $appState.settings.corridorRadiusMiles,
                              range: 5...30, step: 1,
                              display: Format.miles(appState.settings.corridorRadiusMiles))
                } header: {
                    Text("Chargers")
                } footer: {
                    Text("The 2026 Ioniq 5 peaks around 257 kW on 800 V CCS and ~126 kW on Tesla V3 Superchargers. A 125 kW minimum keeps stops quick without skipping usable sites.")
                }
            }
            .navigationTitle("Trip Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func sliderRow(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        display: String
    ) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title)
                Spacer()
                Text(display).foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
        }
    }
}

// MARK: - Home/Work editor

struct SavedPlaceEditor: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let kind: SavedPlace.Kind

    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var isSearching = false
    @State private var searchService = DestinationSearchService()

    private var title: String { kind == .home ? "Home" : "Work" }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search for an address", text: $query)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                            .onSubmit { Task { await search() } }
                            .onChange(of: query) {
                                results = []
                                searchService.update(query: query)
                            }
                    }
                    Button {
                        Task { await useCurrentLocation() }
                    } label: {
                        Label("Use Current Location", systemImage: "location.fill")
                    }
                }
                if isSearching {
                    Section { ProgressView().frame(maxWidth: .infinity) }
                }
                if results.isEmpty, !searchService.completions.isEmpty {
                    ForEach(searchService.completions, id: \.self) { completion in
                        Button {
                            Task {
                                if let item = await searchService.resolve(completion) {
                                    save(name: item.name ?? completion.title,
                                         subtitle: item.placemark.title ?? completion.subtitle,
                                         coordinate: item.placemark.coordinate)
                                }
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(completion.title).foregroundStyle(.primary)
                                if !completion.subtitle.isEmpty {
                                    Text(completion.subtitle).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                ForEach(Array(results.enumerated()), id: \.offset) { _, item in
                    Button {
                        save(name: item.name ?? title,
                             subtitle: item.placemark.title ?? "",
                             coordinate: item.placemark.coordinate)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name ?? "Unknown").foregroundStyle(.primary)
                            if let address = item.placemark.title {
                                Text(address).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Set \(title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func save(name: String, subtitle: String, coordinate: CLLocationCoordinate2D) {
        appState.setPlace(SavedPlace(
            kind: kind,
            name: name,
            subtitle: subtitle,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        ))
        dismiss()
    }

    private func useCurrentLocation() async {
        guard let location = await LocationProvider.shared.currentLocation() else { return }
        save(name: title, subtitle: "Saved from current location", coordinate: location.coordinate)
    }

    private func search() async {
        isSearching = true
        defer { isSearching = false }
        results = await searchService.fullSearch(query)
    }
}
