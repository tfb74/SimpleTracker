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

    init(
        id: UUID = UUID(),
        workoutType: WorkoutType,
        startDate: Date,
        endDate: Date? = nil,
        lastUpdated: Date = Date(),
        distanceMeters: Double,
        route: [RoutePoint],
        status: WorkoutDraftStatus
    ) {
        self.id = id
        self.workoutType = workoutType
        self.startDate = startDate
        self.endDate = endDate
        self.lastUpdated = lastUpdated
        self.distanceMeters = distanceMeters
        self.route = route
        self.status = status
    }
}
