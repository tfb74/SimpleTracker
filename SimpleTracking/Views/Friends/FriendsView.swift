import SwiftUI

struct FriendsView: View {
    @Environment(CloudKitService.self) private var cloudKit
    @Environment(UserSettings.self)   private var settings
    @Environment(GameCenterService.self) private var gameCenter

    @State private var showAddFriend = false

    var body: some View {
        NavigationStack {
            List {
                if !cloudKit.isAvailable {
                    comingSoonBanner
                }
                myProfileSection
                if !cloudKit.feed.isEmpty {
                    feedSection
                }
                if cloudKit.isAvailable {
                    friendsSection
                }
            }
            .navigationTitle("Freunde & Feed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if cloudKit.isAvailable {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showAddFriend = true
                        } label: {
                            Image(systemName: "person.badge.plus")
                        }
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    if cloudKit.isLoading {
                        ProgressView().scaleEffect(0.8)
                    }
                }
            }
            .sheet(isPresented: $showAddFriend) {
                AddFriendSheet()
            }
            .refreshable {
                await cloudKit.refreshFeed()
            }
            .task {
                cloudKit.markAllRead()
                await cloudKit.refreshFeed()
            }
        }
    }

    // MARK: - My Profile

    private var myProfileSection: some View {
        Section {
            HStack(spacing: 14) {
                UserAvatarView(
                    size: 52,
                    name: displayName,
                    photoData: settings.avatarImageData,
                    preset: settings.avatarPreset,
                    fallbackImage: gameCenter.isAuthenticated ? gameCenter.playerAvatar : nil
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(displayName)
                        .font(.headline)
                    Text("Dein Code")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        Text(cloudKit.myFriendCode)
                            .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                            .foregroundStyle(Color.accentColor)

                        Button {
                            UIPasteboard.general.string = cloudKit.myFriendCode
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()

                if cloudKit.isAvailable {
                    Image(systemName: "icloud.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Mein Profil")
        } footer: {
            Text("Teile deinen Code mit Freunden, damit sie dich hinzufügen können.")
        }
    }

    // MARK: - Activity Feed

    private var feedSection: some View {
        Section("Aktivitäten") {
            ForEach(cloudKit.feed.prefix(20)) { activity in
                FeedRowView(activity: activity)
            }
        }
    }

    // MARK: - Friends List

    private var friendsSection: some View {
        Section {
            if cloudKit.friends.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: "person.2.slash")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("Noch keine Freunde")
                            .foregroundStyle(.secondary)
                        Button("Freund hinzufügen") { showAddFriend = true }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 20)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else {
                ForEach(cloudKit.friends) { friend in
                    FriendRowView(friend: friend)
                }
                .onDelete { offsets in
                    for index in offsets {
                        cloudKit.removeFriend(code: cloudKit.friends[index].code)
                    }
                }
            }
        } header: {
            Text("Freunde (\(cloudKit.friends.count))")
        }
    }

    // MARK: - Coming Soon Banner

    private var comingSoonBanner: some View {
        Section {
            VStack(spacing: 14) {
                Image(systemName: "person.2.wave.2.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.blue.gradient)

                VStack(spacing: 6) {
                    Text("Community – bald verfügbar")
                        .font(.headline)
                    Text("Verbinde dich mit Freunden, teile Workouts und verfolge Achievements gemeinsam. Dein persönlicher Code ist schon bereit.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .listRowBackground(Color.clear)
        }
    }

    private var displayName: String {
        let fallback = gameCenter.isAuthenticated ? gameCenter.playerName : UIDevice.current.name
        return settings.effectiveProfileName(fallbackName: fallback)
    }
}

// MARK: - Feed Row

private struct FeedRowView: View {
    let activity: FriendActivity

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 40, height: 40)

                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(activity.displayName)
                        .font(.subheadline.weight(.semibold))
                    if !activity.isRead {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 7, height: 7)
                    }
                }
                Text(activity.eventTitle)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Text(activity.eventDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(activity.timestamp.relativeShort)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var icon: String {
        switch activity.eventType {
        case .achievement:
            return "trophy.fill"
        case .workout:
            return activity.workoutType?.systemImage ?? "figure.run"
        }
    }

    private var iconColor: Color {
        switch activity.eventType {
        case .achievement: return .yellow
        case .workout:     return .blue
        }
    }
}

// MARK: - Friend Row

private struct FriendRowView: View {
    let friend: FriendProfile

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                LinearGradient(
                    colors: (ProfileAvatarPreset(rawValue: friend.avatarPreset) ?? .person).gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: (ProfileAvatarPreset(rawValue: friend.avatarPreset) ?? .person).systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 38, height: 38)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(friend.displayName)
                    .font(.subheadline.weight(.semibold))
                Text(friend.code)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fontDesign(.monospaced)
            }

            Spacer()
        }
    }
}

// MARK: - Add Friend Sheet

private struct AddFriendSheet: View {
    @Environment(CloudKitService.self) private var cloudKit
    @Environment(\.dismiss) private var dismiss

    @State private var code      = ""
    @State private var isAdding  = false
    @State private var errorMsg: String? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 52))
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 16)

                VStack(spacing: 6) {
                    Text("Freund hinzufügen")
                        .font(.title2.weight(.bold))
                    Text("Gib den 7-stelligen Code deines Freundes ein.\nBeispiel: ABC-123")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                TextField("ABC-123", text: $code)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal)
                    .onChange(of: code) { _, new in
                        errorMsg = nil
                        // Auto-insert dash after 3 chars
                        let digits = new.filter { $0.isLetter || $0.isNumber }
                        if digits.count > 3 {
                            code = "\(digits.prefix(3))-\(digits.dropFirst(3).prefix(4))"
                        } else {
                            code = String(digits.prefix(3))
                        }
                    }

                if let errorMsg {
                    Text(errorMsg)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                Button {
                    Task { await addFriend() }
                } label: {
                    Group {
                        if isAdding {
                            ProgressView()
                        } else {
                            Text("Hinzufügen")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(code.count < 7 || isAdding)
                .padding(.horizontal)

                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func addFriend() async {
        isAdding = true
        errorMsg = nil
        do {
            try await cloudKit.addFriend(code: code)
            dismiss()
        } catch {
            errorMsg = error.localizedDescription
        }
        isAdding = false
    }
}

// MARK: - Date Helper

private extension Date {
    var relativeShort: String {
        let diff = Date().timeIntervalSince(self)
        if diff < 3_600 {
            return "\(Int(diff / 60))m"
        } else if diff < 86_400 {
            return "\(Int(diff / 3_600))h"
        } else {
            return "\(Int(diff / 86_400))d"
        }
    }
}
