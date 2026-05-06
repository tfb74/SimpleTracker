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

    // Deep-Link aus iMessage / QR-Scan: simpletracking://friend?code=ABC-123
    @State private var pendingFriendCode: String?

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
                .onOpenURL { url in handleIncomingURL(url) }
                .sheet(item: Binding(
                    get: { pendingFriendCode.map { FriendCodeInvite(code: $0) } },
                    set: { newValue in pendingFriendCode = newValue?.code }
                )) { invite in
                    AddFriendSheet(prefilledCode: invite.code)
                        .environment(cloudKit)
                }
        }
    }

    private func handleIncomingURL(_ url: URL) {
        // Akzeptiert beide Formate:
        //   simpletracking://friend?code=ABC-123       (Custom URL Scheme)
        //   https://tfb74.github.io/SimpleTracker/friend?code=ABC-123   (Universal Link)
        let scheme = url.scheme?.lowercased() ?? ""
        let isCustomScheme = scheme == "simpletracking" && url.host?.lowercased() == "friend"
        let isUniversalLink = (scheme == "https" || scheme == "http")
            && url.host?.lowercased() == "tfb74.github.io"
            && url.path.hasSuffix("/friend")

        guard isCustomScheme || isUniversalLink else { return }

        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard let code = comps?.queryItems?.first(where: { $0.name == "code" })?.value,
              !code.isEmpty else { return }
        pendingFriendCode = code
    }
}

private struct FriendCodeInvite: Identifiable {
    let code: String
    var id: String { code }
}
