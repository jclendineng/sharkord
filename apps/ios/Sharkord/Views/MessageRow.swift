import SwiftUI

struct MessageRow: View {
    let message: Message
    let showsHeader: Bool
    var showsThreadLink = true
    let onLongPress: () -> Void

    @Environment(SessionStore.self) private var session

    private var author: PublicUser? {
        message.userId.flatMap { session.usersById[$0] }
    }

    private var authorName: String {
        author?.name ?? message.pluginId ?? "Unknown"
    }

    private var nameColor: Color {
        session.roleColor(for: author).map { Color(hex: $0) } ?? Theme.header
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if showsHeader {
                AvatarView(user: author, size: 40)
            } else {
                Color.clear.frame(width: 40, height: 1)
            }

            VStack(alignment: .leading, spacing: 4) {
                if showsHeader {
                    header
                }

                if let content = message.content, !content.isEmpty {
                    MessageContentView(html: content)
                }

                if message.editedAt != nil {
                    Text("(edited)")
                        .font(.caption2)
                        .foregroundStyle(Theme.muted)
                }

                ForEach(message.files) { file in
                    AttachmentView(file: file)
                }

                if !message.reactions.isEmpty {
                    ReactionsView(message: message)
                }

                if showsThreadLink, let replyCount = message.replyCount, replyCount > 0 {
                    NavigationLink(value: ThreadRoute(parent: message)) {
                        Label(replyCount == 1 ? "1 reply" : "\(replyCount) replies", systemImage: "arrow.turn.down.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.blurple)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.top, showsHeader ? 16 : 2)
        .contentShape(.rect)
        .onLongPressGesture(perform: onLongPress)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(authorName)
                .font(.body.weight(.semibold))
                .foregroundStyle(nameColor)
                .lineLimit(1)

            if message.pluginId != nil {
                Text("APP")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Theme.blurple, in: .rect(cornerRadius: 3))
            }

            Text(MessageDate.timestamp(message.createdDate))
                .font(.caption)
                .foregroundStyle(Theme.muted)
        }
    }
}

struct DaySeparator: View {
    let date: Date

    var body: some View {
        HStack(spacing: 8) {
            line

            Text(MessageDate.day(date))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.muted)
                .fixedSize()

            line
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 4)
    }

    private var line: some View {
        Theme.divider.frame(height: 1)
    }
}
