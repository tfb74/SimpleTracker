import SwiftUI

struct ContestListView: View {
    @Environment(ContestService.self) private var contestService
    @Environment(TeamService.self) private var teamService
    @Environment(CloudKitService.self) private var cloudKit

    @State private var showCreate = false
    @State private var showJoin = false

    private var active: [Contest] {
        contestService.contests.filter { $0.isInProgress }.sorted { $0.endDate < $1.endDate }
    }
    private var upcoming: [Contest] {
        contestService.contests.filter { $0.isUpcoming }.sorted { $0.startDate < $1.startDate }
    }
    private var finished: [Contest] {
        contestService.contests.filter { $0.isFinished }.sorted { $0.endDate > $1.endDate }
    }

    var body: some View {
        NavigationStack {
            List {
                if !cloudKit.isAvailable {
                    iCloudHint
                }

                if !active.isEmpty {
                    Section(lt("Aktive Contests")) {
                        ForEach(active) { contest in
                            NavigationLink(destination: ContestDetailView(contest: contest)) {
                                ContestRow(contest: contest, accent: .green)
                            }
                        }
                    }
                }
                if !upcoming.isEmpty {
                    Section(lt("Kommende Contests")) {
                        ForEach(upcoming) { contest in
                            NavigationLink(destination: ContestDetailView(contest: contest)) {
                                ContestRow(contest: contest, accent: .orange)
                            }
                        }
                    }
                }
                if !finished.isEmpty {
                    Section(lt("Beendet")) {
                        ForEach(finished) { contest in
                            NavigationLink(destination: ContestDetailView(contest: contest)) {
                                ContestRow(contest: contest, accent: .secondary)
                            }
                        }
                    }
                }

                if active.isEmpty && upcoming.isEmpty && finished.isEmpty {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(Color.accentColor.gradient)
                            Text(lt("Noch keine Contests"))
                                .font(.headline)
                            Text(lt("Starte einen neuen Contest oder tritt einem mit Code bei."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .navigationTitle(lt("Contests"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showCreate = true
                        } label: {
                            Label(lt("Neuer Contest"), systemImage: "plus.circle")
                        }
                        Button {
                            showJoin = true
                        } label: {
                            Label(lt("Beitreten via Code"), systemImage: "person.badge.key")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(!cloudKit.isAvailable)
                }
            }
            .sheet(isPresented: $showCreate) {
                ContestCreateSheet()
            }
            .sheet(isPresented: $showJoin) {
                ContestJoinSheet()
            }
            .refreshable {
                await contestService.refreshAll()
                await teamService.refreshAll()
            }
            .task {
                await contestService.refreshAll()
                await teamService.refreshAll()
            }
        }
    }

    private var iCloudHint: some View {
        Section {
            VStack(spacing: 8) {
                Image(systemName: "icloud.slash")
                    .font(.title)
                    .foregroundStyle(.orange)
                Text(lt("iCloud nicht verfügbar"))
                    .font(.headline)
                Text(lt("Aktiviere iCloud in den iOS-Einstellungen, um Contests zu nutzen."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }
}

// MARK: - Contest Row

private struct ContestRow: View {
    let contest: Contest
    let accent: Color

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(accent.opacity(0.15)).frame(width: 40, height: 40)
                Image(systemName: contest.type.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(contest.title).font(.subheadline.weight(.semibold))
                Text("\(contest.type.displayName) · \(contest.metric.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(contest.remainingLabel())
                .font(.caption2.weight(.medium))
                .foregroundStyle(accent)
        }
        .padding(.vertical, 2)
    }
}
