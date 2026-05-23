import SwiftUI

struct FriendsView: View {
    @Environment(CloudKitService.self) private var cloudKit
    @Environment(UserSettings.self)   private var settings
    @Environment(GameCenterService.self) private var gameCenter

    @State private var showAddFriend = false
    @State private var showShareCode = false

    @State private var showNamePrompt = false
    @State private var nameDraft = ""

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
                if cloudKit.isAvailable && !inboxFriends.isEmpty {
                    inboxSection
                }
                if cloudKit.isAvailable {
                    friendsSection
                }
            }
            .navigationTitle(lt("Freunde & Feed"))
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
            .sheet(isPresented: $showShareCode) {
                FriendCodeShareView(code: cloudKit.myFriendCode, displayName: displayName)
            }
            .refreshable {
                await cloudKit.refreshFeed()
            }
            .task {
                cloudKit.markAllRead()
                await cloudKit.refreshFriendProfiles()  // aktualisiert Namen/Avatare
                await cloudKit.refreshFeed()
                await cloudKit.refreshMessages()
                // Contact-Photos vorladen — bei erster Nutzung wird hier
                // die Berechtigung angefragt. Wenn der User ablehnt,
                // fallen wir auf Avatar-Preset zurück.
                await ContactMatchService.shared.requestAccessIfNeeded()
                await ContactMatchService.shared.preloadPhotos(
                    for: cloudKit.friends.map(\.displayName)
                )
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
                    Button {
                        nameDraft = settings.profileName
                        showNamePrompt = true
                    } label: {
                        HStack(spacing: 4) {
                            Text(displayName)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Image(systemName: "pencil.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)

                    Text(lt("Dein Code"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Text(cloudKit.myFriendCode)
                            .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                            .foregroundStyle(Color.accentColor)

                        Button {
                            showShareCode = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
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
            Text(lt("Mein Profil"))
        } footer: {
            Text(lt("Teile deinen Code mit Freunden, damit sie dich hinzufügen können."))
        }
        .alert(lt("Wie sollen wir dich nennen?"), isPresented: $showNamePrompt) {
            TextField(lt("Dein Name"), text: $nameDraft)
                .textInputAutocapitalization(.words)
            Button(lt("Speichern")) {
                let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                settings.profileName = String(trimmed.prefix(40))
                Task { await cloudKit.republishProfile() }
            }
            Button(lt("Abbrechen"), role: .cancel) { }
        } message: {
            Text(lt("Wir nutzen den Namen nur in deinem Friends-Feed und in Contests."))
        }
    }

    // MARK: - Activity Feed

    private var feedSection: some View {
        Section(lt("Aktivitäten")) {
            ForEach(cloudKit.feed.prefix(20)) { activity in
                NavigationLink {
                    ActivityDetailView(activity: activity)
                } label: {
                    FeedRowView(activity: activity)
                }
            }
        }
    }

    // MARK: - Inbox (Direkt-Nachrichten)

    /// Friends mit denen es eine bestehende Konversation gibt — sortiert
    /// nach letzter Nachricht, ungelesene zuerst.
    private var inboxFriends: [(friend: FriendProfile, last: DirectMessage, unread: Int)] {
        cloudKit.friends.compactMap { f -> (FriendProfile, DirectMessage, Int)? in
            let msgs = cloudKit.conversation(with: f.code)
            guard let last = msgs.last else { return nil }
            let unread = msgs.filter { $0.toCode == cloudKit.myFriendCode && $0.readAt == nil }.count
            return (f, last, unread)
        }
        .sorted { lhs, rhs in
            if (lhs.2 > 0) != (rhs.2 > 0) { return lhs.2 > rhs.2 }
            return lhs.1.timestamp > rhs.1.timestamp
        }
    }

    private var inboxSection: some View {
        Section(lt("Nachrichten")) {
            ForEach(inboxFriends.prefix(10), id: \.friend.id) { item in
                NavigationLink {
                    DirectMessageView(peer: item.friend)
                } label: {
                    HStack(spacing: 10) {
                        UserAvatarView(
                            size: 34,
                            name: item.friend.displayName,
                            photoData: nil,
                            preset: item.friend.avatarPresetEnum,
                            fallbackImage: nil,
                            tryContactPhoto: true
                        )

                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(item.friend.presentableName)
                                    .font(.subheadline.weight(.semibold))
                                if item.unread > 0 {
                                    Text("\(item.unread)")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6).padding(.vertical, 1)
                                        .background(Color.red, in: Capsule())
                                }
                            }
                            Text(item.last.text)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(item.last.timestamp.relativeShort)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
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
                        Text(lt("Noch keine Freunde"))
                            .foregroundStyle(.secondary)
                        Button(lt("Freund hinzufügen")) { showAddFriend = true }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 20)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else {
                ForEach(cloudKit.friends) { friend in
                    NavigationLink {
                        FriendProfileView(friend: friend)
                    } label: {
                        FriendRowView(friend: friend)
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        cloudKit.removeFriend(code: cloudKit.friends[index].code)
                    }
                }
            }
        } header: {
            Text(lf("Freunde (%d)", cloudKit.friends.count))
        }
    }

    // MARK: - iCloud-nicht-verfügbar Hinweis

    /// Wird angezeigt, wenn der Nutzer nicht in iCloud eingeloggt ist oder
    /// CloudKit aus anderem Grund nicht erreichbar ist.
    private var comingSoonBanner: some View {
        Section {
            VStack(spacing: 14) {
                Image(systemName: "icloud.slash")
                    .font(.system(size: 40))
                    .foregroundStyle(.orange.gradient)

                VStack(spacing: 6) {
                    Text(lt("iCloud nicht verfügbar"))
                        .font(.headline)
                    Text(lt("Melde dich in den iOS-Einstellungen mit deiner Apple ID an, um Freunde hinzuzufügen und Aktivitäten zu teilen. Dein persönlicher Code ist trotzdem schon bereit."))
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
    @State private var showCheerSheet = false

    private var commentReactions: [CheerReaction] {
        activity.reactions.filter { $0.text?.isEmpty == false }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                        Text(activity.presentableName)
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

                VStack(alignment: .trailing, spacing: 6) {
                    Text(activity.timestamp.relativeShort)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Button {
                        showCheerSheet = true
                    } label: {
                        Image(systemName: "face.smiling")
                            .font(.callout)
                            .foregroundStyle(Color.accentColor)
                            .padding(6)
                            .background(Color.accentColor.opacity(0.12))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(lt("Reagieren"))
                }
            }

            // Reactions ohne Text als kompakte Chips
            ReactionChipsView(reactions: activity.reactions)

            // Reactions mit Text als kleine Kommentar-Bubbles
            ForEach(commentReactions) { reaction in
                ReactionMessageView(reaction: reaction)
            }
        }
        .padding(.vertical, 2)
        .sheet(isPresented: $showCheerSheet) {
            CheerSheet(activity: activity)
        }
    }

    private var icon: String {
        switch activity.eventType {
        case .achievement:
            return "trophy.fill"
        case .meal:
            return "fork.knife"
        case .workout:
            return activity.workoutType?.systemImage ?? "figure.run"
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

// MARK: - Friend Row

private struct FriendRowView: View {
    let friend: FriendProfile

    var body: some View {
        HStack(spacing: 12) {
            UserAvatarView(
                size: 38,
                name: friend.displayName,
                photoData: nil,
                preset: friend.avatarPresetEnum,
                fallbackImage: nil,
                tryContactPhoto: true
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(friend.presentableName)
                    .font(.subheadline.weight(.semibold))
                Text(friend.code)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fontDesign(.monospaced)
            }

            Spacer()
        }
    }
}

// MARK: - Add Friend Sheet

struct AddFriendSheet: View {
    @Environment(CloudKitService.self) private var cloudKit
    @Environment(\.dismiss) private var dismiss

    /// Optional vorbelegter Code (z.B. via Deep Link aus iMessage).
    var prefilledCode: String? = nil

    @State private var code      = ""
    @State private var isAdding  = false
    @State private var errorMsg: String? = nil

    // Reciprocal-Share-Rückfrage nach erfolgreichem Hinzufügen
    @State private var pendingReciprocalCode: String? = nil
    @State private var pendingReciprocalName: String = ""
    @State private var showReciprocalPrompt = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 52))
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 16)

                VStack(spacing: 6) {
                    Text(lt("Freund hinzufügen"))
                        .font(.title2.weight(.bold))
                    Text(lt("Gib den 7-stelligen Code deines Freundes ein.\nBeispiel: ABC-123"))
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
                            Text(lt("Hinzufügen"))
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
                    Button(lt("Abbrechen")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .task {
            if let prefilledCode, code.isEmpty {
                code = normalizeIncomingCode(prefilledCode)
            }
        }
        .alert(lt("Status auch teilen?"), isPresented: $showReciprocalPrompt) {
            Button(lt("Ja, auch teilen")) {
                if let target = pendingReciprocalCode {
                    Task {
                        try? await cloudKit.offerReciprocalShare(toCode: target)
                        dismiss()
                    }
                } else {
                    dismiss()
                }
            }
            Button(lt("Nein, nur folgen"), role: .cancel) {
                dismiss()
            }
        } message: {
            Text(lf("Möchtest du deine Aktivitäten auch mit %@ teilen? Dann sieht %@ dich ebenfalls im Friends-Feed.",
                    pendingReciprocalName, pendingReciprocalName))
        }
    }

    private func normalizeIncomingCode(_ raw: String) -> String {
        let cleaned = raw.uppercased().filter { $0.isLetter || $0.isNumber }
        guard cleaned.count >= 6 else { return raw.uppercased() }
        return "\(cleaned.prefix(3))-\(cleaned.dropFirst(3).prefix(3))"
    }

    private func addFriend() async {
        isAdding = true
        errorMsg = nil
        do {
            try await cloudKit.addFriend(code: code)
            // Nach erfolgreichem Add: zugehörigen Friend aus der frisch
            // aktualisierten Liste finden und Reciprocal-Share-Dialog anzeigen.
            let normalized = code.uppercased()
            if let added = cloudKit.friends.first(where: { $0.code == normalized }) {
                pendingReciprocalCode = added.code
                pendingReciprocalName = added.displayName
                showReciprocalPrompt  = true
            } else {
                dismiss()
            }
        } catch {
            errorMsg = error.localizedDescription
        }
        isAdding = false
    }
}

// MARK: - Date Helper

/// Public extension — wird auch in FriendProfileView, ActivityDetailView,
/// DirectMessageView genutzt. Vorher private auf FriendsView.swift, jetzt
/// hier weil das logisch zum Friends-Modul gehört aber nicht mehr file-scoped.
extension Date {
    var relativeShort: String {
        let diff = Date().timeIntervalSince(self)
        if diff < 60 {
            return "jetzt"
        } else if diff < 3_600 {
            return "\(Int(diff / 60))m"
        } else if diff < 86_400 {
            return "\(Int(diff / 3_600))h"
        } else {
            return "\(Int(diff / 86_400))d"
        }
    }
}
