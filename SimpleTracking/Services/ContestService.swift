import Foundation
import UIKit
import CloudKit

// MARK: - CloudKit Schema-Konstanten

private enum CKContestType {
    static let contest     = "STContest"
    static let participant = "STContestParticipant"
    static let progress    = "STContestProgress"
    static let team        = "STTeam"
    static let membership  = "STTeamMembership"
}

private enum CKField {
    // Contest
    static let contestID    = "contestID"
    static let ownerCode    = "ownerCode"
    static let title        = "title"
    static let description  = "contestDescription"
    static let type         = "contestType"
    static let metric       = "metric"
    static let targetValue  = "targetValue"
    static let startDate    = "startDate"
    static let endDate      = "endDate"
    static let scope        = "scope"
    static let teamID       = "teamID"
    static let inviteCode   = "inviteCode"
    static let isActive     = "isActive"
    // Participant
    static let participantID = "participantID"
    static let userCode      = "userCode"
    static let displayName   = "displayName"
    static let avatarPreset  = "avatarPreset"
    static let joinedAt      = "joinedAt"
    static let subTeamID     = "subTeamID"
    // Progress
    static let progressID    = "progressID"
    static let date          = "progressDate"
    static let value         = "value"
    static let cumulative    = "cumulativeValue"
    static let dailyTargetMet = "dailyTargetMet"
    // Team
    static let parentTeamID  = "parentTeamID"
    static let name          = "teamName"
    static let memberCount   = "memberCount"
    static let membershipID  = "membershipID"
    static let isAdmin       = "isAdmin"
}

// MARK: - Service

@Observable
@MainActor
final class ContestService {
    static let shared = ContestService()

    private(set) var contests: [Contest] = []
    private(set) var participantsByContest: [String: [ContestParticipant]] = [:]
    private(set) var progressByContest: [String: [ContestProgress]] = [:]
    private(set) var standingsByContest: [String: [ContestStanding]] = [:]
    private(set) var isLoading = false
    private(set) var lastErrorMessage: String?

    private let container: CKContainer
    private var publicDB: CKDatabase { container.publicCloudDatabase }
    private let cacheKey = "contest.cache.v1"

    private init() {
        self.container = CKContainer(identifier: "iCloud.de.baumannheim.SimpleTracking")
        loadCache()
    }

    // MARK: - Public API

    /// Erstellt einen neuen Contest, schreibt Owner als ersten Teilnehmer.
    @discardableResult
    func createContest(
        title: String,
        description: String?,
        type: ContestType,
        metric: ContestMetric,
        targetValue: Double,
        startDate: Date,
        endDate: Date,
        scope: ContestScope,
        teamID: String?
    ) async throws -> Contest {
        guard endDate > startDate else { throw ContestError.invalidDateRange }
        guard CloudKitService.shared.isAvailable else { throw ContestError.iCloudUnavailable }

        let myCode = CloudKitService.shared.myFriendCode
        let contest = Contest(
            contestID:  UUID().uuidString,
            ownerCode:  myCode,
            title:      title,
            description: description?.isEmpty == false ? description : nil,
            type:       type,
            metric:     metric,
            targetValue: targetValue,
            startDate:  startDate,
            endDate:    endDate,
            scope:      scope,
            teamID:     teamID,
            inviteCode: ContestCodeGenerator.makeInviteCode(),
            isActive:   true
        )
        try await saveContestRecord(contest)

        // Owner direkt als Teilnehmer eintragen
        try await joinAsParticipant(contest: contest)

        contests.append(contest)
        persistCache()
        return contest
    }

    /// Tritt einem Contest via Invite-Code bei.
    @discardableResult
    func joinContest(inviteCode: String, subTeamID: String? = nil) async throws -> Contest {
        guard CloudKitService.shared.isAvailable else { throw ContestError.iCloudUnavailable }

        let normalized = inviteCode.uppercased()
        let predicate = NSPredicate(format: "%K == %@", CKField.inviteCode, normalized)
        let query = CKQuery(recordType: CKContestType.contest, predicate: predicate)
        let records = try await runQuery(query, limit: 1)
        guard let record = records.first, let contest = decodeContest(record) else {
            throw ContestError.contestNotFound
        }
        guard contest.endDate > Date() else { throw ContestError.contestEnded }

        // Schon Teilnehmer?
        let existing = try await fetchParticipants(for: contest.id)
        if existing.contains(where: { $0.userCode == CloudKitService.shared.myFriendCode }) {
            throw ContestError.alreadyJoined
        }

        try await joinAsParticipant(contest: contest, subTeamID: subTeamID)

        if !contests.contains(where: { $0.id == contest.id }) {
            contests.append(contest)
        }
        persistCache()
        return contest
    }

    /// Entfernt eigene Teilnahme (verlässt Contest).
    func leaveContest(_ contest: Contest) async throws {
        guard CloudKitService.shared.isAvailable else { throw ContestError.iCloudUnavailable }
        let myCode = CloudKitService.shared.myFriendCode
        let participants = participantsByContest[contest.id] ?? []
        guard let me = participants.first(where: { $0.userCode == myCode }) else { return }

        let recordID = CKRecord.ID(recordName: "participant_\(me.id)")
        try await publicDB.deleteRecord(withID: recordID)

        contests.removeAll { $0.id == contest.id }
        participantsByContest[contest.id] = nil
        progressByContest[contest.id] = nil
        standingsByContest[contest.id] = nil
        persistCache()
    }

    /// Lädt eigene Contests (alle, in denen ich Teilnehmer bin) plus Daten.
    func refreshAll() async {
        guard CloudKitService.shared.isAvailable else { return }
        isLoading = true
        defer { isLoading = false }

        let myCode = CloudKitService.shared.myFriendCode
        do {
            // Eigene Teilnahmen finden
            let participantPredicate = NSPredicate(format: "%K == %@", CKField.userCode, myCode)
            let participantQuery = CKQuery(recordType: CKContestType.participant, predicate: participantPredicate)
            let participantRecords = try await runQuery(participantQuery, limit: 200)
            let myParticipations = participantRecords.compactMap(decodeParticipant)
            let contestIDs = Array(Set(myParticipations.map(\.contestID)))

            guard !contestIDs.isEmpty else {
                contests = []
                participantsByContest = [:]
                progressByContest = [:]
                standingsByContest = [:]
                persistCache()
                return
            }

            // Contests laden
            let contestPredicate = NSPredicate(format: "%K IN %@", CKField.contestID, contestIDs)
            let contestQuery = CKQuery(recordType: CKContestType.contest, predicate: contestPredicate)
            let contestRecords = try await runQuery(contestQuery, limit: 100)
            let loadedContests = contestRecords.compactMap(decodeContest)
            contests = loadedContests.sorted { $0.endDate > $1.endDate }

            // Pro Contest: Teilnehmer + Progress laden
            for contest in loadedContests {
                let parts = try await fetchParticipants(for: contest.id)
                participantsByContest[contest.id] = parts
                let progress = try await fetchProgress(for: contest.id)
                progressByContest[contest.id] = progress
                standingsByContest[contest.id] = computeStandings(contest: contest, participants: parts, progress: progress)
            }
            persistCache()
            lastErrorMessage = nil
        } catch {
            print("[ContestService] refreshAll failed: \(error.localizedDescription)")
            lastErrorMessage = error.localizedDescription
        }
    }

    /// Schreibt einen Progress-Record (oder aktualisiert vorhandenen) für heute.
    func recordProgress(
        contestID: String,
        value: Double,
        cumulativeValue: Double,
        dailyTargetMet: Bool
    ) async {
        guard CloudKitService.shared.isAvailable else { return }
        let myCode = CloudKitService.shared.myFriendCode
        let today = Calendar.current.startOfDay(for: Date())
        let recordID = CKRecord.ID(recordName: "progress_\(contestID)_\(myCode)_\(Int(today.timeIntervalSince1970))")
        let record = CKRecord(recordType: CKContestType.progress, recordID: recordID)
        let progressID = "\(myCode)_\(today.timeIntervalSince1970)"
        record[CKField.progressID]    = progressID as CKRecordValue
        record[CKField.contestID]     = contestID as CKRecordValue
        record[CKField.userCode]      = myCode as CKRecordValue
        record[CKField.date]          = today as CKRecordValue
        record[CKField.value]         = value as CKRecordValue
        record[CKField.cumulative]    = cumulativeValue as CKRecordValue
        record[CKField.dailyTargetMet] = (dailyTargetMet ? 1 : 0) as CKRecordValue

        let op = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
        op.savePolicy = .allKeys
        do {
            try await runModifyOperation(op)
        } catch {
            print("[ContestService] recordProgress failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Private: Persist + Decode

    private func saveContestRecord(_ contest: Contest) async throws {
        let recordID = CKRecord.ID(recordName: "contest_\(contest.contestID)")
        let record = CKRecord(recordType: CKContestType.contest, recordID: recordID)
        record[CKField.contestID]   = contest.contestID as CKRecordValue
        record[CKField.ownerCode]   = contest.ownerCode as CKRecordValue
        record[CKField.title]       = contest.title as CKRecordValue
        if let d = contest.description { record[CKField.description] = d as CKRecordValue }
        record[CKField.type]        = contest.type.rawValue as CKRecordValue
        record[CKField.metric]      = contest.metric.rawValue as CKRecordValue
        record[CKField.targetValue] = contest.targetValue as CKRecordValue
        record[CKField.startDate]   = contest.startDate as CKRecordValue
        record[CKField.endDate]     = contest.endDate as CKRecordValue
        record[CKField.scope]       = contest.scope.rawValue as CKRecordValue
        if let t = contest.teamID { record[CKField.teamID] = t as CKRecordValue }
        record[CKField.inviteCode]  = contest.inviteCode as CKRecordValue
        record[CKField.isActive]    = (contest.isActive ? 1 : 0) as CKRecordValue

        let op = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
        op.savePolicy = .allKeys
        try await runModifyOperation(op)
    }

    private func joinAsParticipant(contest: Contest, subTeamID: String? = nil) async throws {
        let myCode = CloudKitService.shared.myFriendCode
        let settings = UserSettings.shared
        let displayName = settings.effectiveProfileName(fallbackName: UIDevice.current.name)
        let avatarPreset = settings.avatarPreset.rawValue

        let participant = ContestParticipant(
            participantID: "\(contest.contestID)_\(myCode)",
            contestID:    contest.contestID,
            userCode:     myCode,
            displayName:  displayName,
            avatarPreset: avatarPreset,
            joinedAt:     Date(),
            subTeamID:    subTeamID
        )

        let recordID = CKRecord.ID(recordName: "participant_\(participant.participantID)")
        let record = CKRecord(recordType: CKContestType.participant, recordID: recordID)
        record[CKField.participantID] = participant.participantID as CKRecordValue
        record[CKField.contestID]     = participant.contestID as CKRecordValue
        record[CKField.userCode]      = participant.userCode as CKRecordValue
        record[CKField.displayName]   = participant.displayName as CKRecordValue
        record[CKField.avatarPreset]  = participant.avatarPreset as CKRecordValue
        record[CKField.joinedAt]      = participant.joinedAt as CKRecordValue
        if let sub = subTeamID { record[CKField.subTeamID] = sub as CKRecordValue }

        let op = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
        op.savePolicy = .allKeys
        try await runModifyOperation(op)

        var current = participantsByContest[contest.id] ?? []
        current.removeAll { $0.userCode == myCode }
        current.append(participant)
        participantsByContest[contest.id] = current
    }

    private func fetchParticipants(for contestID: String) async throws -> [ContestParticipant] {
        let predicate = NSPredicate(format: "%K == %@", CKField.contestID, contestID)
        let query = CKQuery(recordType: CKContestType.participant, predicate: predicate)
        let records = try await runQuery(query, limit: 200)
        return records.compactMap(decodeParticipant)
    }

    private func fetchProgress(for contestID: String) async throws -> [ContestProgress] {
        let predicate = NSPredicate(format: "%K == %@", CKField.contestID, contestID)
        let query = CKQuery(recordType: CKContestType.progress, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: CKField.date, ascending: true)]
        let records = try await runQuery(query, limit: 1000)
        return records.compactMap(decodeProgress)
    }

    private func decodeContest(_ r: CKRecord) -> Contest? {
        guard let id = r[CKField.contestID] as? String,
              let owner = r[CKField.ownerCode] as? String,
              let title = r[CKField.title] as? String,
              let typeRaw = r[CKField.type] as? String,
              let type = ContestType(rawValue: typeRaw),
              let metricRaw = r[CKField.metric] as? String,
              let metric = ContestMetric(rawValue: metricRaw),
              let target = r[CKField.targetValue] as? Double,
              let start = r[CKField.startDate] as? Date,
              let end = r[CKField.endDate] as? Date,
              let scopeRaw = r[CKField.scope] as? String,
              let scope = ContestScope(rawValue: scopeRaw),
              let invite = r[CKField.inviteCode] as? String
        else { return nil }
        let active = ((r[CKField.isActive] as? Int) ?? 1) != 0
        return Contest(
            contestID: id, ownerCode: owner, title: title,
            description: r[CKField.description] as? String,
            type: type, metric: metric, targetValue: target,
            startDate: start, endDate: end, scope: scope,
            teamID: r[CKField.teamID] as? String,
            inviteCode: invite, isActive: active
        )
    }

    private func decodeParticipant(_ r: CKRecord) -> ContestParticipant? {
        guard let id = r[CKField.participantID] as? String,
              let contestID = r[CKField.contestID] as? String,
              let userCode = r[CKField.userCode] as? String,
              let name = r[CKField.displayName] as? String,
              let preset = r[CKField.avatarPreset] as? String,
              let joined = r[CKField.joinedAt] as? Date
        else { return nil }
        return ContestParticipant(
            participantID: id, contestID: contestID, userCode: userCode,
            displayName: name, avatarPreset: preset, joinedAt: joined,
            subTeamID: r[CKField.subTeamID] as? String
        )
    }

    private func decodeProgress(_ r: CKRecord) -> ContestProgress? {
        guard let id = r[CKField.progressID] as? String,
              let contestID = r[CKField.contestID] as? String,
              let userCode = r[CKField.userCode] as? String,
              let date = r[CKField.date] as? Date,
              let value = r[CKField.value] as? Double,
              let cumulative = r[CKField.cumulative] as? Double
        else { return nil }
        let met = ((r[CKField.dailyTargetMet] as? Int) ?? 0) != 0
        return ContestProgress(
            progressID: id, contestID: contestID, userCode: userCode,
            date: date, value: value, cumulativeValue: cumulative,
            dailyTargetMet: met
        )
    }

    // MARK: - Standings (Leaderboard-Berechnung)

    private func computeStandings(
        contest: Contest,
        participants: [ContestParticipant],
        progress: [ContestProgress]
    ) -> [ContestStanding] {
        let groupedByUser = Dictionary(grouping: progress, by: \.userCode)

        let raw = participants.map { p -> (ContestParticipant, Double, Double) in
            let userProgress = groupedByUser[p.userCode] ?? []
            let value: Double
            switch contest.type {
            case .dailyStreak:
                value = Double(userProgress.filter(\.dailyTargetMet).count)
            case .cumulativeTotal, .calorieGoal:
                value = userProgress.last?.cumulativeValue ?? 0
            case .scoreRace:
                value = userProgress.map(\.value).max() ?? 0
            }
            let avg: Double = userProgress.isEmpty ? 0 :
                userProgress.reduce(0) { $0 + $1.value } / Double(userProgress.count)
            return (p, value, avg)
        }
        let sorted = raw.sorted { $0.1 > $1.1 }
        return sorted.enumerated().map { idx, tuple in
            ContestStanding(
                participant: tuple.0,
                currentValue: tuple.1,
                dailyAverage: tuple.2,
                rank: idx + 1,
                rankDelta: 0    // Phase 2: rank delta tracking
            )
        }
    }

    // MARK: - CKQueryOperation helpers

    private func runQuery(_ query: CKQuery, limit: Int) async throws -> [CKRecord] {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[CKRecord], Error>) in
            var results: [CKRecord] = []
            let op = CKQueryOperation(query: query)
            op.resultsLimit = limit
            op.recordMatchedBlock = { _, result in
                if case .success(let r) = result { results.append(r) }
            }
            op.queryResultBlock = { result in
                switch result {
                case .success: cont.resume(returning: results)
                case .failure(let e): cont.resume(throwing: e)
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
                case .failure(let e): cont.resume(throwing: e)
                }
            }
            publicDB.add(op)
        }
    }

    // MARK: - Cache (offline-fähig)

    private func persistCache() {
        guard let data = try? JSONEncoder().encode(contests) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }

    private func loadCache() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let decoded = try? JSONDecoder().decode([Contest].self, from: data) else { return }
        contests = decoded
    }
}
