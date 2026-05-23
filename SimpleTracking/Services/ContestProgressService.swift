import Foundation

/// Synchronisiert lokale HealthKit/Workout-Daten in CloudKit für jeden
/// aktiven Contest. Wird beim App-Start und nach Workout-Ende aufgerufen.
@MainActor
final class ContestProgressService {
    static let shared = ContestProgressService()

    private init() {}

    /// Aktualisiert für jeden aktiven Contest des Users den Tagesfortschritt.
    /// Nimmt Daten aus HealthKitService und FoodLogStore.
    func syncAllActiveContests() async {
        let service = ContestService.shared
        let healthKit = HealthKitService.shared
        let active = service.contests.filter { $0.isInProgress }
        guard !active.isEmpty else { return }

        for contest in active {
            await syncContest(contest, healthKit: healthKit)
        }
    }

    private func syncContest(_ contest: Contest, healthKit: HealthKitService) async {
        // Wert für heute aus passender Datenquelle holen
        let today = Calendar.current.startOfDay(for: Date())
        let stats = await healthKit.fetchDailyStats(for: today)

        let workoutsToday = healthKit.workouts.filter { Calendar.current.isDate($0.startDate, inSameDayAs: today) }

        // Tagessummen pro Metrik
        let todayValue: Double
        switch contest.metric {
        case .steps:
            todayValue = Double(stats.steps)
        case .distanceKm:
            todayValue = stats.distanceKm
        case .calories:
            todayValue = stats.calories
        case .workoutScore:
            // Höchster einzelner Workout-Score von heute
            let scores = workoutsToday.map { $0.score(settings: UserSettings.shared).displayScore }
            todayValue = Double(scores.max() ?? 0)
        }

        // Kumulativwert über die gesamte Contest-Periode (für Total/Calorie-Goal)
        let cumulative = await computeCumulative(
            for: contest, today: today, healthKit: healthKit, todayValue: todayValue
        )

        // Tagesziel erreicht? (für Daily Streak)
        let dailyTargetMet: Bool
        switch contest.type {
        case .dailyStreak:
            dailyTargetMet = todayValue >= contest.targetValue
        default:
            dailyTargetMet = false
        }

        await ContestService.shared.recordProgress(
            contestID: contest.contestID,
            value: todayValue,
            cumulativeValue: cumulative,
            dailyTargetMet: dailyTargetMet
        )
    }

    private func computeCumulative(
        for contest: Contest,
        today: Date,
        healthKit: HealthKitService,
        todayValue: Double
    ) async -> Double {
        // Holt für jeden Tag von Contest-Start bis heute den Wert und summiert.
        // Bei großen Zeiträumen ist das viele HK-Calls — ok für MVP, später optional cachen.
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: contest.startDate)
        guard let dayCount = calendar.dateComponents([.day], from: startDay, to: today).day else {
            return todayValue
        }

        var total: Double = 0
        for offset in 0...dayCount {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startDay) else { continue }
            let dayStats = await healthKit.fetchDailyStats(for: day)
            switch contest.metric {
            case .steps:        total += Double(dayStats.steps)
            case .distanceKm:   total += dayStats.distanceKm
            case .calories:     total += dayStats.calories
            case .workoutScore: total = max(total, todayValue)
            }
        }
        return total
    }
}
