import CoreLocation
import MapKit
import Testing

@testable import EVRoutePlan

// MARK: - Ioniq5Config tests

@Suite("Ioniq5Config")
struct Ioniq5ConfigTests {
    @Test("Long range AWD has correct specs")
    func longRangeAWDSpecs() {
        #expect(Ioniq5Config.Variant.longRangeAWD.batteryKWh == 84.0)
        #expect(Ioniq5Config.Variant.longRangeAWD.epaRangeMiles == 310.0)
    }

    @Test("Standard RWD has correct specs")
    func standardRWDSpecs() {
        #expect(Ioniq5Config.Variant.standardRWD.batteryKWh == 77.4)
        #expect(Ioniq5Config.Variant.standardRWD.epaRangeMiles == 266.0)
    }
}

// MARK: - Charge time calculation

@Suite("Charge time estimation")
struct ChargeTimeTests {
    // (toSOC - fromSOC) * batteryKWh / chargerKW * 60
    // (0.80 - 0.15) * 84.0 / 150.0 * 60 = 21.84 min
    @Test("Charge from 15% to 80% at 150 kW on 84 kWh battery")
    func chargeTime15to80at150kW() {
        let time = estimateChargeMinutes(fromSOC: 0.15, toSOC: 0.80, chargerKW: 150, batteryKWh: 84.0)
        #expect(abs(time - 21.84) < 0.01)
    }

    // (0.80 - 0.20) * 84.0 / 350.0 * 60 = 8.64 min
    @Test("Charge from 20% to 80% at 350 kW on 84 kWh battery")
    func chargeTime20to80at350kW() {
        let time = estimateChargeMinutes(fromSOC: 0.20, toSOC: 0.80, chargerKW: 350, batteryKWh: 84.0)
        #expect(abs(time - 8.64) < 0.01)
    }

    @Test("Zero charge time when toSOC <= fromSOC")
    func noChargeNeeded() {
        let time = estimateChargeMinutes(fromSOC: 0.80, toSOC: 0.80, chargerKW: 150, batteryKWh: 84.0)
        #expect(time == 0)
    }
}

// MARK: - ChargingStation model

@Suite("ChargingStation model")
struct ChargingStationTests {
    @Test("Electrify America estimated max kW is 350")
    func electrifyAmericaKW() {
        let station = makeStation(network: "Electrify America")
        #expect(station.estimatedMaxKW == 350.0)
    }

    @Test("Tesla estimated max kW is 250")
    func teslaKW() {
        let station = makeStation(network: "Tesla")
        #expect(station.estimatedMaxKW == 250.0)
    }

    @Test("Unknown network defaults to minimum DCFC kW")
    func unknownNetworkKW() {
        let station = makeStation(network: "SomeOtherNetwork")
        #expect(station.estimatedMaxKW == Ioniq5Config.minimumDCFastKW)
    }

    @Test("hasDCFast is true when evDcFastNum > 0")
    func hasDCFastTrue() {
        let station = makeStation(dcFastNum: 4)
        #expect(station.hasDCFast)
    }

    @Test("hasDCFast is false when evDcFastNum is nil")
    func hasDCFastFalse() {
        let station = makeStation(dcFastNum: nil)
        #expect(!station.hasDCFast)
    }
}

// MARK: - PlannedRoute model

@Suite("PlannedRoute model")
struct PlannedRouteTests {
    @Test("Route with no stops does not require charging")
    func directRoute() {
        let route = PlannedRoute(
            destination: DestinationInfo(name: "LA", coordinate: .init(latitude: 34, longitude: -118)),
            totalDistanceMiles: 100,
            stops: [],
            estimatedDriveMinutes: 90,
            estimatedChargeMinutes: 0,
            routeCoordinates: []
        )
        #expect(!route.requiresCharging)
        #expect(route.estimatedTotalMinutes == 90)
    }

    @Test("Total minutes includes charge time")
    func totalMinutesWithCharge() {
        let stop = ChargingStop(
            station: makeStation(),
            arrivalSOC: 0.15,
            estimatedChargeTimeMinutes: 20,
            distanceFromPreviousMiles: 200
        )
        let route = PlannedRoute(
            destination: DestinationInfo(name: "LA", coordinate: .init(latitude: 34, longitude: -118)),
            totalDistanceMiles: 400,
            stops: [stop],
            estimatedDriveMinutes: 360,
            estimatedChargeMinutes: 20,
            routeCoordinates: []
        )
        #expect(route.estimatedTotalMinutes == 380)
        #expect(route.requiresCharging)
    }
}

// MARK: - Helpers

private func estimateChargeMinutes(
    fromSOC: Double,
    toSOC: Double,
    chargerKW: Double,
    batteryKWh: Double
) -> Double {
    guard toSOC > fromSOC, chargerKW > 0 else { return 0 }
    return (toSOC - fromSOC) * batteryKWh / chargerKW * 60.0
}

private func makeStation(
    id: Int = 1,
    network: String? = "Electrify America",
    dcFastNum: Int? = 4
) -> ChargingStation {
    ChargingStation(
        id: id,
        stationName: "Test Charger",
        streetAddress: "123 Main St",
        city: "Testville",
        state: "CA",
        zip: "90210",
        latitude: 37.3,
        longitude: -122.0,
        evNetwork: network,
        evConnectorTypes: ["CCS"],
        evDcFastNum: dcFastNum,
        evLevel2EvseNum: nil,
        accessCode: "public",
        statusCode: "E"
    )
}
