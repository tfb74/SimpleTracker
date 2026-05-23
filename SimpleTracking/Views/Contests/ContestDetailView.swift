import SwiftUI
import Charts

struct ContestDetailView: View {
    let contest: Contest

    @Environment(ContestService.self) private var contestService
    @Environment(CloudKitService.self) private var cloudKit
    @State private var showShareSheet = false
    @State private var showLeaveConfirm = false

    private var standings: [ContestStanding] {
        contestService.standingsByContest[contest.id] ?? []
    }
    private var myCode: String { cloudKit.myFriendCode }
    private var myStanding: ContestStanding? {
        standings.first(where: { $0.participant.userCode == myCode })
    }
    private var inviteURL: URL {
        URL(string: "https://tfb74.github.io/SimpleTracker/contest?code=\(contest.inviteCode)")
        ?? URL(string: "https://tfb74.github.io/SimpleTracker/")!
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerCard
                myProgressCard
                leaderboardCard
                chartCard
                inviteCard
            }
            .padding()
        }
        .navigationTitle(contest.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showShareSheet = true
                    } label: {
                        Label(lt("Einladen"), systemImage: "square.and.arrow.up")
                    }
                    Button(role: .destructive) {
                        showLeaveConfirm = true
                    } label: {
                        Label(lt("Verlassen"), systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareLink(
                item: inviteURL,
                subject: Text(lf("Mach mit beim Contest %@", contest.title)),
                message: Text(lt("Tippe auf den Link, um dem Contest beizutreten."))
            )
        }
        .confirmationDialog(
            lt("Contest verlassen?"),
            isPresented: $showLeaveConfirm,
            titleVisibility: .visible
        ) {
            Button(lt("Verlassen"), role: .destructive) {
                Task {
                    try? await contestService.leaveContest(contest)
                }
            }
            Button(lt("Abbrechen"), role: .cancel) {}
        } message: {
            Text(lt("Dein Fortschritt bleibt im Cloud-Verlauf, wird aber nicht mehr gewertet."))
        }
        .task {
            await contestService.refreshAll()
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: contest.type.systemImage)
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(contest.type.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(contest.title).font(.title3.bold())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(contest.remainingLabel())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(contest.isInProgress ? .green : .secondary)
                    Text(contest.endDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if let desc = contest.description, !desc.isEmpty {
                Text(desc).font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Label(metricLabel, systemImage: "target")
                    .font(.caption)
                    .foregroundStyle(.primary)
                Spacer()
                Text(contest.type.explanation)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var metricLabel: String {
        let value = formatValue(contest.targetValue)
        switch contest.type {
        case .dailyStreak: return lf("Tagesziel: %@ %@", value, contest.metric.unit)
        case .cumulativeTotal, .calorieGoal: return lf("Gesamtziel: %@ %@", value, contest.metric.unit)
        case .scoreRace: return lt("Höchster Workout-Score gewinnt")
        }
    }

    // MARK: - My Progress

    private var myProgressCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(lt("Mein Fortschritt"))
                .font(.headline)
            if let me = myStanding {
                HStack {
                    Text(formatValue(me.currentValue))
                        .font(.system(size: 36, weight: .bold).monospacedDigit())
                        .foregroundStyle(Color.accentColor)
                    Text(contest.metric.unit).font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    rankBadge(rank: me.rank, total: standings.count)
                }
                if contest.type != .scoreRace {
                    let target = contest.targetValue
                    let progress = target > 0 ? min(1.0, me.currentValue / target) : 0
                    ProgressView(value: progress)
                        .tint(Color.accentColor)
                    HStack {
                        Text(lf("%@%% des Ziels", String(format: "%.0f", progress * 100)))
                            .font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Text(lf("Ziel: %@ %@", formatValue(target), contest.metric.unit))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            } else {
                Text(lt("Noch keine Daten"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func rankBadge(rank: Int, total: Int) -> some View {
        VStack(spacing: 2) {
            Text("#\(rank)")
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(rank == 1 ? .yellow : .primary)
            Text(lf("von %d", total))
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(rank == 1 ? Color.yellow.opacity(0.15) : Color.secondary.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Leaderboard

    private var leaderboardCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(lt("Leaderboard")).font(.headline)
                Spacer()
                Text(lf("%d Teilnehmer", standings.count))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if standings.isEmpty {
                Text(lt("Noch keine Teilnehmer.")).font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(standings) { standing in
                    leaderboardRow(standing)
                    if standing.id != standings.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func leaderboardRow(_ s: ContestStanding) -> some View {
        let isMe = s.participant.userCode == myCode
        return HStack(spacing: 10) {
            Text("#\(s.rank)")
                .font(.subheadline.bold().monospacedDigit())
                .frame(width: 36, alignment: .leading)
                .foregroundStyle(s.rank == 1 ? .yellow : (isMe ? Color.accentColor : .primary))

            UserAvatarView(
                size: 32,
                name: s.participant.displayName,
                photoData: nil,
                preset: s.participant.avatarPresetEnum,
                fallbackImage: nil
            )

            Text(s.participant.displayName)
                .font(.subheadline)
                .fontWeight(isMe ? .bold : .regular)

            Spacer()
            HStack(spacing: 4) {
                Text(formatValue(s.currentValue))
                    .font(.subheadline.monospacedDigit().bold())
                Text(contest.metric.unit)
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Chart

    @ViewBuilder
    private var chartCard: some View {
        let progressList = (contestService.progressByContest[contest.id] ?? []).sorted { $0.date < $1.date }
        if progressList.count >= 2 {
            VStack(alignment: .leading, spacing: 8) {
                Text(lt("Verlauf")).font(.headline)
                Chart {
                    ForEach(standings.prefix(5)) { s in
                        ForEach(progressList.filter { $0.userCode == s.participant.userCode }) { p in
                            LineMark(
                                x: .value("Date", p.date),
                                y: .value("Value", contest.type == .dailyStreak ? Double(progressList.filter { $0.userCode == s.participant.userCode && $0.date <= p.date && $0.dailyTargetMet }.count) : p.cumulativeValue)
                            )
                            .foregroundStyle(by: .value("User", s.participant.displayName))
                        }
                    }
                }
                .frame(height: 180)
                .chartLegend(position: .bottom)
            }
            .padding()
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Invite

    private var inviteCard: some View {
        VStack(spacing: 8) {
            HStack {
                Text(lt("Invite-Code")).font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            HStack {
                Text(contest.inviteCode)
                    .font(.system(.title3, design: .monospaced).weight(.bold))
                    .foregroundStyle(Color.accentColor)
                Spacer()
                Button {
                    UIPasteboard.general.string = contest.inviteCode
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                ShareLink(item: inviteURL) {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Format

    private func formatValue(_ v: Double) -> String {
        switch contest.metric {
        case .steps, .calories, .workoutScore: return Int(v).formatted()
        case .distanceKm: return String(format: "%.1f", v)
        }
    }
}
