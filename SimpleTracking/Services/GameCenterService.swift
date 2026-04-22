import Foundation
import GameKit
import HealthKit

// MARK: - Achievement IDs  (müssen 1:1 in App Store Connect angelegt werden)
enum Achievement: String, CaseIterable {
    case firstWorkout      = "com.felix.SimpleTracking.first_workout"
    case fiveWorkouts      = "com.felix.SimpleTracking.five_workouts"
    case twentyWorkouts    = "com.felix.SimpleTracking.twenty_workouts"
    case firstKilometer    = "com.felix.SimpleTracking.first_km"
    case run5km            = "com.felix.SimpleTracking.run_5km"
    case run10km           = "com.felix.SimpleTracking.run_10km"
    case run21km           = "com.felix.SimpleTracking.run_halfmarathon"
    case run42km           = "com.felix.SimpleTracking.run_marathon"
    case total50km         = "com.felix.SimpleTracking.total_50km"
    case total100km        = "com.felix.SimpleTracking.total_100km"
    case steps10k          = "com.felix.SimpleTracking.steps_10k_day"
    case earlyBird         = "com.felix.SimpleTracking.early_bird"    // vor 7 Uhr
    case nightOwl          = "com.felix.SimpleTracking.night_owl"     // nach 20 Uhr
    case allTypes          = "com.felix.SimpleTracking.all_types"     // alle 4 Sportarten

    var displayName: String {
        switch self {
        case .firstWorkout:   return "Erster Schritt"
        case .fiveWorkouts:   return "Fünf Workouts"
        case .twentyWorkouts: return "Fitness-Enthusiast"
        case .firstKilometer: return "Erster Kilometer"
        case .run5km:         return "5-km-Läufer"
        case .run10km:        return "10-km-Läufer"
        case .run21km:        return "Halbmarathon"
        case .run42km:        return "Marathonläufer"
        case .total50km:      return "50 km Gesamtstrecke"
        case .total100km:     return "100 km Gesamtstrecke"
        case .steps10k:       return "10.000 Schritte"
        case .earlyBird:      return "Frühaufsteher"
        case .nightOwl:       return "Nachteule"
        case .allTypes:       return "Allrounder"
        }
    }

    var description: String {
        switch self {
        case .firstWorkout:   return "Erstes Workout abgeschlossen"
        case .fiveWorkouts:   return "5 Workouts abgeschlossen"
        case .twentyWorkouts: return "20 Workouts abgeschlossen"
        case .firstKilometer: return "Ersten Kilometer zurückgelegt"
        case .run5km:         return "5 km in einem Lauf"
        case .run10km:        return "10 km in einem Lauf"
        case .run21km:        return "Halbmarathon (21,1 km) in einem Lauf"
        case .run42km:        return "Marathon (42,2 km) in einem Lauf"
        case .total50km:      return "50 km Gesamtstrecke aller Workouts"
        case .total100km:     return "100 km Gesamtstrecke aller Workouts"
        case .steps10k:       return "10.000 Schritte an einem Tag"
        case .earlyBird:      return "Workout vor 7:00 Uhr gestartet"
        case .nightOwl:       return "Workout nach 20:00 Uhr gestartet"
        case .allTypes:       return "Laufen, Gehen, Radfahren und Wandern absolviert"
        }
    }

    var icon: String {
        switch self {
        case .firstWorkout:   return "figure.walk.circle.fill"
        case .fiveWorkouts:   return "5.circle.fill"
        case .twentyWorkouts: return "rosette"
        case .firstKilometer: return "mappin.circle.fill"
        case .run5km:         return "figure.run.circle.fill"
        case .run10km:        return "medal.fill"
        case .run21km:        return "medal.fill"
        case .run42km:        return "trophy.fill"
        case .total50km:      return "road.lanes"
        case .total100km:     return "road.lanes.curved.left"
        case .steps10k:       return "figure.walk.motion"
        case .earlyBird:      return "sunrise.fill"
        case .nightOwl:       return "moon.stars.fill"
        case .allTypes:       return "square.grid.2x2.fill"
        }
    }
}

// MARK: - Leaderboard IDs
enum Leaderboard: String {
    case weeklySteps      = "com.felix.SimpleTracking.leaderboard.weekly_steps"
    case monthlyDistKm    = "com.felix.SimpleTracking.leaderboard.monthly_dist"
    case bestWorkoutScore = "com.felix.SimpleTracking.leaderboard.best_score"
    case totalScore       = "com.felix.SimpleTracking.leaderboard.total_score"
}

// MARK: - Service

@Observable
final class GameCenterService {
    static let shared = GameCenterService()

    var isAuthenticated = false
    var playerName      = ""
    var playerAvatar:   UIImage? = nil

    private let localStore = LocalAchievementStore.shared

    /// Unlocked achievements derived from the local store — always authoritative.
    var unlockedAchievements: Set<Achievement> {
        Set(localStore.unlockedIdentifiers.compactMap { Achievement(rawValue: $0) })
    }

    private init() {}

    // MARK: - Authentication (only used when user opted into GC sync)

    func authenticate() async {
        await withCheckedContinuation { cont in
            GKLocalPlayer.local.authenticateHandler = { [weak self] _, _ in
                guard let self else { cont.resume(); return }
                if GKLocalPlayer.local.isAuthenticated {
                    Task { @MainActor in
                        self.isAuthenticated = true
                        self.playerName = GKLocalPlayer.local.displayName
                        self.playerAvatar = try? await GKLocalPlayer.local.loadPhoto(for: .small)
                        self.syncLocalToGameCenter()
                    }
                }
                cont.resume()
            }
        }
    }

    /// Replays every locally unlocked achievement to Game Center.
    /// Safe to call repeatedly: GC dedupes reports with identical percentComplete.
    func syncLocalToGameCenter() {
        guard isAuthenticated else { return }
        let gkAchievements: [GKAchievement] = localStore.unlocks.map { id, _ in
            let a = GKAchievement(identifier: id)
            a.percentComplete = 100
            a.showsCompletionBanner = false       // already granted locally
            return a
        }
        guard !gkAchievements.isEmpty else { return }
        GKAchievement.report(gkAchievements) { _ in }
    }

    // MARK: - Report Achievement (local primary, GC optional)

    func unlock(_ achievement: Achievement, percentComplete: Double = 100) {
        let justUnlocked = localStore.unlock(achievement.rawValue)

        if justUnlocked {
            Task { await CloudKitService.shared.publishAchievement(achievement) }
        }

        guard isAuthenticated else { return }
        let gk = GKAchievement(identifier: achievement.rawValue)
        gk.percentComplete = percentComplete
        gk.showsCompletionBanner = justUnlocked
        GKAchievement.report([gk]) { _ in }
    }

    // MARK: - Report Score to Leaderboard (GC-only; no local equivalent)

    func submitScore(_ score: Int, to leaderboard: Leaderboard) {
        guard isAuthenticated else { return }
        GKLeaderboard.submitScore(score, context: 0, player: GKLocalPlayer.local,
            leaderboardIDs: [leaderboard.rawValue]) { _ in }
    }

    // MARK: - Check Achievements After Workout

    func evaluateAchievements(for workouts: [WorkoutRecord], todaySteps: Int, settings: UserSettings? = nil) {
        // Unlocks are always evaluated locally; GC reporting only fires when authenticated.

        // Workout count
        if workouts.count >= 1  { unlock(.firstWorkout) }
        if workouts.count >= 5  { unlock(.fiveWorkouts) }
        if workouts.count >= 20 { unlock(.twentyWorkouts) }

        // Longest single run
        let longestRun = workouts.filter { $0.workoutType == .running }.map(\.distanceMeters).max() ?? 0
        if longestRun >= 1_000  { unlock(.firstKilometer) }
        if longestRun >= 5_000  { unlock(.run5km) }
        if longestRun >= 10_000 { unlock(.run10km) }
        if longestRun >= 21_097 { unlock(.run21km) }
        if longestRun >= 42_195 { unlock(.run42km) }

        // Total distance
        let totalM = workouts.reduce(0.0) { $0 + $1.distanceMeters }
        if totalM >= 50_000  { unlock(.total50km) }
        if totalM >= 100_000 { unlock(.total100km) }

        // Steps
        if todaySteps >= 10_000 { unlock(.steps10k) }

        // Time-based
        let hours = workouts.compactMap { Calendar.current.component(.hour, from: $0.startDate) }
        if hours.contains(where: { $0 < 7 })  { unlock(.earlyBird) }
        if hours.contains(where: { $0 >= 20 }) { unlock(.nightOwl) }

        // All sport types
        let types = Set(workouts.map(\.workoutType))
        if types == Set(WorkoutType.allCases) { unlock(.allTypes) }

        // Weekly steps leaderboard
        submitScore(todaySteps * 7, to: .weeklySteps)

        // Monthly distance leaderboard (km as integer)
        let monthDist = Int(totalM / 1_000)
        submitScore(monthDist, to: .monthlyDistKm)

        // Score leaderboards
        if let settings {
            let scores = workouts.map { $0.score(settings: settings).displayScore }
            if let best = scores.max() {
                submitScore(best, to: .bestWorkoutScore)
            }
            submitScore(scores.reduce(0, +), to: .totalScore)
        }
    }

    // MARK: - Show GameCenter UI

    func showLeaderboards() {
        guard isAuthenticated,
              let vc = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first?.windows.first?.rootViewController
        else { return }
        let gcVC = GKGameCenterViewController(state: .leaderboards)
        gcVC.gameCenterDelegate = GameCenterDismissDelegate.shared
        vc.present(gcVC, animated: true)
    }

    func showAchievements() {
        guard isAuthenticated,
              let vc = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first?.windows.first?.rootViewController
        else { return }
        let gcVC = GKGameCenterViewController(state: .achievements)
        gcVC.gameCenterDelegate = GameCenterDismissDelegate.shared
        vc.present(gcVC, animated: true)
    }
}

// MARK: - Dismiss helper (GKGameCenterControllerDelegate needs NSObject)

private final class GameCenterDismissDelegate: NSObject, GKGameCenterControllerDelegate {
    static let shared = GameCenterDismissDelegate()
    nonisolated func gameCenterViewControllerDidFinish(_ vc: GKGameCenterViewController) {
        vc.dismiss(animated: true)
    }
}
