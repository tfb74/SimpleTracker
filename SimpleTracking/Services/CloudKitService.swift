import Foundation
import UIKit

// MARK: - Models

struct FriendProfile: Identifiable, Codable, Hashable {
    var id: String { code }
    let code: String
    var displayName: String
    var avatarPreset: String
}

struct FriendActivity: Identifiable, Codable {
    let id: String
    let friendCode: String
    let displayName: String
    let avatarPreset: String
    let eventType: FriendActivityType
    let eventTitle: String
    let eventDetail: String
    let workoutTypeRaw: String?
    let timestamp: Date
    var isRead: Bool

    var workoutType: WorkoutType? {
        workoutTypeRaw.flatMap { WorkoutType(rawValue: $0) }
    }

    var avatarPresetEnum: ProfileAvatarPreset {
        ProfileAvatarPreset(rawValue: avatarPreset) ?? .person
    }
}

enum FriendActivityType: String, Codable {
    case workout
    case achievement
}

enum CloudKitError: LocalizedError {
    case friendNotFound
    case alreadyFriend
    case cannotAddSelf
    case iCloudUnavailable

    var errorDescription: String? {
        switch self {
        case .friendNotFound:    return "Kein Nutzer mit diesem Code gefunden."
        case .alreadyFriend:     return "Diese Person ist bereits in deiner Liste."
        case .cannotAddSelf:     return "Du kannst dich nicht selbst hinzufügen."
        case .iCloudUnavailable: return "iCloud ist nicht verfügbar. Bitte melde dich in den Einstellungen an."
        }
    }
}

// MARK: - Stub (CloudKit deactivated — requires paid Developer Account)

@Observable
final class CloudKitService {
    static let shared = CloudKitService()

    private(set) var friends: [FriendProfile] = []
    private(set) var feed: [FriendActivity] = []
    private(set) var isAvailable = false
    private(set) var isLoading = false
    private(set) var myFriendCode: String = ""

    var unreadCount: Int { 0 }

    private let friendsKey = "ck.friends.v1"
    private let codeKey    = "ck.myCode.v1"
    private let feedKey    = "ck.feed.v1"

    private init() {
        myFriendCode = generateOrLoadCode()
    }

    func setup() async {}

    func addFriend(code: String) async throws {
        throw CloudKitError.iCloudUnavailable
    }

    func removeFriend(code: String) {
        friends.removeAll { $0.code == code }
    }

    func refreshFeed() async {}

    func markAllRead() {}

    func publishWorkoutIfNeeded(_ workout: WorkoutRecord) async {}

    func publishAchievement(_ achievement: Achievement) async {}

    // MARK: - Helpers

    private func generateOrLoadCode() -> String {
        if let existing = UserDefaults.standard.string(forKey: codeKey), !existing.isEmpty {
            return existing
        }
        let chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        let raw   = String((0..<6).map { _ in chars.randomElement()! })
        let code  = "\(raw.prefix(3))-\(raw.dropFirst(3))"
        UserDefaults.standard.set(code, forKey: codeKey)
        return code
    }
}
