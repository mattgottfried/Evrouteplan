import Foundation

/// A pinned destination — Home, Work, or a favorite.
struct SavedPlace: Codable, Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case home
        case work
        case favorite
    }

    var id = UUID()
    var kind: Kind
    var name: String
    var subtitle: String
    var latitude: Double
    var longitude: Double
}

/// A saved trip plan. Stores the destination plus a snapshot of the numbers
/// at save time; replanning always recomputes with current conditions.
struct SavedPlan: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var destinationName: String
    var subtitle: String
    var latitude: Double
    var longitude: Double
    var savedAt: Date
    var snapshotTotalMiles: Double
    var snapshotStopCount: Int
    var snapshotTotalMinutes: Double
}

/// One observed charging session, recorded from BlueLink status transitions.
struct ChargeSession: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var startDate: Date
    var endDate: Date?
    var startSOC: Double          // percent 0–100
    var endSOC: Double?           // percent, nil while in progress
    var batteryKWh: Double        // usable pack size at record time

    var isActive: Bool { endDate == nil }

    var estKWhAdded: Double? {
        guard let endSOC else { return nil }
        return max(endSOC - startSOC, 0) / 100.0 * batteryKWh
    }

    var durationMinutes: Double? {
        guard let endDate else { return nil }
        return endDate.timeIntervalSince(startDate) / 60.0
    }
}
