import SwiftUI

struct MessageRow: View {
    let message: Message
    let showsHeader: Bool
    var showsThreadLink = true
    let onLongPress: () -> Void
    let onDoubleTap: () -> Void

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
        VStack(alignment: .leading, spacing: 2) {
            if message.replyToMessageId != nil {
                ReplyLine(preview: message.replyTo)
            }

            row
        }
    }

    private var row: some View {
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

                if let content = message.content, !content.isEmpty, !message.isMediaLinkOnly {
                    MessageContentView(html: content)
                }

                if let sticker = message.sticker {
                    AnimatedImage(url: session.address?.fileURL(sticker.file), maxPointSize: 160, contentMode: .scaleAspectFit)
                        .frame(width: 160, height: 160)
                        .accessibilityLabel(sticker.name)
                }

                ForEach(message.mediaImages, id: \.url) { media in
                    AnimatedImage(url: URL(string: media.url), maxPointSize: 300, contentMode: .scaleAspectFit, sizesToImage: true)
                        .frame(maxWidth: 280, maxHeight: 320, alignment: .leading)
                        .clipShape(.rect(cornerRadius: 8))
                }

                ForEach(message.linkPreviews, id: \.url) { preview in
                    LinkPreviewCard(preview: preview)
                }

                if message.editedAt != nil {
                    Text("(edited)")
                        .font(.caption2)
                        .foregroundStyle(Theme.muted)
                }

                if let poll = message.poll {
                    PollView(message: message, poll: poll)
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
        .onTapGesture(count: 2, perform: onDoubleTap)
        // simultaneous so it also works over an attachment's own button, a voice message's play
        // button for one. the sheet opening cancels that button's tap
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.4).onEnded(longPressed))
    }

    private func longPressed(_: Bool) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onLongPress()
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

// discord's line above a reply: who it answers and the start of what they said
private struct ReplyLine: View {
    let preview: ReplyPreview?

    @Environment(SessionStore.self) private var session

    private var author: PublicUser? {
        preview?.userId.flatMap { session.usersById[$0] }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.turn.up.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.muted)
                .scaleEffect(x: -1)
                .padding(.leading, 18)

            if let preview {
                AvatarView(user: author, size: 16)

                Text(author?.name ?? preview.pluginId ?? "Unknown")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(hex: session.roleColor(for: author) ?? "#F2F3F5"))

                Text(HTMLText.plainText(from: preview.content ?? "").replacingOccurrences(of: "\n", with: " "))
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            } else {
                Text("Original message was deleted")
                    .font(.caption.italic())
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.leading, 12)
    }
}

