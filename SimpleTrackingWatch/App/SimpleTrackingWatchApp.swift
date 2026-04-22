import SwiftUI

@main
struct SimpleTrackingWatchApp: App {
    @State private var workoutService = WatchWorkoutService.shared
    @State private var settings       = UserSettings.shared

    var body: some Scene {
        WindowGroup {
            WatchMainView()
                .environment(workoutService)
                .environment(settings)
                .preferredColorScheme(settings.colorScheme.colorScheme)
        }
    }
}
