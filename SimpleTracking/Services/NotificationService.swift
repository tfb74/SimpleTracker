import Foundation
import UserNotifications

@Observable
final class NotificationService {
    static let shared = NotificationService()
    var isAuthorized = false

    private init() {}

    func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await MainActor.run { isAuthorized = granted }
    }

    /// Call during workout whenever distance crosses the next interval boundary.
    /// Returns the number of notifications that should be fired (usually 0 or 1).
    func checkMilestone(
        previousMeters: Double,
        currentMeters: Double,
        unit: UnitPreference,
        workoutType: WorkoutType,
        speedMPS: Double
    ) {
        let interval = unit.notificationIntervalMeters
        let prevInterval = Int(previousMeters / interval)
        let currInterval = Int(currentMeters / interval)
        guard currInterval > prevInterval, currInterval > 0 else { return }

        let count = currInterval
        let label = unit.distanceLabel
        let speedLabel = speedLabel(speedMPS: speedMPS, unit: unit, workoutType: workoutType)

        let content = UNMutableNotificationContent()
        content.title = lf("%d %@ geschafft! 🎉", count, label)
        content.body  = speedLabel
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "milestone_\(count)_\(label)",
            content: content,
            trigger: nil   // deliver immediately
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func speedLabel(speedMPS: Double, unit: UnitPreference, workoutType: WorkoutType) -> String {
        guard speedMPS > 0 else { return "" }
        switch unit {
        case .metric:
            let kmh = speedMPS * 3.6
            if workoutType == .running || workoutType == .walking || workoutType == .hiking {
                let secPerKm = 1_000 / speedMPS
                return lf("Tempo: %d:%02d min/km", Int(secPerKm) / 60, Int(secPerKm) % 60)
            }
            return String(format: "%.1f km/h", kmh)
        case .imperial:
            let mph = speedMPS * 2.23694
            if workoutType == .running || workoutType == .walking || workoutType == .hiking {
                let secPerMile = 1_609.344 / speedMPS
                return lf("Pace: %d:%02d min/mi", Int(secPerMile) / 60, Int(secPerMile) % 60)
            }
            return String(format: "%.1f mph", mph)
        }
    }
}
