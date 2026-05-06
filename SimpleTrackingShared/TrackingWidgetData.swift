import ActivityKit
import Foundation

enum TrackingDistanceUnit: String, Codable, Hashable {
    case metric
    case imperial

    var distanceLabel: String {
        switch self {
        case .metric: return "km"
        case .imperial: return "mi"
        }
    }

    var paceLabel: String {
        switch self {
        case .metric: return "/km"
        case .imperial: return "/mi"
        }
    }

    var unitMeters: Double {
        switch self {
        case .metric: return 1_000
        case .imperial: return 1_609.344
        }
    }

    func formattedDistance(meters: Double) -> String {
        String(format: "%.2f %@", meters / unitMeters, distanceLabel)
    }

    func compactDistance(meters: Double) -> String {
        switch self {
        case .metric where meters < 1_000:
            return String(format: "%.0f m", meters)
        case .imperial where meters < 1_609.344:
            return String(format: "%.0f ft", meters * 3.28084)
        default:
            return String(format: "%.1f %@", meters / unitMeters, distanceLabel)
        }
    }

    func formattedPace(speedMetersPerSecond: Double) -> String {
        guard speedMetersPerSecond > 0.2 else { return "--" }
        let secondsPerUnit = unitMeters / speedMetersPerSecond
        return String(format: "%d:%02d %@", Int(secondsPerUnit) / 60, Int(secondsPerUnit) % 60, paceLabel)
    }
}

enum TrackingSnapshotStatus: String, Codable, Hashable {
    case idle
    case active
    case completed
}

struct TrackingSnapshot: Codable, Hashable {
    var status: TrackingSnapshotStatus
    var workoutName: String
    var systemImageName: String
    var startDate: Date?
    var endDate: Date?
    var lastUpdated: Date
    var distanceMeters: Double
    var speedMetersPerSecond: Double
    var unit: TrackingDistanceUnit

    var isActive: Bool {
        status == .active
    }

    var formattedDistance: String {
        unit.formattedDistance(meters: distanceMeters)
    }

    var compactDistance: String {
        unit.compactDistance(meters: distanceMeters)
    }

    var formattedPace: String {
        unit.formattedPace(speedMetersPerSecond: speedMetersPerSecond)
    }

    var distanceProgressToNextUnit: Double {
        let progress = distanceMeters.truncatingRemainder(dividingBy: unit.unitMeters) / unit.unitMeters
        return max(0.04, min(progress, 1))
    }

    func duration(at date: Date = Date()) -> TimeInterval {
        guard let startDate else { return 0 }
        let end = endDate ?? date
        return max(0, end.timeIntervalSince(startDate))
    }

    func formattedDuration(at date: Date = Date()) -> String {
        let value = Int(duration(at: date))
        let hours = value / 3_600
        let minutes = (value % 3_600) / 60
        let seconds = value % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    static let idle = TrackingSnapshot(
        status: .idle,
        workoutName: "Workout",
        systemImageName: "figure.run",
        startDate: nil,
        endDate: nil,
        lastUpdated: Date(),
        distanceMeters: 0,
        speedMetersPerSecond: 0,
        unit: .metric
    )

    static let previewActive = TrackingSnapshot(
        status: .active,
        workoutName: "Laufen",
        systemImageName: "figure.run",
        startDate: Date().addingTimeInterval(-1_842),
        endDate: nil,
        lastUpdated: Date(),
        distanceMeters: 4_280,
        speedMetersPerSecond: 3.05,
        unit: .metric
    )

    static let previewCompleted = TrackingSnapshot(
        status: .completed,
        workoutName: "Radfahren",
        systemImageName: "figure.outdoor.cycle",
        startDate: Date().addingTimeInterval(-3_960),
        endDate: Date().addingTimeInterval(-180),
        lastUpdated: Date().addingTimeInterval(-180),
        distanceMeters: 17_340,
        speedMetersPerSecond: 0,
        unit: .metric
    )
}

struct TrackingStatisticsSnapshot: Codable, Hashable {
    var lastUpdated: Date
    var steps: Int
    var activeCalories: Double
    var distanceMeters: Double
    var consumedCalories: Double
    var carbsGrams: Double
    var breadUnits: Double
    var foodEntryCount: Int
    var workoutCountToday: Int
    var workoutDistanceMetersToday: Double
    var bestScore: Int?
    var unit: TrackingDistanceUnit

    var energyBalance: Double {
        consumedCalories - activeCalories
    }

    var formattedDistance: String {
        unit.formattedDistance(meters: distanceMeters)
    }

    var compactDistance: String {
        unit.compactDistance(meters: distanceMeters)
    }

    var formattedWorkoutDistance: String {
        unit.compactDistance(meters: workoutDistanceMetersToday)
    }

    static let idle = TrackingStatisticsSnapshot(
        lastUpdated: Date(),
        steps: 0,
        activeCalories: 0,
        distanceMeters: 0,
        consumedCalories: 0,
        carbsGrams: 0,
        breadUnits: 0,
        foodEntryCount: 0,
        workoutCountToday: 0,
        workoutDistanceMetersToday: 0,
        bestScore: nil,
        unit: .metric
    )

    static let preview = TrackingStatisticsSnapshot(
        lastUpdated: Date(),
        steps: 8_420,
        activeCalories: 486,
        distanceMeters: 6_850,
        consumedCalories: 1_280,
        carbsGrams: 164,
        breadUnits: 13.7,
        foodEntryCount: 4,
        workoutCountToday: 1,
        workoutDistanceMetersToday: 4_280,
        bestScore: 742,
        unit: .metric
    )
}

struct WorkoutActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var distanceMeters: Double
        var speedMetersPerSecond: Double
        var lastUpdated: Date
        var unit: TrackingDistanceUnit

        var formattedDistance: String {
            unit.formattedDistance(meters: distanceMeters)
        }

        var compactDistance: String {
            unit.compactDistance(meters: distanceMeters)
        }

        var formattedPace: String {
            unit.formattedPace(speedMetersPerSecond: speedMetersPerSecond)
        }
    }

    var workoutName: String
    var systemImageName: String
    var startDate: Date
}

enum TrackingWidgetConstants {
    static let appGroupIdentifier = "group.de.baumannheim.SimpleTracking"
    static let snapshotKey = "trackingSnapshot"
    static let statisticsSnapshotKey = "trackingStatisticsSnapshot"
    static let widgetKind = "TrackingStatusWidget"
    static let workoutURL = URL(string: "simpletracking://workout")
    static let todayURL = URL(string: "simpletracking://today")
}

enum TrackingWidgetStore {
    static func loadSnapshot() -> TrackingSnapshot {
        guard let data = defaults.data(forKey: TrackingWidgetConstants.snapshotKey),
              let snapshot = try? JSONDecoder().decode(TrackingSnapshot.self, from: data) else {
            return .idle
        }
        return snapshot
    }

    static func saveSnapshot(_ snapshot: TrackingSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: TrackingWidgetConstants.snapshotKey)
    }

    static func loadStatisticsSnapshot() -> TrackingStatisticsSnapshot {
        guard let data = defaults.data(forKey: TrackingWidgetConstants.statisticsSnapshotKey),
              let snapshot = try? JSONDecoder().decode(TrackingStatisticsSnapshot.self, from: data) else {
            return .idle
        }
        return snapshot
    }

    static func saveStatisticsSnapshot(_ snapshot: TrackingStatisticsSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: TrackingWidgetConstants.statisticsSnapshotKey)
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: TrackingWidgetConstants.appGroupIdentifier) ?? .standard
    }
}
