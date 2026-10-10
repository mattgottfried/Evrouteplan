//
//  DestinationSearch.swift
//  BetterBlue
//
//  Live destination suggestions as the user types (MKLocalSearchCompleter),
//  resolved to an MKMapItem on selection.
//

import MapKit
import Observation

@MainActor
@Observable
final class DestinationSearch: NSObject, MKLocalSearchCompleterDelegate {
    struct Suggestion: Identifiable {
        let id: Int
        let title: String
        let subtitle: String
        fileprivate let completion: MKLocalSearchCompletion
    }

    var query = "" {
        didSet {
            if query.isEmpty {
                suggestions = []
                completer.cancel()
            } else {
                completer.queryFragment = query
            }
        }
    }

    private(set) var suggestions: [Suggestion] = []

    @ObservationIgnored private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.resultTypes = [.address, .pointOfInterest]
        completer.delegate = self
    }

    /// Bias suggestions toward where the user is.
    func setRegion(around coordinate: CLLocationCoordinate2D) {
        completer.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 200_000, longitudinalMeters: 200_000)
    }

    func resolve(_ suggestion: Suggestion) async throws -> MKMapItem? {
        let response = try await MKLocalSearch(request: MKLocalSearch.Request(completion: suggestion.completion)).start()
        return response.mapItems.first
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        // The completer calls back on the main thread.
        MainActor.assumeIsolated {
            suggestions = self.completer.results.prefix(8).enumerated().map { index, result in
                Suggestion(id: index, title: result.title, subtitle: result.subtitle, completion: result)
            }
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        MainActor.assumeIsolated { suggestions = [] }
    }
}
