//
//  TripPlannerView.swift
//  BetterBlue
//
//  Pick a destination, see the charging stops, start the trip.
//

import BetterBlueKit
import MapKit
import SwiftUI

struct TripPlannerView: View {
    let vehicle: BBVehicle
    let onDismiss: () -> Void

    @State private var search = DestinationSearch()
    @State private var useManualSOC = false
    @State private var manualSOC = 0.8
    @State private var resolveError: String?
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @FocusState private var searchFocused: Bool

    private var session: TripSession { .shared }
    private var settings: RoutePlanningSettings { .shared }
    private var liveSOC: Double? { PlanInputs.liveSOC(of: vehicle) }
    private var profile: EVProfile { EVProfileStore.profile(forVIN: vehicle.vin, model: vehicle.model) }

    var body: some View {
        NavigationStack {
            List {
                destinationSection
                if search.query.isEmpty || !searchFocused {
                    chargeSection
                    if settings.nrelAPIKey.isEmpty { apiKeySection }
                    routeSection
                }
            }
            .navigationTitle("Plan Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onDismiss)
                }
            }
        }
        .onAppear {
            manualSOC = liveSOC ?? 0.8
            useManualSOC = liveSOC == nil
            LocationProvider.shared.acquire()
            if let here = LocationProvider.shared.lastLocation?.coordinate { search.setRegion(around: here) }
        }
        .onDisappear { LocationProvider.shared.release() }
        .onChange(of: session.plannedRoute?.createdAt) { _, _ in
            if let route = session.plannedRoute {
                withAnimation { cameraPosition = .rect(route.mapRect) }
            }
        }
    }

    // MARK: - Sections

    private var destinationSection: some View {
        Section {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Where to?", text: $search.query)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                if !search.query.isEmpty {
                    Button {
                        search.query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            if searchFocused {
                ForEach(search.suggestions) { suggestion in
                    Button {
                        choose(suggestion)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.title).foregroundStyle(.primary)
                            if !suggestion.subtitle.isEmpty {
                                Text(suggestion.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            if let resolveError {
                Text(resolveError).font(.caption).foregroundStyle(.red)
            }
        } header: {
            Text("Destination")
        }
    }

    private var chargeSection: some View {
        Section {
            HStack {
                Label("Starting charge", systemImage: "battery.75percent")
                Spacer()
                Text(RouteFormat.percent(useManualSOC ? manualSOC : (liveSOC ?? manualSOC)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if liveSOC != nil {
                Toggle("Override vehicle charge", isOn: $useManualSOC)
            }
            if useManualSOC {
                Slider(value: $manualSOC, in: 0.05...1, step: 0.01)
            }
            NavigationLink {
                EVProfileSettingsView(vin: vehicle.vin, model: vehicle.model)
            } label: {
                LabeledContent("Vehicle profile", value: profile.name)
            }
        } header: {
            Text("Battery")
        } footer: {
            Text("Charges to \(RouteFormat.percent(profile.targetSOC)) at each stop and keeps a \(RouteFormat.percent(profile.arrivalReserveSOC)) reserve.")
        }
    }

    private var apiKeySection: some View {
        Section {
            SecureField("NREL API key", text: Bindable(settings).nrelAPIKeyOverride)
                .textContentType(.password)
                .autocorrectionDisabled()
            Link("Get a free key", destination: URL(string: "https://developer.nrel.gov/signup/")!)
        } header: {
            Text("Charger Database")
        } footer: {
            Text("Charging stops come from the U.S. Department of Energy station database, which needs a free API key.")
        }
    }

    @ViewBuilder
    private var routeSection: some View {
        switch session.planningState {
        case .planning:
            Section {
                HStack {
                    ProgressView()
                    Text("Finding charging stops…").foregroundStyle(.secondary)
                }
            }
        case .failed(let message):
            Section {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        case .idle:
            if let route = session.plannedRoute {
                routeResult(route)
            }
        }
    }

    @ViewBuilder
    private func routeResult(_ route: PlannedRoute) -> some View {
        Section {
            Map(position: $cameraPosition) {
                TripMapContent(route: route)
                UserAnnotation()
            }
            .frame(height: 240)
            .listRowInsets(EdgeInsets())

            VStack(alignment: .leading, spacing: 4) {
                Text(route.destination.name).font(.headline)
                Text("\(RouteFormat.distance(miles: route.totalDistanceMiles)) · \(RouteFormat.duration(minutes: route.totalMinutes))")
                    .foregroundStyle(.secondary)
                Label(
                    route.requiresCharging
                        ? "\(route.stops.count) charging stop\(route.stops.count == 1 ? "" : "s") · \(RouteFormat.duration(minutes: route.chargeMinutes)) charging"
                        : "No charging needed",
                    systemImage: route.requiresCharging ? "bolt.car" : "checkmark.circle"
                )
                .font(.subheadline)
                .foregroundStyle(route.requiresCharging ? .orange : .green)
                Text("Arrive with about \(RouteFormat.percent(route.arrivalSOC))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }

        if route.requiresCharging {
            Section("Charging Stops") {
                ForEach(Array(route.stops.enumerated()), id: \.element.id) { index, stop in
                    ChargingStopRow(index: index + 1, stop: stop)
                }
            }
        }

        Section {
            if session.activeTrip == nil {
                Button {
                    session.startTrip()
                    session.navigateCurrentLeg()
                    onDismiss()
                } label: {
                    Label(
                        route.requiresCharging ? "Start Trip — Navigate to Stop 1" : "Start Trip",
                        systemImage: "location.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } else {
                Button("End Current Trip", role: .destructive) { session.endTrip() }
            }
            Picker("Navigate with", selection: Bindable(settings).preferredMapApp) {
                ForEach(MapApp.allCases, id: \.self) { app in
                    Label(app.rawValue, systemImage: app.systemIcon).tag(app)
                }
            }
        }
    }

    // MARK: - Actions

    private func choose(_ suggestion: DestinationSearch.Suggestion) {
        searchFocused = false
        resolveError = nil
        search.query = suggestion.title
        Task {
            do {
                guard let item = try await search.resolve(suggestion) else {
                    resolveError = "Couldn't find that place."
                    return
                }
                session.plan(to: item, vehicle: vehicle, socOverride: useManualSOC ? manualSOC : nil)
            } catch {
                resolveError = error.localizedDescription
            }
        }
    }
}

struct ChargingStopRow: View {
    let index: Int
    let stop: ChargingStop

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(.green))
            VStack(alignment: .leading, spacing: 2) {
                Text(stop.station.stationName).font(.subheadline).lineLimit(1)
                Text("\(stop.station.networkName) · \(stop.station.locality)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text("Arrive \(RouteFormat.percent(stop.arrivalSOC)) → leave \(RouteFormat.percent(stop.departureSOC)) · ~\(RouteFormat.duration(minutes: stop.chargeMinutes))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
