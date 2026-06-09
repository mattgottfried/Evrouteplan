import CarPlay
import MapKit

@MainActor
func buildNearbyChargersTemplate(stations: [ChargingStation]) -> CPPointOfInterestTemplate {
    let pois = stations.map { station -> CPPointOfInterest in
        let placemark = MKPlacemark(
            coordinate: station.coordinate,
            addressDictionary: nil
        )
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = station.stationName

        return CPPointOfInterest(
            location: mapItem,
            title: station.stationName,
            subtitle: "\(station.evNetwork ?? "Unknown Network") · \(station.evDcFastNum ?? 0) DCFC",
            summary: station.streetAddress,
            detailTitle: station.stationName,
            detailSubtitle: "\(station.city), \(station.state) \(station.zip)",
            detailSummary: "Est. max: \(Int(station.estimatedMaxKW)) kW",
            pinImage: UIImage(systemName: "bolt.circle.fill")
        )
    }

    return CPPointOfInterestTemplate(
        title: "Nearby Chargers",
        pointsOfInterest: pois,
        selectedIndex: NSNotFound
    )
}
