# EV Route Planning fork of BetterBlue

This repository is a fork of [schmidtwmark/BetterBlue](https://github.com/schmidtwmark/BetterBlue). It adds EV route planning with charging stops, live GPS trip tracking, and CarPlay. Upstream code is kept as unchanged as possible, so pulling Mark's updates stays easy.

## What's added

| Area | Where |
|---|---|
| Charge-stop planner, NREL client, geometry, EV profiles (pure, unit-tested) | `BetterBlue/RoutePlanning/Core/` |
| Trip state, GPS tracking, maps hand-off | `BetterBlue/RoutePlanning/TripSession.swift`, `LocationProvider.swift` |
| Planner sheet, trip banner, profile and settings UI | `BetterBlue/RoutePlanning/Views/` |
| CarPlay (Route + Nearby tabs) | `BetterBlue/CarPlay/` |
| Unit tests (Swift Testing) | `BetterBlueTests/` (runs with the default `BetterBlue.xctestplan`) |
| End-to-end UI test (fake account) | `BetterBlueUITests/` (`RoutePlanningUI.xctestplan`) |

Hook-ins to upstream files:
- `VehicleSheetPresentation.swift`: a `tripPlanner` case.
- `MainView.swift`: renders that sheet and the active-trip banner.
- `PersistentVehicleSheet.swift`: a **Plan Trip** tile for EVs.
- `SimpleMapView.swift`: draws the route during a trip.
- `SettingsView.swift`: a **Route Planning** section.
- `Info.plist` and the project file:
  - location strings and background mode
  - the CarPlay scene
  - the test targets

## Setup

1. Initialize the BetterBlueKit submodule:
   ```bash
   git submodule update --init --recursive
   ```
2. Copy `Config/Local.xcconfig.template` to `Config/Local.xcconfig`, then set:
   - `DEVELOPMENT_TEAM`
   - `BB_BUNDLE_ID_PREFIX`
   - `BB_APP_GROUP`
   - `BB_ICLOUD_CONTAINER`
   - `NREL_API_KEY`: free at <https://developer.nrel.gov/signup/>. You can also paste a key at runtime in **Settings › Route Planning**.
3. Build and test:
   ```bash
   xcodebuild test -scheme BetterBlue -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
   # end-to-end (needs network for MapKit search/directions):
   xcodebuild test -scheme BetterBlue -testPlan RoutePlanningUI -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
   ```

To try it without a car, sign in with `testaccount@betterblue.com` / `betterblue`, then use **Add Vehicle**. The first fake vehicle is an IONIQ 5 EV.

## How planning works

1. MapKit returns a driving route.
2. One NREL `nearby-route` request finds every public CCS DC fast charger within 5 mi of it.
3. `ChargeStopPlanner` walks the route and stops in the back half of each reachable window, preferring the fastest charger. It keeps the profile's arrival reserve (10% by default) and charges to the target (80%). The last stop only charges what is needed to finish.
4. Full range comes from the car's live BlueLink estimate (range ÷ SOC) when plausible, otherwise from the vehicle profile's rated range.

During a trip:
- GPS fixes are matched to the current leg.
- Predicted SOC is re-anchored to BlueLink every 10 minutes.
- Three consecutive fixes more than ~400 m off the route trigger a re-plan (at most once every 2 minutes).
- Arriving at a charger pauses the trip; driving away starts the next leg.
- Each leg opens in Apple Maps, Google Maps or Waze. Pick one in Settings › Route Planning.

## CarPlay entitlement

CarPlay apps need an entitlement that Apple grants per team. This app fits the EV charging category, `com.apple.developer.carplay-charging`; you request it at <https://developer.apple.com/contact/carplay/>.

Until Apple grants it, the entitlement is applied to **simulator builds only**. The `CODE_SIGN_ENTITLEMENTS[sdk=iphonesimulator*]` setting points at `BetterBlue/BetterBlue-CarPlay.entitlements`, so device builds still sign.

Once it's granted, point the device `CODE_SIGN_ENTITLEMENTS` at `BetterBlue-CarPlay.entitlements` as well.

## Syncing upstream

```bash
git fetch upstream
git merge upstream/main
```

Conflicts, if any, should be limited to the hook-in lines listed above.
