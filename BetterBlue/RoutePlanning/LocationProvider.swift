//
//  LocationProvider.swift
//  BetterBlue
//
//  Thin wrapper over CoreLocation's async live updates. A background
//  activity session keeps fixes flowing while the phone is locked or the
//  app is behind CarPlay, as long as a trip is active.
//

import CoreLocation
import Foundation
import Observation

@MainActor
@Observable
final class LocationProvider {
    static let shared = LocationProvider()

    private(set) var lastLocation: CLLocation?
    private(set) var authorizationDenied = false

    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var serviceSession: CLServiceSession?
    @ObservationIgnored private var backgroundSession: CLBackgroundActivitySession?
    @ObservationIgnored private var subscribers = 0

    private init() {}

    /// Start (or keep) receiving fixes. Balanced with `release()`.
    /// - Parameter background: keep updating while the app is backgrounded.
    func acquire(background: Bool = false) {
        subscribers += 1
        if serviceSession == nil {
            serviceSession = CLServiceSession(authorization: .whenInUse)
        }
        if background, backgroundSession == nil {
            backgroundSession = CLBackgroundActivitySession()
        }
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates(.automotiveNavigation) {
                    guard let self else { return }
                    self.authorizationDenied = update.authorizationDenied || update.authorizationDeniedGlobally
                    if let location = update.location, location.horizontalAccuracy >= 0,
                       location.horizontalAccuracy < 100 {
                        self.lastLocation = location
                    }
                }
            } catch {
                // The sequence only throws on cancellation.
            }
        }
    }

    func release() {
        subscribers = max(0, subscribers - 1)
        guard subscribers == 0 else { return }
        updatesTask?.cancel()
        updatesTask = nil
        backgroundSession?.invalidate()
        backgroundSession = nil
        serviceSession?.invalidate()
        serviceSession = nil
    }

    /// Drop background updates but keep foreground ones if others still listen.
    func endBackground() {
        backgroundSession?.invalidate()
        backgroundSession = nil
    }
}
