# EV Route Plan

Personal iPhone + CarPlay companion for a **2026 Hyundai Ioniq 5** that replaces two paid apps:

- **BetterBlue** → the **My Car** tab talks directly to Hyundai BlueLink: live battery %, range, charging state, doors, 12 V battery, odometer, plus remote lock/unlock, climate, and charge start/stop.
- **A Better Route Planner** → the **Plan** tab is a full ABRP-style map planner: full-screen map with DC fast-charger pins (tap for details/navigate), Home/Work shortcuts, battery slider with "Use live SoC", per-trip options (avoid tolls/highways, minimum charger power, prefer NACS), saved plans, and charging stops sized by a consumption model (Wh/mi × speed × WeatherKit temperature). Routes hand off — charging stops included — to Apple Maps, which navigates on **CarPlay**. Charging sessions are logged automatically to a history view, and an active charge shows as a Live Activity on the Lock Screen / Dynamic Island.

No third-party code, no server, no subscription. Credentials stay in the phone's Keychain. The BlueLink integration uses the same public owner API the MyHyundai app uses (endpoints verified against the open-source `hyundai_kia_connect_api` project).

---

## Setup (one time, ~15 minutes)

### 1. Get a free NREL API key (charger database)

Sign up at <https://developer.nlr.gov/signup/> (the API portal formerly at developer.nrel.gov) — the key arrives instantly by email. This is the US Department of Energy charging-station database (the same underlying data ABRP uses for US chargers). You'll paste the key into the app's Settings tab after install — no build configuration needed.

### 1b. Enable WeatherKit on your App ID (required before building)

Weather-adjusted range uses Apple's WeatherKit (free, 500k calls/month with your developer account), and the entitlement ships **enabled**. Before building: [developer.apple.com](https://developer.apple.com/account) → Identifiers → your app ID → tick **WeatherKit** on **both** the Capabilities and App Services tabs, then save. Skipping this makes code signing fail with a provisioning error naming WeatherKit — that's the tell.

### 2. Open and sign the project

1. Open `EVRoutePlan.xcodeproj` in **Xcode 16 or newer**.
2. Select the **EVRoutePlan** target → **Signing & Capabilities** → pick your **Team**.
3. If Xcode complains the bundle ID is taken, change `com.mattgottfried.EVRoutePlan` to anything unique.

### 3. Run it

Build to your iPhone (or simulator — everything except BlueLink works there). On first launch:

- **My Car** tab → sign in with your MyHyundai email, password, and 4-digit BlueLink PIN.
- **Settings** tab → paste the NREL key, pick your trim.
- **Plan** tab → search a destination and plan.

### 4. TestFlight

Product → **Archive** → **Distribute App** → **App Store Connect**. Create the app record in App Store Connect with the same bundle ID first. `ITSAppUsesNonExemptEncryption` is already set to `false`, so builds go straight to testing without the export-compliance question.

### 5. CarPlay (one extra step, free but requires Apple's approval)

CarPlay apps need an Apple-granted entitlement — this is an Apple policy, not a build setting, and it's why the entitlement ships **commented out** (the app builds and runs on iPhone without it, and Apple Maps still shows your planned charging stops on CarPlay via the hand-off in step 3).

1. Request the **EV charging app** CarPlay entitlement at <https://developer.apple.com/contact/carplay/> using your developer account. Describe the app honestly: shows nearby DC fast chargers, battery state, and planned charging stops for your EV.
2. When Apple approves (typically days to a few weeks), they enable the entitlement for your team. In [developer.apple.com](https://developer.apple.com/account) → Identifiers → your app ID, enable CarPlay.
3. Uncomment the two lines in `Support/EVRoutePlan.entitlements`:
   ```xml
   <key>com.apple.developer.carplay-charging</key>
   <true/>
   ```
4. Rebuild. The car now shows a native **EV Route Plan** app with three tabs: nearby **Chargers** (tap → navigate), your **Trip** plan stop list, and **Battery** status. Navigation is handed to Apple Maps on the car display.

> Until the entitlement is granted you still get CarPlay navigation with charging stops: plan the trip on the phone and tap **Navigate with Apple Maps** — the multi-stop route appears on CarPlay.

---

## How the planner works

1. Apple Maps (MKDirections) computes the driving route.
2. Using your **live battery level from BlueLink** (or the manual slider), it simulates driving: EPA range × a real-world highway factor (default 85 %), never dipping below your arrival reserve (default 10 %).
3. When a charge is needed, it searches the NREL database near the far end of your usable range for public DC fast chargers the 2026 Ioniq 5 can use — **NACS (native port, incl. Tesla Superchargers) and CCS** — and scores candidates by charging speed, plug count, and detour distance.
4. Charge time uses an E-GMP charging-curve model (fast to 55 %, tapering to 80 %) capped at what each site can deliver — e.g. ~257 kW at a 350 kW CCS dispenser, ~126 kW at a Tesla V3 Supercharger. It charges only as much as the next leg needs.

All knobs (range factor, reserve, charge ceiling, detour limit, trim) are in Settings.

## Project layout

```
EVRoutePlan.xcodeproj      — ready to open; no codegen tools needed
EVRoutePlan/               — all app sources (auto-synced folder)
  BlueLink/                — native BlueLink USA client + models
  Chargers/                — NREL station client + station model
  Planner/                 — vehicle profile, charging model, route planner
  Views/                   — SwiftUI: My Car, Plan, Settings
  CarPlay/                 — CarPlay scene (POI + trip + battery templates)
Support/                   — Info.plist, entitlements
```

## Troubleshooting

| Symptom | Fix |
|---|---|
| "Sign-in failed" | Check email/password in the MyHyundai app first; BlueLink locks accounts after repeated failures. |
| "NREL rejected the API key" | Re-paste the key in Settings (no spaces). |
| Remote commands time out | The car's modem sleeps; try **Wake Car** (antenna icon) first, wait ~30 s. |
| No CarPlay icon | The entitlement isn't granted/enabled yet — see step 5. |
| Status is stale | Pull to refresh uses the car's last report; **Wake Car** polls the vehicle directly (slower, rate-limited by Hyundai). |
