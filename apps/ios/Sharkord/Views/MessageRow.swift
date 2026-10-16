import SwiftUI

struct MessageRow: View {
    let message: Message
    let showsHeader: Bool
    var showsThreadLink = true
    let onLongPress: () -> Void
    let onDoubleTap: () -> Void
    var onSecondaryClick: (SecondaryClick) -> Void = { _ in }
    // the mac's bar over a hovered message, left off where the row has nowhere to send them
    var hoverActions: MessageHoverActions?

    @Environment(SessionStore.self) private var session
    @Environment(\.isShowingMessageActions) private var isShowingMessageActions
    @Environment(\.openThreadPanel) private var openThreadPanel

    @State private var isHovered = false

    private var author: PublicUser? {
        message.userId.flatMap { session.usersById[$0] }
    }

    private var authorName: String {
        author?.name ?? message.webhookName ?? message.pluginId ?? "Unknown"
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

                if message.id == session.settings?.onboardingMessageId {
                    Label("React to this message to accept the rules and see the rest of the server.", systemImage: "checkmark.seal.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }

                if showsThreadLink, let replyCount = message.replyCount, replyCount > 0 {
                    threadLink(replyCount: replyCount)
                        .buttonStyle(.plain)
                        // a long press on the link opens the actions sheet, and the finger lifting
                        // would otherwise also open the thread under it
                        .disabled(isShowingMessageActions)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.top, showsHeader ? 16 : 2)
        .background(isHovered ? Color.black.opacity(0.08) : .clear)
        // over the row's top right, discord's quick reactions, reply and the menu
        .overlay(alignment: .topTrailing) {
            if isHovered, let hoverActions {
                MessageHoverBar(actions: hoverActions)
                    .padding(.trailing, 16)
                    .offset(y: showsHeader ? -2 : -16)
            }
        }
        .onHover(perform: setHovered)
        .contentShape(.rect)
        .onTapGesture(count: 2, perform: onDoubleTap)
        // simultaneous so it also works over an attachment's own button, a voice message's play
        // button for one. the sheet opening cancels that button's tap
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.3).onEnded(longPressed))
        .onSecondaryClick(perform: onSecondaryClick)
    }

    // the mac's panel beside the chat, a page of its own everywhere else
    @ViewBuilder
    private func threadLink(replyCount: Int) -> some View {
        let label = Label(replyCount == 1 ? "1 reply" : "\(replyCount) replies", systemImage: "arrow.turn.down.right")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.blurple)

        if openThreadPanel != nil {
            Button(action: openThreadInPanel) {
                label
            }
        } else {
            NavigationLink(value: ThreadRoute(parent: message)) {
                label
            }
        }
    }

    private func openThreadInPanel() {
        openThreadPanel?(message)
    }

    private func setHovered(_ hovered: Bool) {
        guard hoverActions != nil, ProcessInfo.processInfo.isiOSAppOnMac else {
            return
        }

        isHovered = hovered
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

            if message.pluginId != nil || message.webhookName != nil {
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


struct MessageHoverActions {
    let onReact: (String) -> Void
    let onReply: () -> Void
    // where the menu should open, under the bar's more button
    let onMore: (SecondaryClick) -> Void
}

private struct MessageHoverBar: View {
    let actions: MessageHoverActions

    @State private var moreFrame = CGRect.zero

    var body: some View {
        HStack(spacing: 2) {
            ForEach(FrequentExpressions.emoji.prefix(3), id: \.self) { shortcode in
                Button {
                    actions.onReact(shortcode)
                } label: {
                    EmojiView(value: shortcode, size: 18)
                        .frame(width: 30, height: 30)
                        .contentShape(.rect)
                }
                .accessibilityLabel("React with \(shortcode)")
                .pointerTooltip(":\(shortcode):")
            }

            Theme.divider
                .frame(width: 1, height: 18)
                .padding(.horizontal, 2)

            Button(action: actions.onReply) {
                barIcon("arrowshape.turn.up.left")
            }
            .accessibilityLabel("Reply")
            .pointerTooltip("Reply")

            Button(action: showMore) {
                barIcon("ellipsis")
            }
            .accessibilityLabel("More")
            .pointerTooltip("More")
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { frame in
                moreFrame = frame
            }
        }
        .buttonStyle(.plain)
        .padding(3)
        .background(Theme.listBackground, in: .rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Theme.panelEdge, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
    }

    private func barIcon(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Theme.text)
            .frame(width: 30, height: 30)
            .contentShape(.rect)
    }

    // discord opens the menu to the left of the button, level with its top
    private func showMore() {
        actions.onMore(SecondaryClick(anchor: .topLeading, windowPoint: CGPoint(x: moreFrame.minX - 224, y: moreFrame.minY)))
    }
}
