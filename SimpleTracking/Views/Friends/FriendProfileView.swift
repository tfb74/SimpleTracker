import SwiftUI

/// Detail-Ansicht eines einzelnen Freundes: Profil-Header + dessen letzte
/// Aktivitäten (Workouts, Achievements) der letzten 14 Tage. Aktivitäten
/// sind die gleichen die auch im globalen Feed gezeigt werden — hier nur
/// auf diesen Freund gefiltert.
struct FriendProfileView: View {
    @Environment(CloudKitService.self) private var cloudKit
    @Environment(UserSettings.self)   private var settings
    @Environment(\.dismiss)            private var dismiss

    let friend: FriendProfile

    @State private var showMessageSheet = false
    @State private var showRemoveAlert = false

    private var activities: [FriendActivity] {
        cloudKit.feed.filter { $0.friendCode == friend.code }
    }

    private var workoutCount: Int {
        activities.filter { $0.eventType == .workout }.count
    }
    private var achievementCount: Int {
        activities.filter { $0.eventType == .achievement }.count
    }
    private var mealCount: Int {
        activities.filter { $0.eventType == .meal }.count
    }

    private var unreadMessages: Int {
        cloudKit.conversation(with: friend.code).filter {
            $0.toCode == cloudKit.myFriendCode && $0.readAt == nil
        }.count
    }

    var body: some View {
        List {
            Section {
                header
            }
            .listRowBackground(Color.clear)

            statsSection

            Section(lt("Aktivitäten")) {
                if activities.isEmpty {
                    Text(lt("Noch keine Aktivitäten in den letzten 14 Tagen."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(activities.prefix(50)) { activity in
                        NavigationLink {
                            ActivityDetailView(activity: activity)
                        } label: {
                            FriendActivityRow(activity: activity)
                        }
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    showRemoveAlert = true
                } label: {
                    Label(lt("Freund entfernen"), systemImage: "person.fill.xmark")
                }
            }
        }
        .navigationTitle(friend.presentableName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showMessageSheet = true
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "message.fill")
                        if unreadMessages > 0 {
                            Text("\(unreadMessages)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Color.red, in: Capsule())
                                .offset(x: 10, y: -8)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showMessageSheet) {
            DirectMessageView(peer: friend)
        }
        .alert(lt("Freund entfernen?"), isPresented: $showRemoveAlert) {
            Button(lt("Entfernen"), role: .destructive) {
                cloudKit.removeFriend(code: friend.code)
                dismiss()
            }
            Button(lt("Abbrechen"), role: .cancel) { }
        } message: {
            Text(lf("%@ wird aus deiner Friends-Liste entfernt. Du siehst dann keine Aktivitäten mehr.", friend.presentableName))
        }
        .task {
            // Stelle sicher dass aktueller Feed + Messages drin sind
            await cloudKit.refreshFeed()
            await cloudKit.refreshMessages()
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            UserAvatarView(
                size: 96,
                name: friend.displayName,
                photoData: nil,
                preset: friend.avatarPresetEnum,
                fallbackImage: nil,
                tryContactPhoto: true
            )

            VStack(spacing: 2) {
                Text(friend.presentableName)
                    .font(.title2.weight(.semibold))
                Text(friend.code)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var statsSection: some View {
        Section {
            HStack(spacing: 0) {
                statCell(value: workoutCount, label: lt("Workouts"), icon: "figure.run", color: .blue)
                Divider()
                statCell(value: achievementCount, label: lt("Erfolge"), icon: "trophy.fill", color: .yellow)
                Divider()
                statCell(value: mealCount, label: lt("Mahlzeiten"), icon: "fork.knife", color: .orange)
            }
        } header: {
            Text(lt("Letzte 14 Tage"))
        }
    }

    @ViewBuilder
    private func statCell(value: Int, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(color)
            Text("\(value)").font(.title2.weight(.semibold))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}

/// Aktivitäts-Row im Profile-Kontext (etwas kompakter als die Feed-Row).
private struct FriendActivityRow: View {
    let activity: FriendActivity

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(iconColor.opacity(0.15))
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
                    .font(.system(size: 14, weight: .semibold))
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(activity.eventTitle)
                    .font(.subheadline.weight(.medium))
                Text(activity.eventDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(activity.timestamp.relativeShort)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if !activity.reactions.isEmpty {
                    Text("\(activity.reactions.count) 💬")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var icon: String {
        switch activity.eventType {
        case .achievement: return "trophy.fill"
        case .meal:        return "fork.knife"
        case .workout:     return activity.workoutType?.systemImage ?? "figure.run"
        }
    }
    private var iconColor: Color {
        switch activity.eventType {
        case .achievement: return .yellow
        case .meal:        return .orange
        case .workout:     return .blue
        }
    }
}
