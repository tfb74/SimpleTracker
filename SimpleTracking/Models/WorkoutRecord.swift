import Foundation

struct WorkoutRecord: Identifiable, Codable {
    let id: UUID
    let workoutType: WorkoutType
    let startDate: Date
    let endDate: Date
    let steps: Int
    let activeCalories: Double
    let distanceMeters: Double
    let route: [RoutePoint]
    let averageSpeedMPS: Double
    let maxSpeedMPS: Double
    let heartRateAvg: Double
    let hkWorkoutUUID: UUID?

    var duration: TimeInterval      { endDate.timeIntervalSince(startDate) }
    var distanceKm: Double          { distanceMeters / 1_000 }
    var distanceMiles: Double       { distanceMeters / 1_609.344 }
    var averageSpeedKmh: Double     { averageSpeedMPS * 3.6 }
    var maxSpeedKmh: Double         { maxSpeedMPS * 3.6 }

    func formattedDistance(unit: UnitPreference) -> String {
        unit.formatted(meters: distanceMeters)
    }

    var pacePerKm: String {
        guard averageSpeedMPS > 0 else { return "--:--" }
        let secPerKm = 1_000 / averageSpeedMPS
        return String(format: "%d:%02d min/km", Int(secPerKm) / 60, Int(secPerKm) % 60)
    }

    var pacePerMile: String {
        guard averageSpeedMPS > 0 else { return "--:--" }
        let secPerMile = 1_609.344 / averageSpeedMPS
        return String(format: "%d:%02d min/mi", Int(secPerMile) / 60, Int(secPerMile) % 60)
    }
}
