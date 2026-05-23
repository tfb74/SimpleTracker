import ActivityKit
import Foundation
import WidgetKit

@MainActor
final class WorkoutSurfaceService {
    static let shared = WorkoutSurfaceService()

    private var liveActivity: Activity<WorkoutActivityAttributes>?

    private init() {}

    func startWorkout(
        workoutName: String,
        systemImageName: String,
        startDate: Date,
        distanceMeters: Double,
        speedMetersPerSecond: Double,
        unit: TrackingDistanceUnit
    ) {
        let state = WorkoutActivityAttributes.ContentState(
            distanceMeters: distanceMeters,
            speedMetersPerSecond: speedMetersPerSecond,
            lastUpdated: Date(),
            unit: unit
        )
        let snapshot = TrackingSnapshot(
            status: .active,
            workoutName: workoutName,
            systemImageName: systemImageName,
            startDate: startDate,
            endDate: nil,
            lastUpdated: state.lastUpdated,
            distanceMeters: distanceMeters,
            speedMetersPerSecond: speedMetersPerSecond,
            unit: unit
        )

        persist(snapshot)

        let attributes = WorkoutActivityAttributes(
            workoutName: workoutName,
            systemImageName: systemImageName,
            startDate: startDate
        )
        Task { await startLiveActivity(attributes: attributes, state: state) }
    }

    func updateWorkout(
        workoutName: String,
        systemImageName: String,
        startDate: Date,
        distanceMeters: Double,
        speedMetersPerSecond: Double,
        unit: TrackingDistanceUnit
    ) {
        let state = WorkoutActivityAttributes.ContentState(
            distanceMeters: distanceMeters,
            speedMetersPerSecond: speedMetersPerSecond,
            lastUpdated: Date(),
            unit: unit
        )
        let snapshot = TrackingSnapshot(
            status: .active,
            workoutName: workoutName,
            systemImageName: systemImageName,
            startDate: startDate,
            endDate: nil,
            lastUpdated: state.lastUpdated,
            distanceMeters: distanceMeters,
            speedMetersPerSecond: speedMetersPerSecond,
            unit: unit
        )

        persist(snapshot)
        Task { await updateLiveActivity(state) }
    }

    func finishWorkout(
        workoutName: String,
        systemImageName: String,
        startDate: Date,
        endDate: Date,
        distanceMeters: Double,
        unit: TrackingDistanceUnit
    ) {
        let state = WorkoutActivityAttributes.ContentState(
            distanceMeters: distanceMeters,
            speedMetersPerSecond: 0,
            lastUpdated: endDate,
            unit: unit
        )
        let snapshot = TrackingSnapshot(
            status: .completed,
            workoutName: workoutName,
            systemImageName: systemImageName,
            startDate: startDate,
            endDate: endDate,
            lastUpdated: endDate,
            distanceMeters: distanceMeters,
            speedMetersPerSecond: 0,
            unit: unit
        )

        persist(snapshot)
        Task { await endLiveActivities(with: state) }
    }

    /// Beim App-Start aufrufen: räumt verwaiste Live Activities weg, die durch
    /// frühere Versionen mit verzögerter Dismissal-Policy auf dem Lock Screen
    /// kleben geblieben sind, obwohl das Workout längst beendet wurde.
    /// Nur sicher zu rufen, wenn KEIN Workout gerade aktiv ist.
    func purgeOrphanLiveActivities() {
        Task {
            for activity in Activity<WorkoutActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            await MainActor.run { self.liveActivity = nil }
        }
    }

    func updateStatistics(
        healthKit: HealthKitService,
        settings: UserSettings,
        foodLog: FoodLogStore
    ) {
        let calendar = Calendar.current
        let todayWorkouts = healthKit.workouts.filter { calendar.isDateInToday($0.startDate) }
        let food = foodLog.totals(on: Date())
        let unit = TrackingDistanceUnit(rawValue: settings.unitPreference.rawValue) ?? .metric
        let bestScore = healthKit.workouts
            .map { $0.score(settings: settings).displayScore }
            .max()

        let snapshot = TrackingStatisticsSnapshot(
            lastUpdated: Date(),
            steps: healthKit.todaySteps,
            activeCalories: healthKit.todayCalories,
            distanceMeters: healthKit.todayDistanceKm * 1_000,
            consumedCalories: food.kcal,
            carbsGrams: food.carbs,
            breadUnits: food.be,
            foodEntryCount: foodLog.entries(on: Date()).count,
            workoutCountToday: todayWorkouts.count,
            workoutDistanceMetersToday: todayWorkouts.reduce(0.0) { $0 + $1.distanceMeters },
            bestScore: bestScore,
            unit: unit
        )

        TrackingWidgetStore.saveStatisticsSnapshot(snapshot)
        WidgetCenter.shared.reloadTimelines(ofKind: TrackingWidgetConstants.widgetKind)
    }

    private func persist(_ snapshot: TrackingSnapshot) {
        TrackingWidgetStore.saveSnapshot(snapshot)
        WidgetCenter.shared.reloadTimelines(ofKind: TrackingWidgetConstants.widgetKind)
    }

    private func startLiveActivity(
        attributes: WorkoutActivityAttributes,
        state: WorkoutActivityAttributes.ContentState
    ) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        for activity in Activity<WorkoutActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        do {
            liveActivity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: Date().addingTimeInterval(90)),
                pushType: nil
            )
        } catch {
            print("[LiveActivity] start failed: \(error.localizedDescription)")
        }
    }

    private func updateLiveActivity(_ state: WorkoutActivityAttributes.ContentState) async {
        guard let activity = liveActivity ?? Activity<WorkoutActivityAttributes>.activities.first else { return }
        liveActivity = activity
        await activity.update(
            ActivityContent(state: state, staleDate: Date().addingTimeInterval(90))
        )
    }

    private func endLiveActivities(with state: WorkoutActivityAttributes.ContentState) async {
        // WICHTIG: .immediate verwenden, sonst bleibt die Live Activity bis zu 20 Min
        // auf dem Lock Screen sichtbar und der eingebaute Timer (Text(timerInterval:))
        // tickt weiter hoch — Nutzer denken das Workout läuft noch, obwohl GPS und
        // alles längst gestoppt ist.
        let content = ActivityContent(state: state, staleDate: nil)
        for activity in Activity<WorkoutActivityAttributes>.activities {
            await activity.end(content, dismissalPolicy: .immediate)
        }
        liveActivity = nil
    }
}
