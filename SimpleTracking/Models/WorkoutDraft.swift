import Foundation

enum WorkoutDraftStatus: String, Codable {
    case active
    case pendingSave
}

struct WorkoutDraft: Codable, Identifiable {
    let id: UUID
    let workoutType: WorkoutType
    let startDate: Date
    let endDate: Date?
    let lastUpdated: Date
    let distanceMeters: Double
    let route: [RoutePoint]
    let status: WorkoutDraftStatus
    /// Akkumulierte Pause-Zeit in Sekunden. Wird in elapsedSinceStart()
    /// abgezogen damit die reine Aktivzeit korrekt bleibt — auch wenn die
    /// App nach App-Restart aus dem Draft wiederhergestellt wird.
    let pausedSeconds: TimeInterval?
    /// True wenn das Workout im Moment des letzten Saves pausiert war.
    let isPaused: Bool?
    /// Zeitpunkt zu dem die aktuelle Pause begann (falls isPaused=true).
    /// Wird beim Resume genutzt um die Pause-Dauer zu pausedSeconds zu addieren.
    let pauseStartedAt: Date?

    init(
        id: UUID = UUID(),
        workoutType: WorkoutType,
        startDate: Date,
        endDate: Date? = nil,
        lastUpdated: Date = Date(),
        distanceMeters: Double,
        route: [RoutePoint],
        status: WorkoutDraftStatus,
        pausedSeconds: TimeInterval? = nil,
        isPaused: Bool? = nil,
        pauseStartedAt: Date? = nil
    ) {
        self.id = id
        self.workoutType = workoutType
        self.startDate = startDate
        self.endDate = endDate
        self.lastUpdated = lastUpdated
        self.distanceMeters = distanceMeters
        self.route = route
        self.status = status
        self.pausedSeconds = pausedSeconds
        self.isPaused = isPaused
        self.pauseStartedAt = pauseStartedAt
    }
}
