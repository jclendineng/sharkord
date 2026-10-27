import SwiftUI

struct MessageRow: View {
    let message: Message
    let showsHeader: Bool
    // the next message right under this one, with only the small gap between them
    var isFollowedClosely = false
    var showsThreadLink = true
    // its menu is open, which keeps it lit on a mac once the pointer has moved onto the menu
    var isShowingActions = false
    let onLongPress: () -> Void
    let onDoubleTap: () -> Void
    var onSecondaryClick: (SecondaryClick) -> Void = { _ in }
    // the mac's bar over a hovered message, left off where the row has nowhere to send them
    var hoverActions: MessageHoverActions?

    @Environment(SessionStore.self) private var session
    @Environment(ServerListStore.self) private var servers
    @Environment(\.isShowingMessageActions) private var isShowingMessageActions
    @Environment(\.openThreadPanel) private var openThreadPanel

    @State private var isHovered = false
    @State private var isProfilePresented = false
    // the finger on the row, lit as it is held so the press has something to show for it
    @State private var isFingerDown = false

    // let go the moment the menu takes over from the press
    private var isPressed: Bool {
        isFingerDown && !isShowingMessageActions
    }

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
        // a reply's line is part of the message: the gap goes above it, not between it and its
        // message, and the press card takes it in. otherwise it sat flush against the message
        // before, under that one's jump glow, and its own press card cut through it
        VStack(alignment: .leading, spacing: 2) {
            if message.replyToMessageId != nil {
                ReplyLine(preview: message.replyTo)
            }

            row
        }
        // the press: a rounded card a few points past the message, inset from the screen's edges,
        // rather than a band taking in the gap above a header. between two lines of one stretch it
        // only reaches into the small gap, past that it covered the edge of the line next to it
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.hover)
                .padding(.horizontal, 6)
                .padding(.top, showsHeader ? -6 : -2)
                .padding(.bottom, isFollowedClosely ? -2 : -6)
                .opacity(isPressed ? 1 : 0)
        }
        .animation(.easeOut(duration: isPressed ? 0.08 : 0.2), value: isPressed)
        .padding(.top, showsHeader ? MessageRowBand.headerGap : MessageRowBand.lineGap)
        .background {
            if isHovered || (isShowingActions && Platform.isMac) {
                Rectangle()
                    .fill(Color.black.opacity(0.08))
                    .rowBand(hasHeader: showsHeader, isFollowedClosely: isFollowedClosely)
            }
        }
        // over the message's top right, discord's quick reactions, reply and the menu
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
        #if os(iOS)
        .gesture(PressTracker(isPressed: $isFingerDown))
        #endif
        .onSecondaryClick(perform: onSecondaryClick)
    }

    private var row: some View {
        HStack(alignment: .top, spacing: 12) {
            if showsHeader {
                Button(action: showProfile) {
                    AvatarView(user: author, size: 40)
                }
                .buttonStyle(.plain)
                .disabled(author == nil)
                .modifier(AuthorProfilePresentation(user: author, isPresented: $isProfilePresented))
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
                    AnimatedImage(url: session.address?.fileURL(sticker.file), maxPointSize: 160, contentMode: .fit)
                        .frame(width: 160, height: 160)
                        .accessibilityLabel(sticker.name)
                }

                ForEach(message.mediaImages, id: \.url) { media in
                    AnimatedImage(url: URL(string: media.url), maxPointSize: 300, contentMode: .fit, sizesToImage: true)
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
                        // a long press on the link opens the actions sheet, and the finger lifting
                        // would otherwise also open the thread under it. switched off rather than
                        // ignored, which cancels that lift, in a style that does not dim it
                        .buttonStyle(UndimmedButtonStyle())
                        .disabled(isShowingMessageActions)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
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

    // the popover hangs off the avatar, the name opens the same one. the chat's inbox or pins
    // go away for it, which a click on a button never told
    private func showProfile() {
        servers.chatDropdownDismissals += 1
        isProfilePresented = true
    }

    private func setHovered(_ hovered: Bool) {
        guard hoverActions != nil, Platform.isMac else {
            return
        }

        isHovered = hovered
    }

    private func longPressed(_: Bool) {
        Haptics.medium()
        onLongPress()
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Button(action: showProfile) {
                Text(authorName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(nameColor)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .disabled(author == nil)

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

// a band behind a message, the mac's hover and a jump's highlight, centred on its text. a row
// carries its own room above the text, more over a name than over a follow-up line, and none
// below, where the next row's begins: drawn over the row as it is, the band sat high
enum MessageRowBand {
    static let headerGap: CGFloat = 16
    static let lineGap: CGFloat = 2

    // as far past the text above as below. right over the next row it only takes half that
    // row's gap, to stay off its text
    static func reach(hasHeader: Bool, isFollowedClosely: Bool) -> CGFloat {
        if isFollowedClosely {
            return hasHeader ? 2 : 1
        }

        return hasHeader ? 4 : 2
    }
}

extension View {
    func rowBand(hasHeader: Bool, isFollowedClosely: Bool) -> some View {
        let gap = hasHeader ? MessageRowBand.headerGap : MessageRowBand.lineGap
        let reach = MessageRowBand.reach(hasHeader: hasHeader, isFollowedClosely: isFollowedClosely)

        return padding(.top, gap - reach)
            .padding(.bottom, -reach)
    }
}

// the author's profile from their avatar or name: beside the avatar on a mac or an ipad, as the
// member list's is, a sheet on a phone. an app or a webhook has no profile to show
private struct AuthorProfilePresentation: ViewModifier {
    let user: PublicUser?
    @Binding var isPresented: Bool

    @Environment(SessionStore.self) private var session
    @Environment(ServerListStore.self) private var servers

    func body(content: Content) -> some View {
        if let user {
            if Platform.isPhone {
                content
                    .sheet(isPresented: $isPresented) {
                        profile(user)
                            .appSheet(addsClose: true)
                    }
            } else {
                content
                    .popover(isPresented: $isPresented, opensAwayFrom: .leading) {
                        profile(user)
                            .frame(width: 340)
                            .fixedSize(horizontal: false, vertical: true)
                            .presentationCompactAdaptation(.popover)
                    }
            }
        } else {
            content
        }
    }

    // handed the stores by hand: on a mac a presentation is worked out before it inherits
    private func profile(_ user: PublicUser) -> some View {
        MemberProfileSheet(user: user, onMessage: { openDirectMessage(with: user) })
            .environment(session)
            .environment(servers)
    }

    private func openDirectMessage(with user: PublicUser) {
        isPresented = false

        Task {
            guard let channelId = try? await session.openDirectMessage(with: user.id) else {
                return
            }

            servers.open(channelId: channelId, in: session)
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

// plain, but the same while switched off: the system's dimmed the reply links for the whole time a
// message's menu was up and a moment after
private struct UndimmedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

// whether a finger rests on the row, from uikit's own recogniser alongside every other one. a
// swiftui gesture tracking it shared the touch with the list, and a menu opening part way through
// a press left it holding on, the messages no longer scrolling. this one never claims the touch
// and lets go as soon as the finger moves, so a scroll always wins
#if os(iOS)
private struct PressTracker: UIGestureRecognizerRepresentable {
    @Binding var isPressed: Bool

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()

        recognizer.minimumPressDuration = 0.05
        recognizer.allowableMovement = 10
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesEnded = false
        recognizer.delegate = context.coordinator

        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .began:
            isPressed = true
        case .ended, .cancelled, .failed:
            isPressed = false
        default:
            break
        }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
#endif
