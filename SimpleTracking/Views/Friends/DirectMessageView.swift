import SwiftUI

/// 1:1-Chat-View zwischen User und einem Friend. Messages werden über
/// CloudKit-Public-DB transportiert — keine APNs-Server nötig, Apple
/// liefert Push via Subscription.
struct DirectMessageView: View {
    @Environment(CloudKitService.self) private var cloudKit
    @Environment(\.dismiss) private var dismiss

    let peer: FriendProfile

    @State private var draft: String = ""
    @State private var isSending = false

    private var messages: [DirectMessage] {
        cloudKit.conversation(with: peer.code)
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(messages) { msg in
                            MessageBubble(message: msg, myCode: cloudKit.myFriendCode)
                                .id(msg.id)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                .onAppear {
                    if let last = messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                composer
                    .background(.bar)
            }
            .navigationTitle(peer.presentableName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(lt("Schließen")) { dismiss() }
                }
            }
            .task {
                await cloudKit.refreshMessages()
                await cloudKit.markMessagesRead(from: peer.code)
            }
        }
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField(lt("Nachricht…"), text: $draft, axis: .vertical)
                .lineLimit(1...4)
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
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSending = true
        Task {
            try? await cloudKit.sendMessage(to: peer.code, text: text)
            await MainActor.run {
                draft = ""
                isSending = false
            }
        }
    }
}

private struct MessageBubble: View {
    let message: DirectMessage
    let myCode: String

    private var isMine: Bool { message.fromCode == myCode }

    var body: some View {
        HStack {
            if isMine { Spacer(minLength: 40) }
            VStack(alignment: isMine ? .trailing : .leading, spacing: 2) {
                Text(message.text)
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isMine ? Color.accentColor : Color(.secondarySystemBackground))
                    .foregroundStyle(isMine ? Color.white : Color.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                HStack(spacing: 4) {
                    Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if isMine, message.readAt != nil {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if !isMine { Spacer(minLength: 40) }
        }
    }
}
