import Foundation
import UIKit
import CloudKit

private enum CKTeamType {
    static let team       = "STTeam"
    static let membership = "STTeamMembership"
}

private enum CKTeamField {
    static let teamID        = "teamID"
    static let parentTeamID  = "parentTeamID"
    static let name          = "teamName"
    static let inviteCode    = "inviteCode"
    static let ownerCode     = "ownerCode"
    static let memberCount   = "memberCount"
    static let membershipID  = "membershipID"
    static let userCode      = "userCode"
    static let displayName   = "displayName"
    static let avatarPreset  = "avatarPreset"
    static let joinedAt      = "joinedAt"
    static let isAdmin       = "isAdmin"
}

@Observable
@MainActor
final class TeamService {
    static let shared = TeamService()

    /// Alle Teams in denen ich Mitglied bin (Top-Level + Sub-Teams)
    private(set) var myTeams: [Team] = []
    private(set) var membershipsByTeam: [String: [TeamMembership]] = [:]
    private(set) var subTeamsByParent: [String: [Team]] = [:]
    private(set) var isLoading = false
    private(set) var lastErrorMessage: String?

    private let container: CKContainer
    private var publicDB: CKDatabase { container.publicCloudDatabase }
    private let cacheKey = "team.cache.v1"

    private init() {
        self.container = CKContainer(identifier: "iCloud.de.baumannheim.SimpleTracking")
        loadCache()
    }

    // MARK: - Public API

    /// Erstellt ein neues Team. Wenn `parentTeamID` gesetzt ist, wird's als
    /// Sub-Team angelegt (Voraussetzung: ich bin Admin im Parent-Team).
    @discardableResult
    func createTeam(name: String, parentTeamID: String? = nil) async throws -> Team {
        guard CloudKitService.shared.isAvailable else { throw ContestError.iCloudUnavailable }

        if let parentTeamID {
            // Admin-Check
            let memberships = membershipsByTeam[parentTeamID] ?? []
            let me = memberships.first { $0.userCode == CloudKitService.shared.myFriendCode }
            guard me?.isAdmin == true else { throw ContestError.notTeamAdmin }
        }

        let myCode = CloudKitService.shared.myFriendCode
        let team = Team(
            teamID:       UUID().uuidString,
            parentTeamID: parentTeamID,
            name:         name.trimmingCharacters(in: .whitespacesAndNewlines),
            inviteCode:   ContestCodeGenerator.makeInviteCode(),
            ownerCode:    myCode,
            memberCount:  1
        )
        try await saveTeamRecord(team)
        try await joinAsMember(team: team, asAdmin: true)

        myTeams.append(team)
        if let parentTeamID {
            var subs = subTeamsByParent[parentTeamID] ?? []
            subs.append(team)
            subTeamsByParent[parentTeamID] = subs
        }
        persistCache()
        return team
    }

    @discardableResult
    func joinTeam(inviteCode: String) async throws -> Team {
        guard CloudKitService.shared.isAvailable else { throw ContestError.iCloudUnavailable }
        let normalized = inviteCode.uppercased()
        let predicate = NSPredicate(format: "%K == %@", CKTeamField.inviteCode, normalized)
        let query = CKQuery(recordType: CKTeamType.team, predicate: predicate)
        let records = try await runQuery(query, limit: 1)
        guard let r = records.first, let team = decodeTeam(r) else {
            throw ContestError.teamNotFound
        }

        let memberships = try await fetchMemberships(for: team.teamID)
        if memberships.contains(where: { $0.userCode == CloudKitService.shared.myFriendCode }) {
            throw ContestError.alreadyJoined
        }
        try await joinAsMember(team: team, asAdmin: false)

        if !myTeams.contains(where: { $0.id == team.id }) {
            myTeams.append(team)
        }
        membershipsByTeam[team.id] = (memberships + [makeMembership(team: team, isAdmin: false)])
        persistCache()
        return team
    }

    func refreshAll() async {
        guard CloudKitService.shared.isAvailable else { return }
        isLoading = true
        defer { isLoading = false }

        let myCode = CloudKitService.shared.myFriendCode
        do {
            let predicate = NSPredicate(format: "%K == %@", CKTeamField.userCode, myCode)
            let query = CKQuery(recordType: CKTeamType.membership, predicate: predicate)
            let memberRecs = try await runQuery(query, limit: 100)
            let myMemberships = memberRecs.compactMap(decodeMembership)
            let teamIDs = Array(Set(myMemberships.map(\.teamID)))

            guard !teamIDs.isEmpty else {
                myTeams = []
                membershipsByTeam = [:]
                subTeamsByParent = [:]
                persistCache()
                return
            }

            let teamPredicate = NSPredicate(format: "%K IN %@", CKTeamField.teamID, teamIDs)
            let teamQuery = CKQuery(recordType: CKTeamType.team, predicate: teamPredicate)
            let teamRecs = try await runQuery(teamQuery, limit: 100)
            let loaded = teamRecs.compactMap(decodeTeam)
            myTeams = loaded.sorted { $0.name < $1.name }

            // Sub-Teams einsammeln (für jeden Top-Level: Kinder ohne Membership-Filter)
            for top in loaded.filter({ $0.parentTeamID == nil }) {
                let subPredicate = NSPredicate(format: "%K == %@", CKTeamField.parentTeamID, top.teamID)
                let subQuery = CKQuery(recordType: CKTeamType.team, predicate: subPredicate)
                let subRecs = try await runQuery(subQuery, limit: 100)
                let subs = subRecs.compactMap(decodeTeam)
                subTeamsByParent[top.teamID] = subs
            }

            // Mitglieder pro Team laden
            for team in loaded {
                let members = try await fetchMemberships(for: team.teamID)
                membershipsByTeam[team.id] = members
            }
            persistCache()
            lastErrorMessage = nil
        } catch {
            print("[TeamService] refreshAll failed: \(error.localizedDescription)")
            lastErrorMessage = error.localizedDescription
        }
    }

    /// Liefert Sub-Teams eines Top-Teams. Leeres Array wenn keine.
    func subTeams(of teamID: String) -> [Team] {
        subTeamsByParent[teamID] ?? []
    }

    /// Bin ich Admin in diesem Team?
    func isAdmin(of teamID: String) -> Bool {
        let myCode = CloudKitService.shared.myFriendCode
        return membershipsByTeam[teamID]?.first(where: { $0.userCode == myCode })?.isAdmin == true
    }

    // MARK: - Private CK-Operationen

    private func saveTeamRecord(_ team: Team) async throws {
        let recordID = CKRecord.ID(recordName: "team_\(team.teamID)")
        let record = CKRecord(recordType: CKTeamType.team, recordID: recordID)
        record[CKTeamField.teamID]      = team.teamID as CKRecordValue
        if let p = team.parentTeamID { record[CKTeamField.parentTeamID] = p as CKRecordValue }
        record[CKTeamField.name]        = team.name as CKRecordValue
        record[CKTeamField.inviteCode]  = team.inviteCode as CKRecordValue
        record[CKTeamField.ownerCode]   = team.ownerCode as CKRecordValue
        record[CKTeamField.memberCount] = team.memberCount as CKRecordValue
        let op = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
        op.savePolicy = .allKeys
        try await runModifyOperation(op)
    }

    private func makeMembership(team: Team, isAdmin: Bool) -> TeamMembership {
        let s = UserSettings.shared
        let name = s.effectiveProfileName(fallbackName: UIDevice.current.name)
        return TeamMembership(
            membershipID: "\(team.teamID)_\(CloudKitService.shared.myFriendCode)",
            teamID: team.teamID,
            userCode: CloudKitService.shared.myFriendCode,
            displayName: name,
            avatarPreset: s.avatarPreset.rawValue,
            joinedAt: Date(),
            isAdmin: isAdmin
        )
    }

    private func joinAsMember(team: Team, asAdmin: Bool) async throws {
        let m = makeMembership(team: team, isAdmin: asAdmin)
        let recordID = CKRecord.ID(recordName: "membership_\(m.membershipID)")
        let record = CKRecord(recordType: CKTeamType.membership, recordID: recordID)
        record[CKTeamField.membershipID] = m.membershipID as CKRecordValue
        record[CKTeamField.teamID]       = m.teamID as CKRecordValue
        record[CKTeamField.userCode]     = m.userCode as CKRecordValue
        record[CKTeamField.displayName]  = m.displayName as CKRecordValue
        record[CKTeamField.avatarPreset] = m.avatarPreset as CKRecordValue
        record[CKTeamField.joinedAt]     = m.joinedAt as CKRecordValue
        record[CKTeamField.isAdmin]      = (m.isAdmin ? 1 : 0) as CKRecordValue
        let op = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
        op.savePolicy = .allKeys
        try await runModifyOperation(op)
    }

    private func fetchMemberships(for teamID: String) async throws -> [TeamMembership] {
        let predicate = NSPredicate(format: "%K == %@", CKTeamField.teamID, teamID)
        let query = CKQuery(recordType: CKTeamType.membership, predicate: predicate)
        let records = try await runQuery(query, limit: 500)
        return records.compactMap(decodeMembership)
    }

    private func decodeTeam(_ r: CKRecord) -> Team? {
        guard let id = r[CKTeamField.teamID] as? String,
              let name = r[CKTeamField.name] as? String,
              let invite = r[CKTeamField.inviteCode] as? String,
              let owner = r[CKTeamField.ownerCode] as? String
        else { return nil }
        return Team(
            teamID: id,
            parentTeamID: r[CKTeamField.parentTeamID] as? String,
            name: name,
            inviteCode: invite,
            ownerCode: owner,
            memberCount: (r[CKTeamField.memberCount] as? Int) ?? 0
        )
    }

    private func decodeMembership(_ r: CKRecord) -> TeamMembership? {
        guard let id = r[CKTeamField.membershipID] as? String,
              let teamID = r[CKTeamField.teamID] as? String,
              let userCode = r[CKTeamField.userCode] as? String,
              let name = r[CKTeamField.displayName] as? String,
              let preset = r[CKTeamField.avatarPreset] as? String,
              let joined = r[CKTeamField.joinedAt] as? Date
        else { return nil }
        let isAdmin = ((r[CKTeamField.isAdmin] as? Int) ?? 0) != 0
        return TeamMembership(
            membershipID: id, teamID: teamID, userCode: userCode,
            displayName: name, avatarPreset: preset, joinedAt: joined,
            isAdmin: isAdmin
        )
    }

    // MARK: - CK Helpers

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

    // MARK: - Cache

    private func persistCache() {
        guard let data = try? JSONEncoder().encode(myTeams) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }

    private func loadCache() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let decoded = try? JSONDecoder().decode([Team].self, from: data) else { return }
        myTeams = decoded
    }
}
