import SwiftUI

// discord's threads list under the mac's top bar: the channel's threads, the one replied to
// last first, each opening in the panel beside the chat. messages.getThreads
struct ThreadsListPanel: View {
    let channelId: Int
    let onOpen: (Message) -> Void

    @Environment(SessionStore.self) private var session

    @State private var threads: [Message]?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            Text("Threads")
                .font(.headline)
                .foregroundStyle(Theme.header)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Theme.divider
                .frame(height: 1)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if let threads {
                        if threads.isEmpty {
                            ContentUnavailableView(
                                "There are no threads",
                                systemImage: "bubble.left.and.text.bubble.right",
                                description: Text("Right click a message and choose Open Thread to start one.")
                            )
                            .padding(.top, 40)
                        } else {
                            ForEach(threads) { thread in
                                ThreadListRow(thread: thread, onOpen: { onOpen(thread) })
                            }
                        }
                    } else if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(Theme.red)
                            .padding(18)
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }
                }
                .padding(8)
            }
        }
        .background(Theme.deepBackground)
        .task {
            await load()
        }
    }

    // a server from before the list answers that it has no such route, which says nothing useful
    private func load() async {
        do {
            threads = try await session.request("messages.getThreads", ["channelId": channelId])
        } catch {
            errorMessage = "Couldn't load threads. The server may need updating to list them."
        }
    }
}

private struct ThreadListRow: View {
    let thread: Message
    let onOpen: () -> Void

    @Environment(SessionStore.self) private var session

    private var author: PublicUser? {
        thread.userId.flatMap { session.usersById[$0] }
    }

    private var text: String {
        HTMLText.plainText(from: thread.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var replies: String {
        let count = thread.replyCount ?? 0

        return count == 1 ? "1 reply" : "\(count) replies"
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 10) {
                AvatarView(user: author, size: 32)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(author?.name ?? "Unknown")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(hex: session.roleColor(for: author) ?? "#F2F3F5"))

                        Text(MessageDate.timestamp(thread.createdDate))
                            .font(.caption2)
                            .foregroundStyle(Theme.muted)
                    }
                    .lineLimit(1)

                    if !text.isEmpty {
                        Text(text)
                            .font(.subheadline)
                            .foregroundStyle(Theme.text)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }

                    Label(replies, systemImage: "arrow.turn.down.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.blurple)
                }

                Spacer(minLength: 0)
            }
            .padding(8)
            .hoverHighlight(cornerRadius: 8)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
