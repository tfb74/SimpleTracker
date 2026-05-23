import SwiftUI

/// Schlankes Sheet zum Anfeuern: Emoji-Auswahl + optional kurzer Text.
/// Bewusst auf Compact-Detent — soll sich anfühlen wie eine kurze Reaktion,
/// nicht wie das Verfassen einer Nachricht.
struct CheerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CloudKitService.self) private var cloudKit

    let activity: FriendActivity

    @State private var selectedEmoji: String = CheerEmoji.motivating.first ?? "👍"
    @State private var text: String = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    /// Vorschläge für kurze Texte je nach Auswahl. Tippt der User auf einen
    /// Chip, wird der Text übernommen und das Sheet kann direkt abgeschickt werden.
    private var textSuggestions: [String] {
        if CheerEmoji.teasing.contains(selectedEmoji) {
            return ["Mid.", "Cap.", lt("Schneckenpace"), lt("Couch ruft"), lt("War das alles?")]
        } else {
            return ["Beast!", lt("Krass!"), "Banger!", "GG", lt("Respekt!")]
        }
    }

    private var remainingChars: Int {
        max(0, CheerEmoji.maxTextLength - text.count)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                // Empfänger-Headline
                VStack(spacing: 4) {
                    Text(lf("Reagieren auf %@", activity.presentableName))
                        .font(.headline)
                    Text(activity.eventTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)

                // Emoji-Picker — zwei Kategorien
                VStack(spacing: 12) {
                    emojiRow(label: "Hype",  emojis: CheerEmoji.motivating)
                    emojiRow(label: "Roast", emojis: CheerEmoji.teasing)
                }
                .padding(.horizontal, 8)

                // Vorschlags-Chips passend zur Tonart
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(textSuggestions, id: \.self) { suggestion in
                            Button {
                                text = suggestion
                                UISelectionFeedbackGenerator().selectionChanged()
                            } label: {
                                Text(suggestion)
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule().fill(Color.accentColor.opacity(0.12))
                                    )
                                    .foregroundStyle(Color.accentColor)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                // Text-Input
                VStack(alignment: .leading, spacing: 6) {
                    TextField(lt("Kurzer Kommentar (optional)"), text: $text, axis: .vertical)
                        .lineLimit(2...3)
                        .padding(10)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .onChange(of: text) { _, new in
                            if new.count > CheerEmoji.maxTextLength {
                                text = String(new.prefix(CheerEmoji.maxTextLength))
                            }
                        }
                    HStack {
                        Spacer()
                        Text(lf("%d Zeichen übrig", remainingChars))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                Spacer(minLength: 0)

                Button {
                    Task { await send() }
                } label: {
                    Group {
                        if isSending {
                            ProgressView().tint(.white)
                        } else {
                            HStack(spacing: 6) {
                                Text(selectedEmoji).font(.title3)
                                Text(lt("Senden")).font(.headline)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSending)
                .padding(.horizontal)
                .padding(.bottom, 8)
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
    }

    /// Zeile von Emoji-Buttons mit Sektions-Label.
    private func emojiRow(label: String, emojis: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 4)

            HStack(spacing: 8) {
                ForEach(emojis, id: \.self) { e in
                    Button {
                        selectedEmoji = e
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        Text(e)
                            .font(.system(size: 26))
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .fill(selectedEmoji == e
                                          ? Color.accentColor.opacity(0.18)
                                          : Color(.secondarySystemBackground))
                            )
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        selectedEmoji == e ? Color.accentColor : .clear,
                                        lineWidth: 2
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func send() async {
        isSending = true
        errorMessage = nil
        do {
            try await cloudKit.sendCheer(
                to: activity.id,
                emoji: selectedEmoji,
                text: text.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSending = false
    }
}

// MARK: - Reactions-Anzeige unter einer Aktivität im Feed

struct ReactionChipsView: View {
    let reactions: [CheerReaction]

    var body: some View {
        if !reactions.isEmpty {
            HStack(spacing: 6) {
                ForEach(reactions.prefix(4)) { r in
                    HStack(spacing: 3) {
                        Text(r.emoji).font(.caption)
                        Text(r.fromName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.10))
                    .clipShape(Capsule())
                }
                if reactions.count > 4 {
                    Text("+\(reactions.count - 4)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Zeigt eine ausgewählte Reaktion mit Text — z.B. wenn jemand kommentiert hat.
struct ReactionMessageView: View {
    let reaction: CheerReaction

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(reaction.emoji)
                .font(.callout)
            VStack(alignment: .leading, spacing: 1) {
                Text(reaction.fromName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let text = reaction.text, !text.isEmpty {
                    Text(text)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
