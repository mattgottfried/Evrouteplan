import CoreLocation

struct DestinationInfo: Sendable {
    let name: String
    let coordinate: CLLocationCoordinate2D
}

struct ChargingStop: Identifiable, Sendable {
    let id: UUID
    let station: ChargingStation
    let arrivalSOC: Double
    let departureSOC: Double
    let estimatedChargeTimeMinutes: Double
    let distanceFromPreviousMiles: Double

    init(
        station: ChargingStation,
        arrivalSOC: Double,
        departureSOC: Double = Ioniq5Config.defaultTargetSOC,
        estimatedChargeTimeMinutes: Double,
        distanceFromPreviousMiles: Double
    ) {
        self.id = UUID()
        self.station = station
        self.arrivalSOC = arrivalSOC
        self.departureSOC = departureSOC
        self.estimatedChargeTimeMinutes = estimatedChargeTimeMinutes
        self.distanceFromPreviousMiles = distanceFromPreviousMiles
    }
}

struct PlannedRoute: Sendable {
    let destination: DestinationInfo
    let totalDistanceMiles: Double
    let stops: [ChargingStop]
    let estimatedDriveMinutes: Double
    let estimatedChargeMinutes: Double
    let routeCoordinates: [CLLocationCoordinate2D]

    var estimatedTotalMinutes: Double { estimatedDriveMinutes + estimatedChargeMinutes }
    var requiresCharging: Bool { !stops.isEmpty }
}
