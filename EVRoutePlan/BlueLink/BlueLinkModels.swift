import Foundation

// MARK: - Errors

enum BlueLinkError: LocalizedError {
    case badCredentials(String)
    case apiError(code: String, message: String)
    case httpError(Int, String)
    case notLoggedIn
    case noVehicles
    case malformedResponse(String)

    var errorDescription: String? {
        switch self {
        case .badCredentials(let msg):
            return "Sign-in failed: \(msg)"
        case .apiError(let code, let message):
            return "BlueLink error \(code): \(message)"
        case .httpError(let status, let body):
            return "BlueLink HTTP \(status): \(body)"
        case .notLoggedIn:
            return "Not signed in to BlueLink."
        case .noVehicles:
            return "No vehicles are enrolled in this BlueLink account."
        case .malformedResponse(let what):
            return "Unexpected BlueLink response (\(what))."
        }
    }
}

// MARK: - Auth token

struct BlueLinkToken: Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date

    /// Treat the token as stale 60 s before actual expiry.
    var isValid: Bool { Date() < expiresAt.addingTimeInterval(-60) }
}

// MARK: - Vehicle identity (from enrollment details)

struct BlueLinkVehicle: Identifiable, Sendable, Equatable {
    let regId: String          // "regid" — used as registrationId header
    let vin: String
    let nickname: String
    let modelCode: String
    let generation: Int        // "vehicleGeneration" — Ioniq 5 is gen 3
    let isEV: Bool

    var id: String { vin }
}

// MARK: - Vehicle status snapshot

/// Parsed from the deeply nested `vehicleStatus` JSON. All fields optional —
/// the API omits anything it doesn't currently know.
struct BlueLinkStatus: Sendable {
    var socPercent: Double?           // evStatus.batteryStatus (0–100)
    var isCharging: Bool?             // evStatus.batteryCharge
    var isPluggedIn: Bool?            // evStatus.batteryPlugin != 0
    var rangeMiles: Double?           // evStatus.drvDistance[0].rangeByFuel.evModeRange
    var minutesToTargetSOC: Int?      // evStatus.remainTime2.atc.value
    var acChargeLimit: Int?           // reservChargeInfos.targetSOClist plugType 1
    var dcChargeLimit: Int?           // reservChargeInfos.targetSOClist plugType 0
    var twelveVoltPercent: Double?    // battery.batSoc
    var isLocked: Bool?               // doorLock
    var climateOn: Bool?              // airCtrlOn
    var anyDoorOpen: Bool?            // doorOpen.* / hoodOpen / trunkOpen
    var tirePressureWarning: Bool?    // tirePressureLamp.tirePressureWarningLampAll
    var odometerMiles: Double?        // from vehicleDetails.odometer
    var latitude: Double?             // vehicleLocation.coord.lat
    var longitude: Double?
    var reportedAt: Date?             // vehicleStatus.dateTime
    var fetchedAt: Date = Date()

    var socFraction: Double? { socPercent.map { $0 / 100.0 } }
}

// MARK: - Tolerant JSON helpers

/// The BlueLink USA API mixes bools, 0/1 ints, and numeric strings across
/// firmware versions, so status parsing goes through untyped JSON with
/// coercing accessors instead of Codable.
enum JSONPath {
    /// Walks `root` following dot-separated keys; numeric components index arrays.
    static func value(_ root: Any?, _ path: String) -> Any? {
        var current: Any? = root
        for component in path.split(separator: ".") {
            if let dict = current as? [String: Any] {
                current = dict[String(component)]
            } else if let array = current as? [Any], let index = Int(component) {
                current = index < array.count ? array[index] : nil
            } else {
                return nil
            }
        }
        return current
    }

    static func double(_ root: Any?, _ path: String) -> Double? {
        switch value(root, path) {
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s)
        default: return nil
        }
    }

    static func int(_ root: Any?, _ path: String) -> Int? {
        switch value(root, path) {
        case let n as NSNumber: return n.intValue
        case let s as String: return Int(s)
        default: return nil
        }
    }

    static func bool(_ root: Any?, _ path: String) -> Bool? {
        switch value(root, path) {
        case let n as NSNumber: return n.boolValue
        case let s as String: return ["true", "1", "y", "yes"].contains(s.lowercased())
        default: return nil
        }
    }

    static func string(_ root: Any?, _ path: String) -> String? {
        switch value(root, path) {
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        default: return nil
        }
    }
}
