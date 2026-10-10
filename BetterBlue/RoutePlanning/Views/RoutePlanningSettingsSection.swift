//
//  RoutePlanningSettingsSection.swift
//  BetterBlue
//

import SwiftUI

/// Settings › Route Planning.
struct RoutePlanningSettingsSection: View {
    @Bindable private var settings = RoutePlanningSettings.shared

    var body: some View {
        Section {
            Picker("Navigate with", selection: $settings.preferredMapApp) {
                ForEach(MapApp.allCases, id: \.self) { app in
                    Text(app.rawValue).tag(app)
                }
            }
            SecureField(
                settings.buildAPIKey.isEmpty ? "NREL API key" : "NREL API key (using build key)",
                text: $settings.nrelAPIKeyOverride
            )
            .textContentType(.password)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
        } header: {
            Text("Route Planning")
        } footer: {
            if settings.nrelAPIKey.isEmpty {
                Text("Charging stops need a free key from [developer.nrel.gov](https://developer.nrel.gov/signup/).")
            } else {
                Text("Charger data from the U.S. DOE Alternative Fuel Stations database.")
            }
        }
    }
}
