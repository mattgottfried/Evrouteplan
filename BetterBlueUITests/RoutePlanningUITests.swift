//
//  RoutePlanningUITests.swift
//  BetterBlueUITests
//
//  End-to-end drive of route planning with the built-in fake account:
//  sign in, open Plan Trip, pick a destination, start the trip, return to
//  the app and check the active-trip banner.
//
//  Run with:
//    xcodebuild test -scheme BetterBlue -testPlan RoutePlanningUI \
//      -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
//  Set TEST_RUNNER_SHOTS_DIR=/some/dir to also write PNG screenshots there.
//

import XCTest

@MainActor
final class RoutePlanningUITests: XCTestCase {
    private let app = XCUIApplication()
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testPlanAndStartTrip() throws {
        app.launch()
        dismissSystemAlerts()
        signInWithFakeAccountIfNeeded()
        addFakeVehicleIfNeeded()
        snapshot("01-main")

        // The Plan Trip tile lives in the vehicle sheet; expand it if needed.
        let planTrip = app.buttons["Plan Trip"]
        if !planTrip.waitForExistence(timeout: 5) {
            app.swipeUp()
        }
        XCTAssertTrue(planTrip.waitForExistence(timeout: 10), "Plan Trip tile missing")
        planTrip.tap()

        let search = app.textFields["Where to?"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        snapshot("02-planner")

        search.tap()
        search.typeText("Monterey Bay Aquarium")
        let suggestion = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] 'Aquarium'")).firstMatch
        XCTAssertTrue(suggestion.waitForExistence(timeout: 15), "no destination suggestions")
        snapshot("03-suggestions")
        suggestion.tap()

        let start = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Start Trip'")).firstMatch
        let failure = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'NREL' OR label CONTAINS[c] 'charger' OR label CONTAINS[c] 'route'")).firstMatch
        _ = start.waitForExistence(timeout: 30) || failure.exists
        app.swipeUp()
        snapshot("04-route")
        XCTAssertTrue(start.exists, "route did not plan")

        start.tap()
        // Start Trip hands off to Apple Maps; come back to BetterBlue.
        sleep(3)
        app.activate()
        let banner = app.buttons["End"]
        XCTAssertTrue(banner.waitForExistence(timeout: 10), "active trip banner missing")
        sleep(2)
        snapshot("05-active-trip")
    }

    // MARK: - Helpers

    private func signInWithFakeAccountIfNeeded() {
        let addAccount = app.buttons["Add Account"]
        guard addAccount.waitForExistence(timeout: 5) else { return }
        addAccount.tap()
        let username = app.textFields.firstMatch
        XCTAssertTrue(username.waitForExistence(timeout: 5))
        username.tap()
        username.typeText("testaccount@betterblue.com")
        let password = app.secureTextFields.firstMatch
        password.tap()
        password.typeText("betterblue")
        // The test account starts empty; its first fake vehicle is an IONIQ 5.
        app.buttons["Add Vehicle"].tap()
        app.buttons["Add"].tap()
        dismissSystemAlerts()
    }

    /// An existing fake account with no vehicles (e.g. from an earlier run):
    /// add one through Settings › account.
    private func addFakeVehicleIfNeeded() {
        guard app.staticTexts["No Vehicles"].waitForExistence(timeout: 3) else { return }
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'gear' OR label CONTAINS[c] 'settings'")).firstMatch.tap()
        let account = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] 'testaccount'")).firstMatch
        XCTAssertTrue(account.waitForExistence(timeout: 5), "account row missing in Settings")
        account.tap()
        let addVehicle = app.buttons["Add Vehicle"]
        if !addVehicle.waitForExistence(timeout: 3) { app.swipeUp() }
        addVehicle.tap()
        snapshot("01b-fake-vehicle")
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Done"].firstMatch.tap()
    }

    private func dismissSystemAlerts() {
        for label in ["Allow While Using App", "Allow", "Allow Once"] {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 2) { button.tap() }
        }
    }

    private func snapshot(_ name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] {
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }
}
