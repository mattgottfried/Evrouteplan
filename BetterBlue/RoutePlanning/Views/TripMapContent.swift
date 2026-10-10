//
//  TripMapContent.swift
//  BetterBlue
//
//  Route overlay shared by the trip planner preview and the main map.
//

import BetterBlueKit
import MapKit
import SwiftUI

struct TripMapContent: MapContent {
    let route: PlannedRoute
    /// Legs before this index are drawn faded (already driven).
    var currentLegIndex: Int?

    var body: some MapContent {
        ForEach(route.legs) { leg in
            MapPolyline(coordinates: leg.coordinates)
                .stroke(
                    legColor(leg),
                    style: StrokeStyle(lineWidth: leg.id == currentLegIndex ? 6 : 4, lineCap: .round, lineJoin: .round)
                )
        }
        ForEach(route.stops) { stop in
            Annotation(stop.station.stationName, coordinate: stop.station.coordinate) {
                Image(systemName: "bolt.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white, .green)
                    .shadow(radius: 2)
            }
        }
        Annotation(route.destination.name, coordinate: route.destination.coordinate) {
            Image(systemName: "flag.checkered.circle.fill")
                .font(.title)
                .foregroundStyle(.white, .blue)
                .shadow(radius: 2)
        }
    }

    private func legColor(_ leg: RouteLeg) -> Color {
        guard let current = currentLegIndex else { return .blue }
        return leg.id < current ? .gray.opacity(0.5) : .blue
    }
}

extension MKMapRect {
    /// Bounding rect of `coordinates`, padded, for fitting the camera.
    init(fitting coordinates: [CLLocationCoordinate2D]) {
        let rect = coordinates.reduce(MKMapRect.null) { rect, coord in
            rect.union(MKMapRect(origin: MKMapPoint(coord), size: MKMapSize(width: 1, height: 1)))
        }
        self = rect.insetBy(dx: -rect.size.width * 0.15, dy: -rect.size.height * 0.15)
    }
}

extension PlannedRoute {
    var mapRect: MKMapRect { MKMapRect(fitting: coordinates) }
}

extension RouteFormat {
    @MainActor static func distance(miles: Double) -> String {
        Distance.Units.miles.format(miles, to: AppSettings.shared.preferredDistanceUnit)
    }
}
