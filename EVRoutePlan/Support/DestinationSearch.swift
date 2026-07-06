import CoreLocation
import Foundation
import MapKit
import Observation

/// Address/POI search done the way the Maps app does it: live autocomplete
/// via MKLocalSearchCompleter while typing, and on submit a merged
/// MKLocalSearch + CLGeocoder lookup so exact street addresses always
/// resolve (single-shot naturalLanguageQuery alone is POI-biased and misses
/// house addresses).
@MainActor
@Observable
final class DestinationSearchService: NSObject, MKLocalSearchCompleterDelegate {
    private(set) var completions: [MKLocalSearchCompletion] = []

    private let completer = MKLocalSearchCompleter()
    private var regionSeeded = false

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    /// Call on every keystroke.
    func update(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            completions = []
            completer.queryFragment = ""
            return
        }
        seedRegionIfNeeded()
        completer.queryFragment = trimmed
    }

    func clear() {
        completions = []
        completer.queryFragment = ""
    }

    private func seedRegionIfNeeded() {
        guard !regionSeeded else { return }
        regionSeeded = true
        Task {
            if let location = await LocationProvider.shared.currentLocation() {
                completer.region = MKCoordinateRegion(
                    center: location.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 6, longitudeDelta: 6)
                )
            }
        }
    }

    /// Turns a tapped autocomplete row into a routable map item.
    func resolve(_ completion: MKLocalSearchCompletion) async -> MKMapItem? {
        let request = MKLocalSearch.Request(completion: completion)
        let response = try? await MKLocalSearch(request: request).start()
        return response?.mapItems.first
    }

    /// Full search on submit: geocoder (exact addresses) first, then local
    /// search (POIs), deduplicated by coordinate.
    func fullSearch(_ query: String) async -> [MKMapItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        async let geocoded: [MKMapItem] = {
            let placemarks = (try? await CLGeocoder().geocodeAddressString(trimmed)) ?? []
            return placemarks.map { MKMapItem(placemark: MKPlacemark(placemark: $0)) }
        }()

        async let searched: [MKMapItem] = {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = trimmed
            request.resultTypes = [.address, .pointOfInterest]
            if let location = await LocationProvider.shared.currentLocation() {
                request.region = MKCoordinateRegion(
                    center: location.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 4, longitudeDelta: 4)
                )
            }
            let response = try? await MKLocalSearch(request: request).start()
            return response?.mapItems ?? []
        }()

        var seen = Set<String>()
        var merged: [MKMapItem] = []
        for item in await geocoded + searched {
            let coord = item.placemark.coordinate
            let key = String(format: "%.4f,%.4f", coord.latitude, coord.longitude)
            if seen.insert(key).inserted {
                merged.append(item)
            }
        }
        return merged
    }

    // MARK: MKLocalSearchCompleterDelegate

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results
        Task { @MainActor in
            self.completions = results
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            self.completions = []
        }
    }
}
