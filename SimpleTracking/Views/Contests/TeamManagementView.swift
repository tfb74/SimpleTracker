import SwiftUI

struct TeamManagementView: View {
    @Environment(TeamService.self) private var teamService
    @Environment(CloudKitService.self) private var cloudKit

    @State private var showCreate = false
    @State private var showJoin = false

    private var topLevelTeams: [Team] {
        teamService.myTeams.filter { $0.parentTeamID == nil }
    }

    var body: some View {
        NavigationStack {
            List {
                if !cloudKit.isAvailable {
                    Section {
                        Label(lt("iCloud nicht verfügbar"), systemImage: "icloud.slash")
                            .foregroundStyle(.orange)
                    }
                }

                if topLevelTeams.isEmpty {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "person.3.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(.purple.gradient)
                            Text(lt("Noch in keinem Team"))
                                .font(.headline)
                            Text(lt("Lege ein Team an oder tritt einem mit Code bei."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .listRowBackground(Color.clear)
                    }
                }

                ForEach(topLevelTeams) { team in
                    Section(team.name) {
                        TeamSummaryRow(team: team, isAdmin: teamService.isAdmin(of: team.id))

                        let subs = teamService.subTeams(of: team.id)
                        if !subs.isEmpty {
                            ForEach(subs) { sub in
                                NavigationLink(destination: TeamDetailView(team: sub)) {
                                    HStack {
                                        Image(systemName: "arrow.turn.down.right")
                                            .foregroundStyle(.secondary)
                                            .font(.caption)
                                        Text(sub.name).font(.subheadline)
                                        Spacer()
                                        Text(lf("%d", sub.memberCount))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }

                        if teamService.isAdmin(of: team.id) {
                            NavigationLink(destination: SubTeamCreateView(parentTeam: team)) {
                                Label(lt("Sub-Team anlegen"), systemImage: "plus")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            }
            .navigationTitle(lt("Teams"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showCreate = true
                        } label: { Label(lt("Neues Team"), systemImage: "plus.circle") }
                        Button {
                            showJoin = true
                        } label: { Label(lt("Beitreten via Code"), systemImage: "person.badge.key") }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(!cloudKit.isAvailable)
                }
            }
            .sheet(isPresented: $showCreate) {
                TeamCreateSheet()
            }
            .sheet(isPresented: $showJoin) {
                TeamJoinSheet()
            }
            .refreshable { await teamService.refreshAll() }
            .task { await teamService.refreshAll() }
        }
    }
}

// MARK: - Team Summary Row

private struct TeamSummaryRow: View {
    let team: Team
    let isAdmin: Bool

    var body: some View {
        NavigationLink(destination: TeamDetailView(team: team)) {
            HStack {
                Image(systemName: "person.3.fill")
                    .foregroundStyle(.purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text(team.name).font(.subheadline.weight(.semibold))
                    HStack(spacing: 4) {
                        Text(lf("%d Mitglieder", team.memberCount))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if isAdmin {
                            Text(lt("· Admin"))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                Spacer()
            }
        }
    }
}

// MARK: - Team Detail

struct TeamDetailView: View {
    let team: Team
    @Environment(TeamService.self) private var teamService

    private var members: [TeamMembership] {
        (teamService.membershipsByTeam[team.id] ?? [])
            .sorted { $0.displayName < $1.displayName }
    }

    var body: some View {
        List {
            Section(lt("Invite-Code")) {
                HStack {
                    Text(team.inviteCode)
                        .font(.system(.title3, design: .monospaced).weight(.bold))
                        .foregroundStyle(Color.accentColor)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = team.inviteCode
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                }
            }
            Section(lf("Mitglieder (%d)", members.count)) {
                ForEach(members) { m in
                    HStack {
                        UserAvatarView(
                            size: 32,
                            name: m.displayName,
                            photoData: nil,
                            preset: ProfileAvatarPreset(rawValue: m.avatarPreset) ?? .person,
                            fallbackImage: nil
                        )
                        Text(m.displayName).font(.subheadline)
                        if m.isAdmin {
                            Text(lt("Admin"))
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.15))
                                .foregroundStyle(Color.accentColor)
                                .clipShape(Capsule())
                        }
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle(team.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Sub-Team Create

struct SubTeamCreateView: View {
    let parentTeam: Team
    @Environment(\.dismiss) private var dismiss
    @Environment(TeamService.self) private var teamService

    @State private var name: String = ""
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section(lf("Sub-Team von %@", parentTeam.name)) {
                TextField(lt("Sub-Team Name (z. B. Vertrieb)"), text: $name)
            }
            if let errorMessage {
                Section { Text(errorMessage).font(.caption).foregroundStyle(.red) }
            }
            Section {
                Button {
                    Task { await create() }
                } label: {
                    Label(lt("Sub-Team anlegen"), systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .disabled(name.isEmpty || isCreating)
            }
        }
        .navigationTitle(lt("Sub-Team"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func create() async {
        isCreating = true
        do {
            _ = try await teamService.createTeam(name: name, parentTeamID: parentTeam.id)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isCreating = false
    }
}

// MARK: - Create / Join Team Sheets

struct TeamCreateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(TeamService.self) private var teamService

    @State private var name: String = ""
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(lt("Team-Name")) {
                    TextField(lt("z. B. Zalaris"), text: $name)
                }
                if let errorMessage {
                    Section { Text(errorMessage).font(.caption).foregroundStyle(.red) }
                }
            }
            .navigationTitle(lt("Neues Team"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(lt("Abbrechen")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(lt("Erstellen")) {
                        Task { await create() }
                    }
                    .fontWeight(.semibold)
                    .disabled(name.isEmpty || isCreating)
                }
            }
        }
    }

    private func create() async {
        isCreating = true
        do {
            _ = try await teamService.createTeam(name: name)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isCreating = false
    }
}

struct TeamJoinSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(TeamService.self) private var teamService

    @State private var code: String = ""
    @State private var isJoining = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.purple)
                    .padding(.top, 20)
                Text(lt("Team beitreten"))
                    .font(.title2.bold())

                TextField("ABCD-EF12", text: $code)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal)

                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(.red)
                }

                Button {
                    Task { await join() }
                } label: {
                    Group {
                        if isJoining { ProgressView() } else { Text(lt("Beitreten")) }
                    }.frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(code.count < 8 || isJoining)
                .padding(.horizontal)

                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(lt("Abbrechen")) { dismiss() }
                }
            }
        }
    }

    private func join() async {
        isJoining = true
        do {
            _ = try await teamService.joinTeam(inviteCode: code)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isJoining = false
    }
}
