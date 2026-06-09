import SwiftUI

@main
struct EVRoutePlanApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(AppState.shared)
        }
    }
}
