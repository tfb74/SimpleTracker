import Foundation

struct WorkoutMetrics: Codable {
    var steps: Int = 0
    var activeCalories: Double = 0
    var distanceMeters: Double = 0
    var durationSeconds: TimeInterval = 0
    var currentSpeedMPS: Double = 0
    var heartRate: Double = 0
    var isActive: Bool = false
    var workoutType: String = WorkoutType.walking.rawValue
}

enum WatchCommand: String {
    case startWorkout = "start"
    case stopWorkout  = "stop"
    case pauseWorkout = "pause"
    case resumeWorkout = "resume"
}

enum WatchMessage {
    static let metricsKey     = "metrics"
    static let commandKey     = "command"
    static let workoutTypeKey = "workoutType"
}
