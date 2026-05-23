import SwiftUI
import UIKit

/// AppDelegate damit wir Remote-Notifications empfangen können (CloudKit
/// Subscriptions liefern über APNs). SwiftUI alone gibt uns dafür keinen
/// Hook, deshalb der Bridge-Pattern via @UIApplicationDelegateAdaptor.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // CloudKit kümmert sich selbst um Token-Routing — wir müssen nichts schicken.
        print("[Push] registered for remote notifications")
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("[Push] registration failed: \(error.localizedDescription)")
    }

    /// Inbound Push (CloudKit-Notification). Wird sowohl im Vorder- als auch
    /// Hintergrund aufgerufen. Wir nutzen das um den Feed sofort zu refreshen
    /// → Daten ankommen schon bevor User die App öffnet, Notification ist nur
    /// das Trigger-Signal.
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        Task {
            await CloudKitService.shared.handleIncomingPush(userInfo: userInfo)
            completionHandler(.newData)
        }
    }
}

@main
struct SimpleTrackingApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
    @State private var contestService    = ContestService.shared
    @State private var teamService       = TeamService.shared

    // Deep-Link aus iMessage / QR-Scan: simpletracking://friend?code=ABC-123
    @State private var pendingFriendCode: String?
    // Contest-Invite-Code aus Universal Link
    @State private var pendingContestCode: String?

    // Onboarding beim ersten Start
    @State private var hasCompletedOnboarding: Bool = UserDefaults.standard.hasCompletedOnboarding

    init() {
        Theme.applyAppearance()
        let settings = UserSettings.shared
        settings.ensureProfileDefaults(deviceName: UIDevice.current.name)
        // Falls Profilname noch ein „weak default" ist (alte Installation
        // mit „iPhone" als Name), durch GC-Name oder Random-Funname ersetzen.
        if UserSettings.isWeakDefaultName(settings.profileName) {
            let gcName = GameCenterService.shared.isAuthenticated
                ? GameCenterService.shared.playerName
                : nil
            settings.profileName = ""  // zurücksetzen damit ensureProfileDefaults greift
            settings.ensureProfileDefaults(deviceName: UIDevice.current.name, gameCenterName: gcName)
        }
        AdService.shared.start()
        Task { await CloudKitService.shared.setup() }
        Task { await ContestNotificationService.shared.setup() }

        // Game Center automatisch reauthentifizieren, sobald Sync einmal
        // aktiviert wurde. Game Center cached die Credentials systemweit —
        // wenn der Nutzer auf dem Gerät bereits eingeloggt ist, läuft das
        // ohne UI durch. Andernfalls bleibt der Status auf "Nicht angemeldet".
        if settings.gameCenterSyncEnabled {
            Task {
                await GameCenterService.shared.authenticate()
                // Nach erfolgreichem Login: GC-Name übernehmen falls aktueller
                // Profilname schwach ist + CloudKit-Profil aktualisieren.
                if GameCenterService.shared.isAuthenticated {
                    let gcName = GameCenterService.shared.playerName
                    await MainActor.run {
                        UserSettings.shared.applyGameCenterNameIfBetter(gcName)
                    }
                    await CloudKitService.shared.republishProfile()
                }
            }
        }

        // Verwaiste Live Activities aus früheren Versionen aufräumen
        // (alter Bug: 20-Min-Dismissal-Policy → LA blieb auf dem Lock Screen
        // sichtbar und der Timer tickte weiter, obwohl das Workout beendet war).
        // Nur ausführen, wenn KEIN Workout gerade läuft.
        if WorkoutDraftStore.shared.currentDraft?.status != .active {
            WorkoutSurfaceService.shared.purgeOrphanLiveActivities()
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding {
                    ContentView()
                } else {
                    OnboardingView(hasCompletedOnboarding: Binding(
                        get: { hasCompletedOnboarding },
                        set: { newValue in
                            hasCompletedOnboarding = newValue
                            UserDefaults.standard.hasCompletedOnboarding = newValue
                        }
                    ))
                }
            }
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
                .environment(contestService)
                .environment(teamService)
                .preferredColorScheme(settings.colorScheme.colorScheme)
                .onOpenURL { url in handleIncomingURL(url) }
                .sheet(item: Binding(
                    get: { pendingFriendCode.map { FriendCodeInvite(code: $0) } },
                    set: { newValue in pendingFriendCode = newValue?.code }
                )) { invite in
                    AddFriendSheet(prefilledCode: invite.code)
                        .environment(cloudKit)
                }
                .sheet(item: Binding(
                    get: { pendingContestCode.map { ContestCodeInvite(code: $0) } },
                    set: { newValue in pendingContestCode = newValue?.code }
                )) { invite in
                    ContestJoinSheet(prefilledCode: invite.code)
                        .environment(cloudKit)
                        .environment(contestService)
                }
        }
    }

    private func handleIncomingURL(_ url: URL) {
        // Akzeptiert mehrere Formate:
        //   simpletracking://friend?code=ABC-123        (Custom URL Scheme)
        //   simpletracking://contest?code=ABCD-EF12     (Contest Custom URL Scheme)
        //   https://tfb74.github.io/SimpleTracker/friend?code=...   (Universal Link)
        //   https://tfb74.github.io/SimpleTracker/contest?code=...  (Universal Link Contest)
        let scheme = url.scheme?.lowercased() ?? ""
        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()

        let isCustomFriend = scheme == "simpletracking" && host == "friend"
        let isCustomContest = scheme == "simpletracking" && host == "contest"
        let isHttp = scheme == "https" || scheme == "http"
        let isUniversalFriend = isHttp && host == "tfb74.github.io" && path.hasSuffix("/friend")
        let isUniversalContest = isHttp && host == "tfb74.github.io" && path.hasSuffix("/contest")

        guard isCustomFriend || isCustomContest || isUniversalFriend || isUniversalContest else { return }

        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard let code = comps?.queryItems?.first(where: { $0.name == "code" })?.value,
              !code.isEmpty else { return }

        if isCustomFriend || isUniversalFriend {
            pendingFriendCode = code
        } else {
            pendingContestCode = code
        }
    }
}

private struct FriendCodeInvite: Identifiable {
    let code: String
    var id: String { code }
}

private struct ContestCodeInvite: Identifiable {
    let code: String
    var id: String { code }
}
