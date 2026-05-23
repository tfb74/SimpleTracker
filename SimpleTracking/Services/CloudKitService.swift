import Foundation
import UIKit
import CloudKit

// MARK: - Models

struct FriendProfile: Identifiable, Codable, Hashable {
    var id: String { code }
    let code: String
    var displayName: String
    var avatarPreset: String

    var avatarPresetEnum: ProfileAvatarPreset {
        ProfileAvatarPreset(rawValue: avatarPreset) ?? .person
    }

    /// UI-tauglicher Name: filtert „weak default" Werte wie „iPhone" oder
    /// „iPad" raus und ersetzt sie durch „Freund <Code>". So sieht der
    /// Friends-Tab nie generische Device-Default-Namen.
    var presentableName: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, !UserSettings.isWeakDefaultName(trimmed) {
            return trimmed
        }
        return lf("Freund %@", code)
    }
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

    /// Wie bei FriendProfile: ersetzt schwache Default-Namen für die UI.
    var presentableName: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, !UserSettings.isWeakDefaultName(trimmed) {
            return trimmed
        }
        return lf("Freund %@", friendCode)
    }
}

enum FriendActivityType: String, Codable {
    case workout
    case achievement
    case meal       // Stufe 3: optional opt-in Meal-Sharing
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

/// Direktnachricht zwischen zwei Friends.
struct DirectMessage: Codable, Identifiable, Hashable {
    let id: String              // UUID
    let fromCode: String
    let fromName: String        // denormalisiert für Offline-Anzeige
    let toCode: String          // Empfänger-Code (= meinFriendCode für eingehende)
    let text: String
    let timestamp: Date
    var readAt: Date?           // nil = ungelesen

    static let maxTextLength = 500

    /// "Konversations-Partner": für ausgehende Messages der Empfänger, für
    /// eingehende der Sender. Bestimmt unter welchem Thread die Nachricht
    /// in der UI gruppiert wird.
    func peerCode(myCode: String) -> String {
        fromCode == myCode ? toCode : fromCode
    }
}

enum CloudKitError: LocalizedError {
    case friendNotFound
    case alreadyFriend
    case cannotAddSelf
    case iCloudUnavailable

    var errorDescription: String? {
        switch self {
        case .friendNotFound:    return "Kein Nutzer mit diesem Code gefunden. Bitte stelle sicher, dass die andere Person die App mindestens einmal geöffnet hat und in iCloud angemeldet ist."
        case .alreadyFriend:     return "Diese Person ist bereits in deiner Liste."
        case .cannotAddSelf:     return "Du kannst dich nicht selbst hinzufügen."
        case .iCloudUnavailable: return "iCloud ist nicht verfügbar. Bitte melde dich in den Einstellungen an."
        }
    }
}

// MARK: - CloudKit Record Types

private enum CKType {
    static let profile           = "STUserProfile"
    static let activity          = "STActivity"
    static let reaction          = "STReaction"
    /// Reciprocal-Share-Invite: B hat A hinzugefügt und will ihre Aktivitäten
    /// ebenfalls mit A teilen → schreibt einen Record, den A's App beim Refresh
    /// einsammelt und B automatisch zur eigenen Friends-Liste hinzufügt.
    static let shareInvite       = "STFriendShareInvite"
    /// Direktnachricht zwischen zwei Freunden (1:1).
    static let message           = "STMessage"
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
    // ShareInvite (zusätzlich zu fromCode/fromName/avatarPreset/timestamp)
    static let targetCode     = "targetCode"
    // Message (zusätzlich zu fromCode/fromName/targetCode/text/timestamp)
    // reactionID-Feld wird als message-id wiederverwendet
    static let readAt         = "readAt"
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

    /// True wenn seit dem letzten Friends-Tab-Öffnen ein neuer Feed-Eintrag
    /// oder eine Reaktion auf eine eigene Activity per Push reinkam. Wird
    /// vom UI als „roter Punkt" am Friends-Tab visualisiert.
    var hasUnreadFeed = false

    /// Direkt-Konversationen (Stufe 3). Key: code des Gesprächspartners.
    private(set) var conversations: [String: [DirectMessage]] = [:]
    var totalUnreadMessages: Int {
        conversations.values.flatMap { $0 }.filter {
            $0.toCode == myFriendCode && $0.readAt == nil
        }.count
    }

    var unreadCount: Int { feed.filter { !$0.isRead }.count }

    private let friendsKey = "ck.friends.v1"
    private let codeKey    = "ck.myCode.v1"
    private let feedKey    = "ck.feed.v1"
    private let lastReadKey = "ck.feed.lastReadAt.v1"
    private let conversationsKey = "ck.conversations.v1"

    private let container: CKContainer
    private var publicDB: CKDatabase { container.publicCloudDatabase }

    private init() {
        // Container muss exakt mit der Entitlement-ID übereinstimmen.
        self.container = CKContainer(identifier: "iCloud.de.baumannheim.SimpleTracking")
        self.myFriendCode = generateOrLoadCode()
        self.friends = loadCachedFriends()
        self.feed    = loadCachedFeed()
        self.conversations = loadCachedConversations()
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
                // Erst Invites einsammeln (kann neue Friends hinzufügen),
                // dann Feed laden – damit deren Aktivitäten direkt mitkommen.
                await processIncomingShareInvites()
                await refreshFeed()
                // Subscriptions setzen: Push-Notifications bei neuen Activities
                // von Freunden und neuen Reactions auf eigene Activities.
                await refreshSubscriptions()
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

    /// Forciert eine erneute Profile-Schreibung mit aktuellen Settings-Werten.
    /// Wird z.B. nach Game-Center-Login aufgerufen wenn sich der displayName
    /// geändert hat → andere Friends sehen beim nächsten refreshFeed den
    /// neuen Namen.
    func republishProfile() async {
        guard isAvailable else { return }
        await registerOrUpdateProfile()
    }

    /// Liest die aktuellen STUserProfile-Records aller Friends frisch aus
    /// CloudKit nach. Wird beim Friends-Tab-Öffnen aufgerufen damit
    /// nachträgliche Namens- und Avatar-Änderungen automatisch sichtbar
    /// werden — ohne dass der User den Freund entfernen + neu hinzufügen muss.
    func refreshFriendProfiles() async {
        guard isAvailable else { return }
        let codes = friends.map(\.code)
        guard !codes.isEmpty else { return }

        let predicate = NSPredicate(format: "%K IN %@", CKField.code, codes)
        let query = CKQuery(recordType: CKType.profile, predicate: predicate)
        guard let records = try? await runQuery(query, limit: 100), !records.isEmpty else {
            return
        }

        var updates: [String: (name: String, avatar: String)] = [:]
        for r in records {
            guard let code = r[CKField.code] as? String else { continue }
            let name = (r[CKField.displayName] as? String) ?? ""
            let avatar = (r[CKField.avatarPreset] as? String) ?? ProfileAvatarPreset.person.rawValue
            updates[code] = (name, avatar)
        }

        let updatesFinal = updates
        await MainActor.run {
            var changed = false
            self.friends = self.friends.map { f in
                guard let u = updatesFinal[f.code] else { return f }
                if f.displayName != u.name || f.avatarPreset != u.avatar {
                    changed = true
                    return FriendProfile(code: f.code, displayName: u.name, avatarPreset: u.avatar)
                }
                return f
            }
            if changed {
                self.persistFriends()
                // Cached Feed-Activities haben displayName denormalisiert —
                // wir lassen die wie sie sind und sie kriegen den frischen
                // Namen beim nächsten refreshFeed über den FriendActivity-Build.
            }
        }
    }

    /// Wird beim App-Start aufgerufen. Falls noch nie erfolgreich registriert
    /// (z.B. weil das CloudKit-Schema vorher fehlte), markieren wir das in
    /// UserDefaults und versuchen es beim nächsten Start nochmal.
    private static let profileRegisteredKey = "ck.profileRegisteredInProduction.v1"
    private(set) var profileRegistered = UserDefaults.standard.bool(forKey: profileRegisteredKey)

    private func registerOrUpdateProfile() async {
        let profile = ownProfile()
        let recordID = CKRecord.ID(recordName: "profile_\(profile.code)")
        let record = CKRecord(recordType: CKType.profile, recordID: recordID)
        record[CKField.code]         = profile.code as CKRecordValue
        record[CKField.displayName]  = profile.displayName as CKRecordValue
        record[CKField.avatarPreset] = profile.avatarPreset as CKRecordValue
        // WICHTIG: lastSeen ist in CloudKit Production als STRING typisiert
        // (Schema-Bug beim initialen Anlegen — und Felder können in Production
        // nicht mehr gelöscht/umtypisiert werden). Daher Date als ISO-String
        // serialisieren, nicht als Date()-CKRecordValue, sonst USER_ERROR/OTHER.
        record[CKField.lastSeen]     = ISO8601DateFormatter().string(from: Date()) as CKRecordValue

        do {
            // .allKeys statt .changedKeys: bei .changedKeys lehnt CloudKit
            // Public-DB-Writes ab, wenn der Record-Name noch nie existiert hat
            // (USER_ERROR/OTHER, 150ms). .allKeys macht ein sauberes Upsert
            // unabhängig vom bisherigen Server-Stand.
            let op = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
            op.savePolicy = .allKeys
            try await runModifyOperation(op)
            print("[CloudKit] profile registered/updated: \(profile.code)")
            await MainActor.run {
                self.profileRegistered = true
                UserDefaults.standard.set(true, forKey: Self.profileRegisteredKey)
                self.lastErrorMessage = nil
            }
            return
        } catch {
            print("[CloudKit] profile save failed: \(error.localizedDescription)")
            await MainActor.run {
                self.lastErrorMessage = "Profil-Registrierung fehlgeschlagen: \(error.localizedDescription)"
            }
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

    // MARK: - Reciprocal Share (B-lite)

    /// B ruft das auf, nachdem B den Code von A eingegeben hat und auf
    /// die Rückfrage „Willst du dich auch mit X teilen?" mit Ja antwortet.
    /// Schreibt einen Invite-Record in CloudKit, den A's App beim nächsten
    /// Refresh aufsammelt und B automatisch zu A's Freunden hinzufügt.
    func offerReciprocalShare(toCode targetCode: String) async throws {
        guard isAvailable else { throw CloudKitError.iCloudUnavailable }
        let normalizedTarget = targetCode.uppercased()
        guard normalizedTarget != myFriendCode else { return }

        let me = ownProfile()
        // Deterministische Record-ID — Mehrfach-Klick erzeugt keine Duplikate.
        let recordID = CKRecord.ID(recordName: "shareInvite_\(me.code)_to_\(normalizedTarget)")
        let record = CKRecord(recordType: CKType.shareInvite, recordID: recordID)
        record[CKField.targetCode]    = normalizedTarget as CKRecordValue
        record[CKField.fromCode]      = me.code as CKRecordValue
        record[CKField.fromName]      = me.displayName as CKRecordValue
        record[CKField.avatarPreset]  = me.avatarPreset as CKRecordValue
        record[CKField.timestamp]     = Date() as CKRecordValue

        let op = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
        op.savePolicy = .allKeys
        try await runModifyOperation(op)
    }

    /// Holt eingehende Reciprocal-Share-Invites (für meinen Code) ab, fügt die
    /// Sender automatisch zu meiner Friends-Liste hinzu und löscht die Records.
    /// Idempotent — wird beim App-Start und beim Pull-to-Refresh aufgerufen.
    func processIncomingShareInvites() async {
        guard isAvailable, !myFriendCode.isEmpty else { return }

        let predicate = NSPredicate(format: "%K == %@", CKField.targetCode, myFriendCode)
        let query = CKQuery(recordType: CKType.shareInvite, predicate: predicate)

        do {
            let records = try await runQuery(query, limit: 50)
            guard !records.isEmpty else { return }

            var added: [FriendProfile] = []
            var idsToDelete: [CKRecord.ID] = []
            for r in records {
                idsToDelete.append(r.recordID)
                guard let senderCode = r[CKField.fromCode] as? String else { continue }
                let normalized = senderCode.uppercased()
                guard normalized != myFriendCode,
                      !friends.contains(where: { $0.code == normalized }),
                      !added.contains(where: { $0.code == normalized })
                else { continue }
                let name   = (r[CKField.fromName] as? String) ?? "Friend"
                let preset = (r[CKField.avatarPreset] as? String) ?? ProfileAvatarPreset.person.rawValue
                added.append(FriendProfile(code: normalized, displayName: name, avatarPreset: preset))
            }

            // Swift-6-Concurrency: immutable Kopien, damit die Closure den
            // Wert nicht per Referenz auf eine 'var' captured.
            let addedFinal = added
            let idsFinal = idsToDelete

            if !addedFinal.isEmpty {
                await MainActor.run {
                    self.friends.append(contentsOf: addedFinal)
                    self.persistFriends()
                }
            }

            // Records wegräumen — Invite ist konsumiert.
            if !idsFinal.isEmpty {
                let op = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: idsFinal)
                try? await runModifyOperation(op)
            }

            if !addedFinal.isEmpty {
                await refreshFeed()
            }
        } catch {
            print("[CloudKit] processIncomingShareInvites failed: \(error.localizedDescription)")
        }
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

            let feedFinal = activities
            await MainActor.run {
                self.feed = feedFinal
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

    // MARK: - Direkt-Nachrichten (Stufe 3)

    /// Holt alle Direkt-Nachrichten (eingehend + ausgehend) und MERGED sie
    /// in die lokale Konversations-Map. Lokale Messages werden NICHT
    /// überschrieben oder gelöscht, auch wenn CloudKit weniger zurückgibt
    /// — wichtig falls Schema fehlt oder Netzwerk-Fehler. Damit überleben
    /// vom User gesendete Messages auch dann, wenn CloudKit-Sync scheitert.
    func refreshMessages() async {
        guard isAvailable, !myFriendCode.isEmpty else { return }

        // Predicate: alle Messages wo ICH Sender oder Empfänger bin.
        // CloudKit erlaubt kein OR im Predicate ohne Subqueries, daher 2 Queries.
        let inboundPred  = NSPredicate(format: "%K == %@", CKField.targetCode, myFriendCode)
        let outboundPred = NSPredicate(format: "%K == %@", CKField.fromCode, myFriendCode)

        let inboundQuery  = CKQuery(recordType: CKType.message, predicate: inboundPred)
        let outboundQuery = CKQuery(recordType: CKType.message, predicate: outboundPred)
        inboundQuery.sortDescriptors  = [NSSortDescriptor(key: CKField.timestamp, ascending: true)]
        outboundQuery.sortDescriptors = [NSSortDescriptor(key: CKField.timestamp, ascending: true)]

        var hadFetchError = false
        var fetched: [CKRecord] = []
        do {
            let inbound = try await runQuery(inboundQuery, limit: 500)
            fetched.append(contentsOf: inbound)
        } catch {
            hadFetchError = true
            print("[CloudKit] refreshMessages inbound failed: \(error.localizedDescription)")
        }
        do {
            let outbound = try await runQuery(outboundQuery, limit: 500)
            fetched.append(contentsOf: outbound)
        } catch {
            hadFetchError = true
            print("[CloudKit] refreshMessages outbound failed: \(error.localizedDescription)")
        }

        // Wenn beide Queries fehlschlugen → behalte lokalen Cache komplett.
        // Wenn mindestens eine erfolgreich war → merge.
        guard !fetched.isEmpty || !hadFetchError else {
            print("[CloudKit] refreshMessages: keeping local cache (CloudKit error)")
            return
        }

        // Records → DirectMessages
        var serverMessages: [String: DirectMessage] = [:]
        for r in fetched {
            guard let id = r[CKField.reactionID] as? String,
                  let fromCode = r[CKField.fromCode] as? String,
                  let toCode = r[CKField.targetCode] as? String,
                  let text = r[CKField.text] as? String,
                  let timestamp = r[CKField.timestamp] as? Date
            else { continue }
            let fromName = (r[CKField.fromName] as? String) ?? fromCode
            let readAt = r[CKField.readAt] as? Date
            serverMessages[id] = DirectMessage(
                id: id, fromCode: fromCode, fromName: fromName,
                toCode: toCode, text: text, timestamp: timestamp, readAt: readAt
            )
        }

        // Merge: für jede lokale Konversation, ergänze Server-Messages.
        // Lokale Messages die der Server (noch) nicht hat bleiben drin —
        // wichtig wenn Schema fehlt oder die Message frisch optimistisch
        // eingefügt wurde aber Sync noch nicht durch ist.
        let serverFinal = serverMessages
        await MainActor.run {
            var merged = self.conversations  // lokal-zuerst

            // Sammle alle lokalen Message-IDs
            var localIDs = Set<String>()
            for msgs in merged.values { for m in msgs { localIDs.insert(m.id) } }

            // Füge Server-Messages hinzu die lokal noch nicht da sind
            for (_, sm) in serverFinal where !localIDs.contains(sm.id) {
                let peer = sm.peerCode(myCode: self.myFriendCode)
                merged[peer, default: []].append(sm)
            }

            // Für Server-Messages die lokal AUCH da sind, aktualisiere readAt
            // (Empfänger hat gelesen → ausgehende lokale Message kriegt Häkchen)
            for (peer, msgs) in merged {
                merged[peer] = msgs.map { local in
                    if let server = serverFinal[local.id], server.readAt != nil, local.readAt == nil {
                        var copy = local; copy.readAt = server.readAt; return copy
                    }
                    return local
                }.sorted { $0.timestamp < $1.timestamp }
            }

            self.conversations = merged
            self.persistConversations()
        }
    }

    /// Schickt eine Direktnachricht an einen Freund. Lokale Persistenz
    /// passiert sofort, CloudKit-Upload läuft async und bricht die Message
    /// nicht ab wenn das Schema fehlt — die Message bleibt lokal sichtbar.
    func sendMessage(to peerCode: String, text: String) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let clean = String(trimmed.prefix(DirectMessage.maxTextLength))

        let me = ownProfile()
        let id = UUID().uuidString
        let msg = DirectMessage(
            id: id, fromCode: myFriendCode, fromName: me.displayName,
            toCode: peerCode, text: clean, timestamp: Date(), readAt: nil
        )

        // Optimistisches Update + PERSIST sofort, damit Message auch nach
        // App-Restart da bleibt, selbst wenn CloudKit-Save scheitert.
        await MainActor.run {
            self.conversations[peerCode, default: []].append(msg)
            self.conversations[peerCode]?.sort { $0.timestamp < $1.timestamp }
            self.persistConversations()
        }

        guard isAvailable else { throw CloudKitError.iCloudUnavailable }

        let recordID = CKRecord.ID(recordName: "msg_\(id)")
        let record = CKRecord(recordType: CKType.message, recordID: recordID)
        record[CKField.reactionID] = id as CKRecordValue
        record[CKField.fromCode]   = myFriendCode as CKRecordValue
        record[CKField.fromName]   = me.displayName as CKRecordValue
        record[CKField.targetCode] = peerCode as CKRecordValue
        record[CKField.text]       = clean as CKRecordValue
        record[CKField.timestamp]  = msg.timestamp as CKRecordValue

        let op = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
        op.savePolicy = .allKeys
        try await runModifyOperation(op)
    }

    /// Markiert alle eingehenden Nachrichten von `peerCode` als gelesen.
    func markMessagesRead(from peerCode: String) async {
        guard isAvailable, let msgs = conversations[peerCode] else { return }
        let unread = msgs.filter { $0.toCode == myFriendCode && $0.readAt == nil }
        guard !unread.isEmpty else { return }
        let now = Date()

        // Lokal sofort updaten
        await MainActor.run {
            self.conversations[peerCode] = msgs.map { m in
                guard m.toCode == self.myFriendCode, m.readAt == nil else { return m }
                var copy = m; copy.readAt = now; return copy
            }
            self.persistConversations()
        }

        // In CloudKit auch markieren — fire-and-forget
        let records: [CKRecord] = unread.map { m in
            let r = CKRecord(recordType: CKType.message,
                             recordID: CKRecord.ID(recordName: "msg_\(m.id)"))
            r[CKField.reactionID] = m.id as CKRecordValue
            r[CKField.fromCode]   = m.fromCode as CKRecordValue
            r[CKField.fromName]   = m.fromName as CKRecordValue
            r[CKField.targetCode] = m.toCode as CKRecordValue
            r[CKField.text]       = m.text as CKRecordValue
            r[CKField.timestamp]  = m.timestamp as CKRecordValue
            r[CKField.readAt]     = now as CKRecordValue
            return r
        }
        let op = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
        op.savePolicy = .changedKeys  // nur readAt updaten — Rest soll alt bleiben
        try? await runModifyOperation(op)
    }

    func conversation(with peerCode: String) -> [DirectMessage] {
        conversations[peerCode] ?? []
    }

    // MARK: - Push-Subscriptions (Live-Interaktion)

    /// IDs der CloudKit-Subscriptions, die wir verwalten. Format: stabile
    /// Strings damit wir sie wiederfinden und überschreiben können.
    private enum SubscriptionID {
        /// Push wenn EIN FREUND eine neue Activity postet.
        static let friendActivity = "sub.friendActivity"
        /// Push wenn JEMAND auf eine EIGENE Activity reagiert.
        static let reactionsOnMine = "sub.reactionsOnMine"
        /// Push wenn JEMAND mir eine Direktnachricht schickt (Stufe 3).
        static let messagesToMe = "sub.messagesToMe"
    }

    /// Aktualisiert alle Push-Subscriptions. Wird beim Setup und nach jeder
    /// Friend-Änderung aufgerufen (damit neue Freunde auch berücksichtigt sind).
    func refreshSubscriptions() async {
        guard isAvailable, !myFriendCode.isEmpty else { return }

        // 1. Subscription: neue Activities von meinen Freunden
        let friendCodes = friends.map(\.code)
        if friendCodes.isEmpty {
            // Keine Friends → Subscription entfernen falls vorhanden
            await deleteSubscription(SubscriptionID.friendActivity)
        } else {
            let predicate = NSPredicate(format: "%K IN %@", CKField.code, friendCodes)
            let sub = CKQuerySubscription(
                recordType: CKType.activity,
                predicate: predicate,
                subscriptionID: SubscriptionID.friendActivity,
                options: [.firesOnRecordCreation]
            )
            let info = CKSubscription.NotificationInfo()
            info.titleLocalizationKey = "STPushFriendActivityTitle"
            info.alertLocalizationKey = "STPushFriendActivityBody"
            info.alertLocalizationArgs = [CKField.displayName, CKField.eventTitle]
            info.shouldBadge = true
            info.shouldSendContentAvailable = true
            info.soundName = "default"
            sub.notificationInfo = info
            await saveSubscription(sub)
        }

        // 2. Subscription: Reactions auf meine Activities
        let myActivityPredicate = NSPredicate(format: "%K == %@", CKField.code, myFriendCode)
        _ = myActivityPredicate  // Vorgemerkt für Activity-Filter

        // Reaction-Subscription kann nicht direkt nach "activityID IN myActivities"
        // filtern (CloudKit-Limit). Stattdessen: subscribe auf alle Reactions
        // wo fromCode != myCode UND filter clientseitig nach Empfang.
        let reactionPred = NSPredicate(format: "%K != %@", CKField.fromCode, myFriendCode)
        let reactionSub = CKQuerySubscription(
            recordType: CKType.reaction,
            predicate: reactionPred,
            subscriptionID: SubscriptionID.reactionsOnMine,
            options: [.firesOnRecordCreation]
        )
        let reactionInfo = CKSubscription.NotificationInfo()
        reactionInfo.titleLocalizationKey = "STPushReactionTitle"
        reactionInfo.alertLocalizationKey = "STPushReactionBody"
        reactionInfo.alertLocalizationArgs = [CKField.fromName, CKField.emoji]
        reactionInfo.shouldBadge = true
        reactionInfo.shouldSendContentAvailable = true
        reactionInfo.soundName = "default"
        // Activity-ID mitschicken damit die App direkt zur richtigen
        // Konversation springen kann.
        reactionInfo.desiredKeys = [
            CKField.activityID, CKField.fromCode, CKField.fromName, CKField.emoji
        ]
        reactionSub.notificationInfo = reactionInfo
        await saveSubscription(reactionSub)

        // 3. Subscription: Direktnachrichten (Schema wird in Stufe 3 angelegt)
        await refreshMessageSubscription()
    }

    private func refreshMessageSubscription() async {
        guard isAvailable, !myFriendCode.isEmpty else { return }
        let pred = NSPredicate(format: "%K == %@", CKField.targetCode, myFriendCode)
        let sub = CKQuerySubscription(
            recordType: CKType.message,
            predicate: pred,
            subscriptionID: SubscriptionID.messagesToMe,
            options: [.firesOnRecordCreation]
        )
        let info = CKSubscription.NotificationInfo()
        info.titleLocalizationKey = "STPushMessageTitle"
        info.alertLocalizationKey = "STPushMessageBody"
        info.alertLocalizationArgs = [CKField.fromName, CKField.text]
        info.shouldBadge = true
        info.shouldSendContentAvailable = true
        info.soundName = "default"
        info.desiredKeys = [CKField.fromCode, CKField.fromName, CKField.text]
        sub.notificationInfo = info
        await saveSubscription(sub)
    }

    private func saveSubscription(_ sub: CKSubscription) async {
        do {
            // Erst löschen (idempotent), dann neu speichern — Predicate könnte
            // sich geändert haben (neue Friends).
            _ = try? await publicDB.deleteSubscription(withID: sub.subscriptionID)
            _ = try await publicDB.save(sub)
            print("[CloudKit] subscription saved: \(sub.subscriptionID)")
        } catch {
            print("[CloudKit] subscription save failed (\(sub.subscriptionID)): \(error.localizedDescription)")
        }
    }

    /// Wird vom AppDelegate für JEDE eingehende Remote-Notification gerufen.
    /// Triggert refreshs damit die UI sofort die neuen Daten zeigt, sobald
    /// der Nutzer die App öffnet (oder schon im Vordergrund ist).
    @MainActor
    func handleIncomingPush(userInfo: [AnyHashable: Any]) async {
        guard let ckNotification = CKNotification(fromRemoteNotificationDictionary: userInfo) else {
            print("[CloudKit] received non-CK push, ignoring")
            return
        }

        switch ckNotification.subscriptionID {
        case SubscriptionID.friendActivity:
            print("[CloudKit] push: friend activity")
            await refreshFeed()
            await MainActor.run {
                self.hasUnreadFeed = true
            }
        case SubscriptionID.reactionsOnMine:
            print("[CloudKit] push: reaction on my activity")
            await refreshFeed()
            await MainActor.run {
                self.hasUnreadFeed = true
            }
        case SubscriptionID.messagesToMe:
            print("[CloudKit] push: new direct message")
            await refreshMessages()
        default:
            print("[CloudKit] unknown subscription push: \(ckNotification.subscriptionID ?? "nil")")
        }
    }

    private func deleteSubscription(_ id: String) async {
        do {
            try await publicDB.deleteSubscription(withID: id)
            print("[CloudKit] subscription deleted: \(id)")
        } catch {
            // Ignore — wahrscheinlich war keine da
        }
    }

    // MARK: - Anfeuerungen senden

    /// Sendet eine Reaktion (Emoji + optional kurzer Text) zu einer Aktivität.
    /// Mehrere Reaktionen pro User pro Activity sind erlaubt — jede bekommt
    /// eine eigene UUID, sodass echte Konversationen entstehen können.
    func sendCheer(to activityID: String, emoji: String, text: String?) async throws {
        guard isAvailable else { throw CloudKitError.iCloudUnavailable }

        // Optimistisches lokales Update
        let myProfile = ownProfile()
        let trimmedText = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanText: String? = (trimmedText?.isEmpty == false) ? String(trimmedText!.prefix(CheerEmoji.maxTextLength)) : nil
        let reactionID = UUID().uuidString
        let reaction = CheerReaction(
            id: reactionID,
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
                // KEINE Bereinigung mehr von eigenen Reaktionen — Threading!
                copy.reactions.append(reaction)
                copy.reactions.sort { $0.timestamp < $1.timestamp }
                return copy
            }
            self.persistFeed()
        }

        // RecordName mit UUID → jeder Cheer ist sein eigener Record.
        let recordID = CKRecord.ID(recordName: "reaction_\(reactionID)")
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

    /// Löscht eine eigene Reaktion (für Korrektur-Möglichkeit).
    func deleteCheer(reactionID: String, activityID: String) async {
        await MainActor.run {
            self.feed = self.feed.map { activity in
                guard activity.id == activityID else { return activity }
                var copy = activity
                copy.reactions.removeAll { $0.id == reactionID && $0.fromCode == self.myFriendCode }
                return copy
            }
            self.persistFeed()
        }
        let recordID = CKRecord.ID(recordName: "reaction_\(reactionID)")
        let op = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: [recordID])
        try? await runModifyOperation(op)
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

    /// Veröffentlicht eine Mahlzeit als Friend-Activity — NUR wenn der User
    /// für diesen Eintrag das Share-Toggle aktiviert hat. Privacy-by-Default:
    /// ohne Opt-In passiert hier nichts.
    func publishMealIfShared(_ entry: FoodEntry) async {
        guard isAvailable else { return }
        guard entry.sharedWithFriends == true else { return }

        let kcal = Int(entry.resolvedCalories)
        let carbs = Int(entry.resolvedCarbsGrams)
        let detail: String
        if entry.kind == .drink, let ml = entry.portionMilliliters {
            detail = String(format: "%d ml · %d kcal", Int(ml), kcal)
        } else if carbs > 0 {
            detail = String(format: "%d kcal · %d g KH", kcal, carbs)
        } else {
            detail = String(format: "%d kcal", kcal)
        }
        await publishActivity(
            id: "meal_\(entry.id.uuidString)",
            type: .meal,
            title: entry.name,
            detail: detail,
            workoutTypeRaw: nil,
            timestamp: entry.timestamp
        )
    }

    /// Entfernt eine veröffentlichte Meal-Activity (z.B. wenn User
    /// nachträglich „Share" zurückzieht oder den Eintrag löscht).
    func unpublishMeal(_ entry: FoodEntry) async {
        guard isAvailable else { return }
        let recordID = CKRecord.ID(recordName: "act_\(myFriendCode)_meal_\(entry.id.uuidString)")
        let op = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: [recordID])
        try? await runModifyOperation(op)
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

    private func persistConversations() {
        if let data = try? JSONEncoder().encode(conversations) {
            UserDefaults.standard.set(data, forKey: conversationsKey)
        }
    }

    private func loadCachedConversations() -> [String: [DirectMessage]] {
        guard let data = UserDefaults.standard.data(forKey: conversationsKey),
              let decoded = try? JSONDecoder().decode([String: [DirectMessage]].self, from: data) else {
            return [:]
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
