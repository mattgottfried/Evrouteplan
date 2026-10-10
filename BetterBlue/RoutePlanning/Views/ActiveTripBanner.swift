//
//  ActiveTripBanner.swift
//  BetterBlue
//
//  Compact trip status over the main map while a trip is active.
//

import SwiftUI

struct ActiveTripBanner: View {
    var onOpenPlanner: () -> Void = {}

    private var session: TripSession { .shared }

    var body: some View {
        if let trip = session.activeTrip, let route = session.plannedRoute, let leg = session.currentLeg {
            VStack(alignment: .leading, spacing: 8) {
                header(trip: trip, route: route, leg: leg)
                statusLine(trip: trip, leg: leg)
                actions(trip: trip, route: route)
            }
            .padding(12)
            .glassEffect(.regular, in: .rect(cornerRadius: 20))
            .contentShape(.rect)
            .onTapGesture(perform: onOpenPlanner)
        }
    }

    private func header(trip: TripSession.ActiveTrip, route: PlannedRoute, leg: RouteLeg) -> some View {
        HStack(spacing: 10) {
            Image(systemName: leg.endStop == nil ? "flag.checkered" : "bolt.fill")
                .font(.title3)
                .foregroundStyle(leg.endStop == nil ? .blue : .green)
            VStack(alignment: .leading, spacing: 1) {
                Text(trip.hasArrivedAtDestination ? "Arrived" : leg.endStop == nil ? "To destination" : "Next charge · stop \(trip.legIndex + 1) of \(route.stops.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(leg.end.name)
                    .font(.headline)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 1) {
                Text(RouteFormat.distance(miles: trip.remainingLegMiles))
                    .font(.headline)
                    .monospacedDigit()
                Text("arrive \(RouteFormat.percent(trip.socAtLegEnd))")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(session.isLowBatteryPredicted ? .red : .secondary)
            }
        }
    }

    @ViewBuilder
    private func statusLine(trip: TripSession.ActiveTrip, leg: RouteLeg) -> some View {
        if trip.isReplanning {
            Label("Off route — re-planning…", systemImage: "arrow.triangle.branch")
                .font(.caption).foregroundStyle(.orange)
        } else if trip.isOffRoute {
            Label("Off route", systemImage: "arrow.triangle.branch")
                .font(.caption).foregroundStyle(.orange)
        } else if session.isLowBatteryPredicted {
            Label("Arrival charge below your reserve", systemImage: "battery.25percent")
                .font(.caption).foregroundStyle(.red)
        } else if trip.isAtStop, let stop = leg.endStop {
            Label("Charge to \(RouteFormat.percent(stop.departureSOC)) (~\(RouteFormat.duration(minutes: stop.chargeMinutes)))", systemImage: "bolt.car")
                .font(.caption).foregroundStyle(.green)
        } else if !trip.hasFix {
            Label("Waiting for GPS…", systemImage: "location.slash")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func actions(trip: TripSession.ActiveTrip, route: PlannedRoute) -> some View {
        HStack {
            if trip.isAtStop {
                Button("Continue", systemImage: "arrow.right") { session.continueToNextLeg() }
                    .buttonStyle(.borderedProminent)
            } else if !trip.hasArrivedAtDestination {
                Button("Navigate", systemImage: "location.fill") { session.navigateCurrentLeg() }
                    .buttonStyle(.borderedProminent)
            }
            if trip.isOffRoute || session.isLowBatteryPredicted {
                Button("Re-plan", systemImage: "arrow.clockwise") { session.replan() }
                    .buttonStyle(.bordered)
                    .disabled(trip.isReplanning)
            }
            Spacer()
            Button(trip.hasArrivedAtDestination ? "Done" : "End", role: .destructive) {
                session.clearRoute()
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.small)
    }
}
