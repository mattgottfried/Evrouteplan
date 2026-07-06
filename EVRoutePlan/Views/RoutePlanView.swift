import CoreLocation
import MapKit
import SwiftUI
import UIKit

/// ABRP-style map-first trip planner: full-screen map with charger pins and
/// the planned route, driven by a persistent bottom sheet (search, Home/Work,
/// vehicle card, saved plans, results).
struct RoutePlanView: View {
    @Environment(AppState.self) private var appState

    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var sheetShown = false
    @State private var showChargers = true
    @State private var hybridStyle = false
    @State private var mapStations: [ChargingStation] = []
    @State private var selectedStation: ChargingStation?
    @State private var visibleRegion: MKCoordinateRegion?

    var body: some View {
        Map(position: $camera) {
            UserAnnotation()

            if showChargers, appState.plannedRoute == nil {
                ForEach(mapStations) { station in
                    Annotation(station.name, coordinate: station.coordinate) {
                        chargerPin(station)
                    }
                    .annotationTitles(.hidden)
                }
            }

            if let route = appState.plannedRoute {
                MapPolyline(coordinates: route.polylineCoordinates)
                    .stroke(.blue, lineWidth: 5)
                ForEach(Array(route.stops.enumerated()), id: \.element.id) { index, stop in
                    Marker("\(index + 1). \(stop.station.name)",
                           systemImage: "bolt.fill",
                           coordinate: stop.station.coordinate)
                        .tint(.green)
                }
                Marker(route.destinationName, coordinate: route.destinationCoordinate)
                    .tint(.red)
            }
        }
        .mapStyle(hybridStyle ? .hybrid : .standard)
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .ignoresSafeArea()
        .overlay(alignment: .topLeading) { mapButtons }
        .onMapCameraChange(frequency: .onEnd) { context in
            visibleRegion = context.region
            Task { await refreshMapChargers(region: context.region) }
        }
        .onChange(of: appState.plannedRoute?.plannedAt) {
            if appState.plannedRoute != nil {
                withAnimation { camera = .automatic }  // frame the whole route
            }
        }
        .onAppear { sheetShown = true }
        .onDisappear { sheetShown = false }
        .sheet(isPresented: $sheetShown) {
            PlannerSheet(selectedStation: $selectedStation)
                .presentationDetents([.height(220), .medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled(true)
        }
        .sensoryFeedback(.success, trigger: appState.plannedRoute?.plannedAt)
    }

    // MARK: Map chrome

    private var mapButtons: some View {
        VStack(spacing: 10) {
            Button {
                showChargers.toggle()
            } label: {
                Image(systemName: showChargers ? "bolt.fill" : "bolt.slash")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(showChargers ? .green : .secondary)
                    .frame(width: 40, height: 40)
            }
            .glassCard(cornerRadius: 12)

            Button {
                hybridStyle.toggle()
            } label: {
                Image(systemName: hybridStyle ? "map.fill" : "globe.americas.fill")
                    .font(.body.weight(.semibold))
                    .frame(width: 40, height: 40)
            }
            .glassCard(cornerRadius: 12)
        }
        .padding(.leading, 12)
        .padding(.top, 4)
    }

    private func chargerPin(_ station: ChargingStation) -> some View {
        Button {
            selectedStation = station
        } label: {
            ZStack {
                Circle()
                    .fill(station.hasNACS ? Color.green : Color.teal)
                    .frame(width: 26, height: 26)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .shadow(radius: 2)
                Image(systemName: "bolt.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
    }

    private func refreshMapChargers(region: MKCoordinateRegion) async {
        guard showChargers, appState.plannedRoute == nil else { return }
        // Skip fetches when zoomed way out — pin soup and wasted quota.
        guard region.span.latitudeDelta < 3.0 else {
            mapStations = []
            return
        }
        let radius = max(region.span.latitudeDelta * 69.0 / 2.0, 5.0)
        mapStations = await appState.mapChargers(near: region.center, radiusMiles: radius)
    }
}

// MARK: - Bottom sheet

private struct PlannerSheet: View {
    @Environment(AppState.self) private var appState
    @Binding var selectedStation: ChargingStation?

    @State private var query = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var isSearching = false
    @State private var showOptions = false
    @State private var editingPlaceKind: SavedPlace.Kind?
    @State private var searchService = DestinationSearchService()

    var body: some View {
        NavigationStack {
            Group {
                if let station = selectedStation {
                    ChargerDetailView(station: station) { selectedStation = nil }
                } else {
                    switch appState.planState {
                    case .planning:
                        planningView
                    case .planned:
                        if let route = appState.plannedRoute {
                            PlanResultSheet(route: route)
                        }
                    default:
                        idleContent
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showOptions) {
            TripOptionsSheet()
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $editingPlaceKind) { kind in
            SavedPlaceEditor(kind: kind)
                .presentationDetents([.medium, .large])
        }
    }

    private var planningView: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "bolt.car.fill")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
                .symbolEffect(.pulse)
            Text("Planning your trip…")
                .font(.headline)
            Text("Routing, then sizing charging stops for your battery.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: Idle sheet (search / shortcuts / vehicle / saved)

    private var idleContent: some View {
        List {
            Section {
                searchField
                shortcutChips
                    .listRowSeparator(.hidden)
            }

            if case .failed(let message) = appState.planState {
                Section {
                    ErrorBanner(message: message)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }

            if !query.isEmpty, searchResults.isEmpty, !searchService.completions.isEmpty {
                Section("Suggestions") {
                    ForEach(searchService.completions, id: \.self) { completion in
                        Button {
                            Task {
                                if let item = await searchService.resolve(completion) {
                                    query = ""
                                    searchService.clear()
                                    await appState.planRoute(to: item)
                                }
                            }
                        } label: {
                            destinationRow(
                                icon: "mappin.circle.fill", iconColor: .red,
                                title: completion.title,
                                subtitle: completion.subtitle
                            )
                        }
                    }
                }
            }

            if isSearching {
                Section { ProgressView().frame(maxWidth: .infinity) }
            } else if !searchResults.isEmpty {
                Section("Results") {
                    ForEach(Array(searchResults.enumerated()), id: \.offset) { _, item in
                        Button {
                            searchResults = []
                            Task { await appState.planRoute(to: item) }
                        } label: {
                            destinationRow(
                                icon: "mappin.circle.fill", iconColor: .red,
                                title: item.name ?? "Unknown",
                                subtitle: item.placemark.title ?? ""
                            )
                        }
                    }
                }
            } else {
                vehicleCard

                if !appState.savedPlans.isEmpty {
                    Section("Saved Plans") {
                        ForEach(appState.savedPlans) { plan in
                            Button {
                                Task {
                                    await appState.planRoute(
                                        toName: plan.destinationName,
                                        latitude: plan.latitude, longitude: plan.longitude
                                    )
                                }
                            } label: {
                                destinationRow(
                                    icon: "heart.fill", iconColor: .pink,
                                    title: plan.destinationName,
                                    subtitle: "\(Format.miles(plan.snapshotTotalMiles)) · \(plan.snapshotStopCount) stops · \(Format.minutes(plan.snapshotTotalMinutes))"
                                )
                            }
                        }
                        .onDelete { appState.deleteSavedPlans(at: $0) }
                    }
                }

                if !appState.recentDestinations.isEmpty {
                    Section("Recent") {
                        ForEach(appState.recentDestinations) { recent in
                            Button {
                                Task {
                                    await appState.planRoute(
                                        toName: recent.name,
                                        latitude: recent.latitude, longitude: recent.longitude
                                    )
                                }
                            } label: {
                                destinationRow(
                                    icon: "clock.arrow.circlepath", iconColor: .secondary,
                                    title: recent.name, subtitle: recent.subtitle
                                )
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.immediately)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Where do you want to go?", text: $query)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { Task { await search() } }
                .onChange(of: query) {
                    searchResults = []
                    searchService.update(query: query)
                }
            if !query.isEmpty {
                Button {
                    query = ""
                    searchResults = []
                    searchService.clear()
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var shortcutChips: some View {
        HStack(spacing: 8) {
            placeChip(.home, icon: "house.fill", label: "Home")
            placeChip(.work, icon: "briefcase.fill", label: "Work")
            Spacer()
        }
        .padding(.vertical, 2)
    }

    private func placeChip(_ kind: SavedPlace.Kind, icon: String, label: String) -> some View {
        Group {
            if let place = appState.place(kind) {
                Button {
                    Task {
                        await appState.planRoute(
                            toName: place.name,
                            latitude: place.latitude, longitude: place.longitude
                        )
                    }
                } label: {
                    Label(label, systemImage: icon)
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.bordered)
                .contextMenu {
                    Button("Change \(label)") { editingPlaceKind = kind }
                    Button("Remove \(label)", role: .destructive) { appState.removePlace(kind) }
                }
            } else {
                Button {
                    editingPlaceKind = kind
                } label: {
                    Label("Set \(label)", systemImage: icon)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: Vehicle card (ABRP-style)

    private var socBinding: Binding<Double> {
        Binding(
            get: { appState.effectiveSOCFraction * 100 },
            set: { newValue in
                if appState.hasLiveSOC {
                    appState.departureSOCOverride = newValue / 100
                } else {
                    appState.manualSOCPercent = newValue
                }
            }
        )
    }

    private var vehicleCard: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(appState.vehicle?.nickname ?? "Hyundai IONIQ 5")
                            .font(.headline)
                        Text(appState.settings.trim.rawValue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        showOptions = true
                    } label: {
                        Label("Options", systemImage: "slider.horizontal.3")
                            .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                }

                HStack {
                    Image(systemName: "battery.75percent")
                        .foregroundStyle(.green)
                    Text("\(Int((appState.effectiveSOCFraction * 100).rounded()))%")
                        .font(.title3.weight(.bold))
                        .contentTransition(.numericText())
                    Spacer()
                    if appState.departureSOCOverride != nil, appState.hasLiveSOC {
                        Button {
                            appState.departureSOCOverride = nil
                        } label: {
                            Label("Use live SoC", systemImage: "arrow.triangle.2.circlepath")
                                .font(.caption.weight(.medium))
                        }
                    } else if appState.hasLiveSOC {
                        Label("Live data", systemImage: "antenna.radiowaves.left.and.right")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                Slider(value: socBinding, in: 5...100, step: 1)
                    .tint(.green)

                if let temp = appState.lastPlanTempF {
                    Text(String(format: "Range adjusted for %.0f°F weather", temp))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func destinationRow(icon: String, iconColor: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.primary)
                if !subtitle.isEmpty {
                    Text(subtitle)
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
        .contentShape(Rectangle())
    }

    private func search() async {
        isSearching = true
        defer { isSearching = false }
        searchResults = await searchService.fullSearch(query)
    }
}

extension SavedPlace.Kind: Identifiable {
    public var id: String { rawValue }
}
