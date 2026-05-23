import SwiftUI

/// Detail-Ansicht einer Activity (eigene oder von Freund). Zeigt die Activity
/// als „Original-Post" oben und alle Reactions/Kommentare chronologisch
/// darunter als Threading-Konversation. Reaktion senden via Bottom-Bar.
struct ActivityDetailView: View {
    @Environment(CloudKitService.self) private var cloudKit
    @Environment(UserSettings.self) private var settings

    let activity: FriendActivity

    @State private var draftText: String = ""
    @State private var selectedEmoji: String = "👍"
    @State private var isSending = false
    @State private var showEmojiPicker = false

    /// Live-Activity aus dem Feed (für aktuelle Reactions). Fallback: die
    /// statische Activity die wir reingereicht bekommen haben.
    private var live: FriendActivity {
        cloudKit.feed.first(where: { $0.id == activity.id }) ?? activity
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                originalPost
                Divider().padding(.vertical, 4)
                commentsSection
            }
            .padding(.horizontal)
            .padding(.top)
        }
        .safeAreaInset(edge: .bottom) {
            composer
                .background(.bar)
        }
        .navigationTitle(lt("Aktivität"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await cloudKit.refreshFeed()
        }
    }

    // MARK: - Original-Post

    private var originalPost: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(iconColor.opacity(0.15))
                    Image(systemName: icon)
                        .foregroundStyle(iconColor)
                        .font(.system(size: 18, weight: .semibold))
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(live.presentableName)
                        .font(.subheadline.weight(.semibold))
                    Text(live.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Text(live.eventTitle)
                .font(.headline)
            Text(live.eventDetail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Comments / Reactions Threading

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(live.reactions.isEmpty
                     ? lt("Noch keine Reaktionen")
                     : lf("%d Reaktionen", live.reactions.count))
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }

            ForEach(live.reactions) { reaction in
                reactionBubble(reaction)
            }
        }
    }

    @ViewBuilder
    private func reactionBubble(_ r: CheerReaction) -> some View {
        let isMine = r.fromCode == cloudKit.myFriendCode
        HStack(alignment: .top, spacing: 8) {
            if isMine { Spacer(minLength: 24) }
            VStack(alignment: isMine ? .trailing : .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if !isMine {
                        Text(r.fromName)
                            .font(.caption.weight(.semibold))
                    }
                    Text(r.emoji).font(.title3)
                    Text(r.timestamp.relativeShort)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let text = r.text, !text.isEmpty {
                    Text(text)
                        .font(.subheadline)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(isMine ? Color.accentColor.opacity(0.2) : Color(.tertiarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            if !isMine { Spacer(minLength: 24) }
        }
        .contextMenu {
            if isMine {
                Button(role: .destructive) {
                    Task {
                        await cloudKit.deleteCheer(reactionID: r.id, activityID: live.id)
                    }
                } label: {
                    Label(lt("Löschen"), systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Composer (Emoji + Text)

    private var composer: some View {
        VStack(spacing: 6) {
            // Emoji-Picker
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(CheerEmoji.options, id: \.self) { emoji in
                        Button {
                            selectedEmoji = emoji
                        } label: {
                            Text(emoji)
                                .font(.title3)
                                .padding(8)
                                .background(selectedEmoji == emoji ? Color.accentColor.opacity(0.25) : Color.clear)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }

            HStack(spacing: 8) {
                TextField(lt("Kommentar (optional)"), text: $draftText, axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.send)
                    .onSubmit { send() }

                Button {
                    send()
                } label: {
                    if isSending {
                        ProgressView()
                    } else {
                        Image(systemName: "paperplane.fill")
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(Color.accentColor, in: Circle())
                    }
                }
                .disabled(isSending)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .padding(.top, 6)
    }

    private func send() {
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        isSending = true
        let textOptional: String? = text.isEmpty ? nil : text
        Task {
            try? await cloudKit.sendCheer(
                to: live.id,
                emoji: selectedEmoji,
                text: textOptional
            )
            await MainActor.run {
                draftText = ""
                isSending = false
            }
        }
    }

    private var icon: String {
        switch live.eventType {
        case .achievement: return "trophy.fill"
        case .meal:        return "fork.knife"
        case .workout:     return live.workoutType?.systemImage ?? "figure.run"
        }
    }
    private var iconColor: Color {
        switch live.eventType {
        case .achievement: return .yellow
        case .meal:        return .orange
        case .workout:     return .blue
        }
    }
}
