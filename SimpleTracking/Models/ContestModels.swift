import Foundation

// MARK: - Contest

enum ContestType: String, CaseIterable, Codable, Identifiable {
    case dailyStreak       // jeden Tag X erreichen
    case cumulativeTotal   // Gesamtsumme bis Deadline
    case scoreRace         // höchster einzelner Workout-Score
    case calorieGoal       // aktive Kalorien kumuliert

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dailyStreak:     return lt("Daily Streak")
        case .cumulativeTotal: return lt("Gesamtsumme")
        case .scoreRace:       return lt("Score-Race")
        case .calorieGoal:     return lt("Kalorien-Ziel")
        }
    }

    var systemImage: String {
        switch self {
        case .dailyStreak:     return "calendar.badge.checkmark"
        case .cumulativeTotal: return "sum"
        case .scoreRace:       return "trophy.fill"
        case .calorieGoal:     return "flame.fill"
        }
    }

    var explanation: String {
        switch self {
        case .dailyStreak:     return lt("Erreiche das Tagesziel jeden Tag bis zur Deadline.")
        case .cumulativeTotal: return lt("Summiere bis zur Deadline so viel wie möglich.")
        case .scoreRace:       return lt("Wer den höchsten einzelnen Workout-Score erreicht, gewinnt.")
        case .calorieGoal:     return lt("Verbrenne kumuliert die meisten aktiven Kalorien.")
        }
    }
}

enum ContestMetric: String, CaseIterable, Codable {
    case steps
    case distanceKm
    case calories
    case workoutScore

    var displayName: String {
        switch self {
        case .steps:        return lt("Schritte")
        case .distanceKm:   return lt("Distanz (km)")
        case .calories:     return lt("Kalorien")
        case .workoutScore: return lt("Workout-Score")
        }
    }

    var unit: String {
        switch self {
        case .steps:        return ""
        case .distanceKm:   return "km"
        case .calories:     return "kcal"
        case .workoutScore: return lt("Punkte")
        }
    }

    /// Erlaubte Metriken pro Typ — nicht alle Kombinationen ergeben Sinn.
    static func allowed(for type: ContestType) -> [ContestMetric] {
        switch type {
        case .dailyStreak:     return [.steps, .distanceKm, .calories]
        case .cumulativeTotal: return [.steps, .distanceKm, .calories]
        case .scoreRace:       return [.workoutScore]
        case .calorieGoal:     return [.calories]
        }
    }
}

enum ContestScope: String, Codable {
    case friends   // ad-hoc Friend-Kreis (kein Team)
    case team      // festes Team
    case company   // Firma mit Sub-Teams
}

struct Contest: Identifiable, Codable, Hashable {
    let contestID: String
    let ownerCode: String
    var title: String
    var description: String?
    let type: ContestType
    let metric: ContestMetric
    var targetValue: Double
    let startDate: Date
    let endDate: Date
    let scope: ContestScope
    var teamID: String?
    let inviteCode: String
    var isActive: Bool

    var id: String { contestID }

    var isInProgress: Bool {
        let now = Date()
        return isActive && startDate <= now && endDate >= now
    }
    var isUpcoming: Bool {
        isActive && startDate > Date()
    }
    var isFinished: Bool {
        !isActive || endDate < Date()
    }

    /// Verbleibende Zeit bis Ende — formatiert als Kurzstring.
    func remainingLabel(now: Date = Date()) -> String {
        let interval = endDate.timeIntervalSince(now)
        guard interval > 0 else { return lt("Beendet") }
        let days = Int(interval / 86_400)
        if days >= 2 { return lf("noch %d Tage", days) }
        let hours = Int(interval / 3600)
        if hours >= 2 { return lf("noch %d Stunden", hours) }
        let mins = max(1, Int(interval / 60))
        return lf("noch %d Min", mins)
    }
}

// MARK: - Participant

struct ContestParticipant: Identifiable, Codable, Hashable {
    let participantID: String
    let contestID: String
    let userCode: String
    let displayName: String
    let avatarPreset: String
    let joinedAt: Date
    var subTeamID: String?

    var id: String { participantID }

    var avatarPresetEnum: ProfileAvatarPreset {
        ProfileAvatarPreset(rawValue: avatarPreset) ?? .person
    }
}

// MARK: - Progress

struct ContestProgress: Identifiable, Codable, Hashable {
    let progressID: String
    let contestID: String
    let userCode: String
    let date: Date
    var value: Double
    var cumulativeValue: Double
    var dailyTargetMet: Bool

    var id: String { progressID }
}

// MARK: - Team

struct Team: Identifiable, Codable, Hashable {
    let teamID: String
    var parentTeamID: String?      // nil = Firma/Top-Level
    var name: String
    let inviteCode: String
    let ownerCode: String
    var memberCount: Int

    var id: String { teamID }

    var isSubTeam: Bool { parentTeamID != nil }
}

struct TeamMembership: Identifiable, Codable, Hashable {
    let membershipID: String
    let teamID: String
    let userCode: String
    let displayName: String
    let avatarPreset: String
    let joinedAt: Date
    var isAdmin: Bool

    var id: String { membershipID }
}

// MARK: - Aggregierter Standpunkt für Leaderboard

/// Zusammengefasster Stand eines Teilnehmers — wird vom Service errechnet
/// und ist nicht direkt persistiert. Reine View-Hilfe.
struct ContestStanding: Identifiable, Hashable {
    let participant: ContestParticipant
    var currentValue: Double           // bei Streak: erreichte Tage, bei Total: Summe, bei Score: Bestwert
    var dailyAverage: Double            // optional, für Charts
    var rank: Int
    var rankDelta: Int                  // ±N seit gestern; 0 = gleich

    var id: String { participant.id }
}

// MARK: - Errors

enum ContestError: LocalizedError {
    case contestNotFound
    case alreadyJoined
    case contestEnded
    case teamNotFound
    case notTeamAdmin
    case iCloudUnavailable
    case invalidDateRange

    var errorDescription: String? {
        switch self {
        case .contestNotFound:    return lt("Contest nicht gefunden.")
        case .alreadyJoined:      return lt("Du bist bereits Teilnehmer.")
        case .contestEnded:       return lt("Dieser Contest ist bereits beendet.")
        case .teamNotFound:       return lt("Team nicht gefunden.")
        case .notTeamAdmin:       return lt("Nur der Team-Admin darf das.")
        case .iCloudUnavailable:  return lt("iCloud ist nicht verfügbar.")
        case .invalidDateRange:   return lt("Das Enddatum muss nach dem Startdatum liegen.")
        }
    }
}

// MARK: - Helpers

enum ContestCodeGenerator {
    /// 8-stelliger Invite-Code, gut lesbar (ohne 0/O/1/I).
    static func makeInviteCode() -> String {
        let chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        let raw = String((0..<8).map { _ in chars.randomElement()! })
        return "\(raw.prefix(4))-\(raw.dropFirst(4))"
    }
}
