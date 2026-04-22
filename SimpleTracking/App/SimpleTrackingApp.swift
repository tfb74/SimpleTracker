import SwiftUI
import UIKit

@main
struct SimpleTrackingApp: App {
    @State private var healthKit         = HealthKitService.shared
    @State private var locationService   = LocationService.shared
    @State private var watchConnectivity = WatchConnectivityService.shared
    @State private var notifications     = NotificationService.shared
    @State private var settings          = UserSettings.shared
    @State private var gameCenter        = GameCenterService.shared
    @State private var foodLog           = FoodLogStore.shared
    @State private var workoutDrafts     = WorkoutDraftStore.shared
    @State private var ads               = AdService.shared
    @State private var cloudKit          = CloudKitService.shared

    init() {
        Theme.applyAppearance()
        UserSettings.shared.ensureProfileDefaults(deviceName: UIDevice.current.name)
        AdService.shared.start()
        Task { await CloudKitService.shared.setup() }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .id("lang-\(settings.appLanguage.rawValue)")
                .environment(healthKit)
                .environment(locationService)
                .environment(watchConnectivity)
                .environment(notifications)
                .environment(settings)
                .environment(gameCenter)
                .environment(foodLog)
                .environment(workoutDrafts)
                .environment(ads)
                .environment(cloudKit)
                .preferredColorScheme(settings.colorScheme.colorScheme)
        }
    }
}
