import Foundation
import UIKit
import CloudKit

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
    var reactions: [CheerReaction] = []

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

/// Eine kurze Anfeuerung („Cheer") zu einer Aktivität — Emoji plus optionaler
/// 80-Zeichen-Text. Bewusst minimalistisch: keine Threads, keine Likes auf Kommentare.
struct CheerReaction: Codable, Identifiable, Hashable {
    let id: String              // UUID
    let activityID: String      // FK zu STActivity.activityID
    let fromCode: String
    let fromName: String        // denormalisiert für Offline-Anzeige
    let emoji: String
    let text: String?
    let timestamp: Date
}

/// Reaktions-Emojis, getrennt nach Tonart. Anfeuern ist die positive
/// Default-Variante, Necken erlaubt freundliche Sticheleien für engere
/// Freundschaften — beides ist hier okay.
enum CheerEmoji {
    /// Motivierend, positiv. Default-Auswahl.
    static let motivating: [String] = ["👍", "❤️", "🔥", "💪", "🚀", "🎉"]

    /// Frech, neckend, ironisch — für gute Freunde.
    static let teasing: [String] = ["🐌", "🥱", "😏", "🛋️", "🍻", "🤣"]

    /// Alle erlaubten Emojis (für Validation).
    static var options: [String] { motivating + teasing }

    static let maxTextLength = 80
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

// MARK: - CloudKit Record Types

private enum CKType {
    static let profile  = "STUserProfile"
    static let activity = "STActivity"
    static let reaction = "STReaction"
}

private enum CKField {
    static let code           = "code"
    static let displayName    = "displayName"
    static let avatarPreset   = "avatarPreset"
    static let lastSeen       = "lastSeen"
    // Activity
    static let activityID     = "activityID"
    static let eventType      = "eventType"
    static let eventTitle     = "eventTitle"
    static let eventDetail    = "eventDetail"
    static let workoutType    = "workoutType"
    static let timestamp      = "timestamp"
    // Reaction
    static let reactionID     = "reactionID"
    static let fromCode       = "fromCode"
    static let fromName       = "fromName"
    static let emoji          = "emoji"
    static let text           = "text"
}

// MARK: - Service

@Observable
final class CloudKitService {
    static let shared = CloudKitService()

    private(set) var friends: [FriendProfile] = []
    private(set) var feed: [FriendActivity] = []
    private(set) var isAvailable = false
    private(set) var isLoading = false
    private(set) var myFriendCode: String = ""
    private(set) var lastErrorMessage: String?

    var unreadCount: Int { feed.filter { !$0.isRead }.count }

    private let friendsKey = "ck.friends.v1"
    private let codeKey    = "ck.myCode.v1"
    private let feedKey    = "ck.feed.v1"
    private let lastReadKey = "ck.feed.lastReadAt.v1"

    private let container: CKContainer
    private var publicDB: CKDatabase { container.publicCloudDatabase }

    private init() {
        // Container muss exakt mit der Entitlement-ID übereinstimmen.
        self.container = CKContainer(identifier: "iCloud.de.baumannheim.SimpleTracking")
        self.myFriendCode = generateOrLoadCode()
        self.friends = loadCachedFriends()
        self.feed    = loadCachedFeed()
    }

    // MARK: - Setup / Availability

    func setup() async {
        do {
            let status = try await container.accountStatus()
            await MainActor.run {
                self.isAvailable = (status == .available)
                if !self.isAvailable {
                    self.lastErrorMessage = "iCloud account: \(self.statusLabel(status))"
                }
            }
            if status == .available {
                await registerOrUpdateProfile()
                await refreshFeed()
            }
        } catch {
            print("[CloudKit] accountStatus failed: \(error.localizedDescription)")
            await MainActor.run {
                self.isAvailable = false
                self.lastErrorMessage = error.localizedDescription
            }
        }
    }

    private func statusLabel(_ s: CKAccountStatus) -> String {
        switch s {
        case .available: return "available"
        case .noAccount: return "noAccount"
        case .restricted: return "restricted"
        case .couldNotDetermine: return "couldNotDetermine"
        case .temporarilyUnavailable: return "temporarilyUnavailable"
        @unknown default: return "unknown"
        }
    }

    // MARK: - Eigenes Profil registrieren / aktualisieren

    private func registerOrUpdateProfile() async {
        let profile = ownProfile()
        let recordID = CKRecord.ID(recordName: "profile_\(profile.code)")
        let record = CKRecord(recordType: CKType.profile, recordID: recordID)
        record[CKField.code]         = profile.code as CKRecordValue
        record[CKField.displayName]  = profile.displayName as CKRecordValue
        record[CKField.avatarPreset] = profile.avatarPreset as CKRecordValue
        record[CKField.lastSeen]     = Date() as CKRecordValue

        do {
            // .changedKeys + saveAndDeletePolicy = .changedKeys: Update wenn da, sonst create
            let op = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
            op.savePolicy = .changedKeys
            try await runModifyOperation(op)
            print("[CloudKit] profile registered/updated: \(profile.code)")
        } catch {
            print("[CloudKit] profile save failed: \(error.localizedDescription)")
        }
    }

    private func ownProfile() -> FriendProfile {
        let settings = UserSettings.shared
        let name = settings.effectiveProfileName(fallbackName: UIDevice.current.name)
        return FriendProfile(
            code: myFriendCode,
            displayName: name,
            avatarPreset: settings.avatarPreset.rawValue
        )
    }

    // MARK: - Friend hinzufügen

    func addFriend(code: String) async throws {
        let normalized = code.uppercased().filter { $0.isLetter || $0.isNumber || $0 == "-" }
        guard normalized != myFriendCode else { throw CloudKitError.cannotAddSelf }
        guard !friends.contains(where: { $0.code == normalized }) else {
            throw CloudKitError.alreadyFriend
        }
        guard isAvailable else { throw CloudKitError.iCloudUnavailable }

        // Profil-Lookup über Code-Query
        let predicate = NSPredicate(format: "%K == %@", CKField.code, normalized)
        let query = CKQuery(recordType: CKType.profile, predicate: predicate)

        let records: [CKRecord] = try await runQuery(query, limit: 1)

        guard let r = records.first else {
            throw CloudKitError.friendNotFound
        }

        let displayName  = (r[CKField.displayName] as? String) ?? "Friend"
        let avatarPreset = (r[CKField.avatarPreset] as? String) ?? ProfileAvatarPreset.person.rawValue
        let profile = FriendProfile(code: normalized, displayName: displayName, avatarPreset: avatarPreset)

        await MainActor.run {
            self.friends.append(profile)
            self.persistFriends()
        }
        await refreshFeed()
    }

    func removeFriend(code: String) {
        friends.removeAll { $0.code == code }
        persistFriends()
        // Aktivitäten dieses Freunds aus Feed entfernen
        feed.removeAll { $0.friendCode == code }
        persistFeed()
    }

    // MARK: - Feed laden

    func refreshFeed() async {
        guard isAvailable else { return }
        let codes = friends.map(\.code)
        guard !codes.isEmpty else {
            await MainActor.run {
                self.feed = []
                self.persistFeed()
            }
            return
        }

        await MainActor.run { self.isLoading = true }
        defer { Task { @MainActor in self.isLoading = false } }

        // Zeitfenster: letzte 14 Tage
        let since = Date().addingTimeInterval(-14 * 24 * 3600)
        let predicate = NSPredicate(
            format: "%K IN %@ AND %K >= %@",
            CKField.code, codes, CKField.timestamp, since as NSDate
        )
        let query = CKQuery(recordType: CKType.activity, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: CKField.timestamp, ascending: false)]

        do {
            let records = try await runQuery(query, limit: 100)
            let lastRead = (UserDefaults.standard.object(forKey: lastReadKey) as? Date) ?? .distantPast
            var activities = records.compactMap { r -> FriendActivity? in
                guard let activityID = r[CKField.activityID] as? String,
                      let code = r[CKField.code] as? String,
                      let typeRaw = r[CKField.eventType] as? String,
                      let type = FriendActivityType(rawValue: typeRaw),
                      let title = r[CKField.eventTitle] as? String,
                      let timestamp = r[CKField.timestamp] as? Date
                else { return nil }
                let detail = (r[CKField.eventDetail] as? String) ?? ""
                let workoutTypeRaw = r[CKField.workoutType] as? String
                // Profil-Daten für Anzeige aus lokaler Friend-Liste ergänzen
                let friend = friends.first(where: { $0.code == code })
                return FriendActivity(
                    id: activityID,
                    friendCode: code,
                    displayName: friend?.displayName ?? code,
                    avatarPreset: friend?.avatarPreset ?? ProfileAvatarPreset.person.rawValue,
                    eventType: type,
                    eventTitle: title,
                    eventDetail: detail,
                    workoutTypeRaw: workoutTypeRaw,
                    timestamp: timestamp,
                    isRead: timestamp <= lastRead
                )
            }

            // Reactions zu allen sichtbaren Aktivitäten laden und zuordnen.
            let activityIDs = activities.map(\.id)
            let reactions = await fetchReactions(forActivityIDs: activityIDs)
            let groupedReactions = Dictionary(grouping: reactions, by: \.activityID)
            activities = activities.map { activity in
                var copy = activity
                copy.reactions = (groupedReactions[activity.id] ?? [])
                    .sorted { $0.timestamp < $1.timestamp }
                return copy
            }

            await MainActor.run {
                self.feed = activities
                self.persistFeed()
            }
        } catch {
            print("[CloudKit] refreshFeed failed: \(error.localizedDescription)")
            await MainActor.run {
                self.lastErrorMessage = error.localizedDescription
            }
        }
    }

    private func fetchReactions(forActivityIDs ids: [String]) async -> [CheerReaction] {
        guard !ids.isEmpty else { return [] }
        let predicate = NSPredicate(format: "%K IN %@", CKField.activityID, ids)
        let query = CKQuery(recordType: CKType.reaction, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: CKField.timestamp, ascending: true)]
        do {
            let records = try await runQuery(query, limit: 200)
            return records.compactMap { r in
                guard let reactionID = r[CKField.reactionID] as? String,
                      let activityID = r[CKField.activityID] as? String,
                      let fromCode = r[CKField.fromCode] as? String,
                      let emoji = r[CKField.emoji] as? String,
                      let timestamp = r[CKField.timestamp] as? Date
                else { return nil }
                let fromName = (r[CKField.fromName] as? String) ?? fromCode
                let text = r[CKField.text] as? String
                return CheerReaction(
                    id: reactionID,
                    activityID: activityID,
                    fromCode: fromCode,
                    fromName: fromName,
                    emoji: emoji,
                    text: text,
                    timestamp: timestamp
                )
            }
        } catch {
            print("[CloudKit] fetchReactions failed: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Anfeuerungen senden

    /// Sendet eine Reaktion (Emoji + optional kurzer Text) zu einer
    /// Aktivität. Mehrfaches Aufrufen mit gleicher activityID ersetzt die
    /// vorherige Reaktion desselben Users (1 Reaktion pro User pro Activity).
    func sendCheer(to activityID: String, emoji: String, text: String?) async throws {
        guard isAvailable else { throw CloudKitError.iCloudUnavailable }

        // Optimistisches lokales Update
        let myProfile = ownProfile()
        let trimmedText = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanText: String? = (trimmedText?.isEmpty == false) ? String(trimmedText!.prefix(CheerEmoji.maxTextLength)) : nil
        let reaction = CheerReaction(
            id: "\(myFriendCode)_\(activityID)",
            activityID: activityID,
            fromCode: myFriendCode,
            fromName: myProfile.displayName,
            emoji: emoji,
            text: cleanText,
            timestamp: Date()
        )

        await MainActor.run {
            self.feed = self.feed.map { activity in
                guard activity.id == activityID else { return activity }
                var copy = activity
                copy.reactions.removeAll { $0.fromCode == self.myFriendCode }
                copy.reactions.append(reaction)
                copy.reactions.sort { $0.timestamp < $1.timestamp }
                return copy
            }
            self.persistFeed()
        }

        // Persistieren in CloudKit. Record-ID enthält myCode+activityID →
        // wenn wir nochmal reagieren, wird derselbe Record überschrieben.
        let recordID = CKRecord.ID(recordName: "reaction_\(myFriendCode)_\(activityID)")
        let record = CKRecord(recordType: CKType.reaction, recordID: recordID)
        record[CKField.reactionID] = reaction.id as CKRecordValue
        record[CKField.activityID] = activityID as CKRecordValue
        record[CKField.fromCode]   = myFriendCode as CKRecordValue
        record[CKField.fromName]   = myProfile.displayName as CKRecordValue
        record[CKField.emoji]      = emoji as CKRecordValue
        record[CKField.timestamp]  = reaction.timestamp as CKRecordValue
        if let cleanText {
            record[CKField.text] = cleanText as CKRecordValue
        }

        let op = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
        op.savePolicy = .allKeys
        try await runModifyOperation(op)
    }

    func markAllRead() {
        UserDefaults.standard.set(Date(), forKey: lastReadKey)
        feed = feed.map { var a = $0; a.isRead = true; return a }
        persistFeed()
    }

    // MARK: - Aktivitäten publishen

    func publishWorkoutIfNeeded(_ workout: WorkoutRecord) async {
        guard isAvailable else { return }
        let title = workout.displayName
        let durationMin = Int(workout.duration / 60)
        let distanceKm = workout.distanceMeters / 1000
        let detail: String
        if distanceKm >= 0.1 {
            detail = String(format: "%.1f km · %d min · %d kcal",
                            distanceKm, durationMin, Int(workout.activeCalories))
        } else {
            detail = String(format: "%d min · %d kcal",
                            durationMin, Int(workout.activeCalories))
        }
        await publishActivity(
            id: "wo_\(workout.id.uuidString)",
            type: .workout,
            title: title,
            detail: detail,
            workoutTypeRaw: workout.workoutType.rawValue,
            timestamp: workout.startDate
        )
    }

    func publishAchievement(_ achievement: Achievement) async {
        guard isAvailable else { return }
        await publishActivity(
            id: "ach_\(achievement.rawValue)",
            type: .achievement,
            title: achievement.displayName,
            detail: achievement.description,
            workoutTypeRaw: nil,
            timestamp: Date()
        )
    }

    private func publishActivity(id: String,
                                 type: FriendActivityType,
                                 title: String,
                                 detail: String,
                                 workoutTypeRaw: String?,
                                 timestamp: Date) async {
        let recordID = CKRecord.ID(recordName: "act_\(myFriendCode)_\(id)")
        let record = CKRecord(recordType: CKType.activity, recordID: recordID)
        record[CKField.activityID]  = id as CKRecordValue
        record[CKField.code]        = myFriendCode as CKRecordValue
        record[CKField.eventType]   = type.rawValue as CKRecordValue
        record[CKField.eventTitle]  = title as CKRecordValue
        record[CKField.eventDetail] = detail as CKRecordValue
        record[CKField.timestamp]   = timestamp as CKRecordValue
        if let raw = workoutTypeRaw {
            record[CKField.workoutType] = raw as CKRecordValue
        }

        let op = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
        op.savePolicy = .allKeys     // Überschreibt vorhandenes Record (Idempotenz)
        do {
            try await runModifyOperation(op)
            print("[CloudKit] published \(type.rawValue): \(title)")
        } catch {
            print("[CloudKit] publish \(type.rawValue) failed: \(error.localizedDescription)")
        }
    }

    // MARK: - CKQueryOperation als async

    private func runQuery(_ query: CKQuery, limit: Int) async throws -> [CKRecord] {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[CKRecord], Error>) in
            var results: [CKRecord] = []
            let op = CKQueryOperation(query: query)
            op.resultsLimit = limit
            op.recordMatchedBlock = { _, result in
                if case .success(let r) = result {
                    results.append(r)
                }
            }
            op.queryResultBlock = { result in
                switch result {
                case .success: cont.resume(returning: results)
                case .failure(let err): cont.resume(throwing: err)
                }
            }
            publicDB.add(op)
        }
    }

    private func runModifyOperation(_ op: CKModifyRecordsOperation) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            op.modifyRecordsResultBlock = { result in
                switch result {
                case .success: cont.resume()
                case .failure(let err): cont.resume(throwing: err)
                }
            }
            publicDB.add(op)
        }
    }

    // MARK: - Persistenz

    private func persistFriends() {
        if let data = try? JSONEncoder().encode(friends) {
            UserDefaults.standard.set(data, forKey: friendsKey)
        }
    }

    private func persistFeed() {
        if let data = try? JSONEncoder().encode(feed) {
            UserDefaults.standard.set(data, forKey: feedKey)
        }
    }

    private func loadCachedFriends() -> [FriendProfile] {
        guard let data = UserDefaults.standard.data(forKey: friendsKey),
              let decoded = try? JSONDecoder().decode([FriendProfile].self, from: data) else {
            return []
        }
        return decoded
    }

    private func loadCachedFeed() -> [FriendActivity] {
        guard let data = UserDefaults.standard.data(forKey: feedKey),
              let decoded = try? JSONDecoder().decode([FriendActivity].self, from: data) else {
            return []
        }
        return decoded
    }

    // MARK: - Code-Generator

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
