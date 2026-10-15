import SwiftUI

struct ChatScreen: View {
    let channelId: Int

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var isPinsPresented = false

    private var store: ChannelMessagesStore {
        session.messages(for: channelId)
    }

    private var channel: Channel? {
        session.channel(channelId)
    }

    private var partner: PublicUser? {
        session.directMessagePartner(for: channelId)
    }

    private var title: String {
        if channel?.isDm == true {
            return session.conversationTitle(for: channelId)
        }

        return channel?.name ?? ""
    }

    private var canUpload: Bool {
        guard let settings = session.settings, settings.storageUploadEnabled else {
            return false
        }

        return channel?.isDm != true || settings.storageFileSharingInDirectMessages
    }

    var body: some View {
        MessageListView(store: store) {
            ChannelWelcome(title: title, isDirectMessage: channel?.isDm == true, partner: partner)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if session.can("SEND_MESSAGES", inChannel: channelId) {
                ComposerView(
                    placeholder: channel?.isDm == true ? "Message @\(title)" : "Message #\(title)",
                    canUpload: canUpload,
                    store: store
                )
            } else {
                ReadOnlyComposer()
            }
        }
        // a panel in the keyboard's place never rides the keyboard: the two trade places, or the
        // keyboard comes up over the panel for its search, see AttachPanelModel
        .ignoresSafeArea(store.attachPanel.isHandingOff || store.attachPanel.isOpen ? .keyboard : [], edges: .bottom)
        .safeAreaInset(edge: .top, spacing: 0) {
            if session.showsReconnectingBanner {
                ReconnectingBanner()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.chatBackground, for: .navigationBar)
        .toolbarBackgroundVisibility(.visible, for: .navigationBar)
        .toolbarVisibility(.hidden, for: .tabBar)
        .toolbar {
            PlainToolbarItem(placement: .topBarLeading) {
                NavigationLink(value: ChannelInfoRoute(channelId: channelId)) {
                    ChatTitle(
                        title: title,
                        partner: partner,
                        isDirectMessage: channel?.isDm == true,
                        group: session.group(for: channelId)
                    )
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded(dismissKeyboard))
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button(action: showPins) {
                    Image(systemName: "pin")
                        .foregroundStyle(Theme.text)
                }
                .accessibilityLabel("Pinned Messages")
            }

            ToolbarItem(placement: .topBarTrailing) {
                SearchLink(route: SearchRoute(channelId: channelId)) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Theme.text)
                }
                .simultaneousGesture(TapGesture().onEnded(dismissKeyboard))
                .accessibilityLabel("Search")
            }
        }
        .sheet(isPresented: $isPinsPresented) {
            PinnedMessagesSheet(channelId: channelId)
        }
        .task {
            session.rememberChannel(channelId)
            session.shownChannelId = channelId
            store.isVisible = true

            let unreadCount = session.unreadCounts[channelId, default: 0]

            await store.loadIfNeeded()
            store.setUnreadMarker(count: unreadCount)
            await session.markAsRead(channelId)
        }
        .onDisappear {
            store.isVisible = false
        }
        // a group left, or a channel deleted, takes its chat with it back to the list
        .onChange(of: channel == nil) { _, isGone in
            if isGone {
                dismiss()
            }
        }
    }

    private func showPins() {
        dismissKeyboard()
        isPinsPresented = true
    }

    // before another screen goes over the chat: swiftui gives a field its focus back when the
    // chat shows again, so a keyboard still up on leaving would come back unasked
    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// ios 26 wraps every toolbar item in a glass capsule, which makes a plain title look like a
// button that does nothing
private struct PlainToolbarItem<Content: View>: ToolbarContent {
    let placement: ToolbarItemPlacement
    @ViewBuilder let content: Content

    var body: some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: placement) {
                content
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: placement) {
                content
            }
        }
    }
}

// discord's header: the name with a chevron, and who is around under it
private struct ChatTitle: View {
    let title: String
    let partner: PublicUser?
    let isDirectMessage: Bool
    var group: GroupInfo?

    @Environment(SessionStore.self) private var session

    private var subtitle: String {
        if let group {
            return "\(group.memberIds.count + 1) Members"
        }

        if isDirectMessage {
            switch partner?.status {
            case .online:
                return "Online"
            case .idle:
                return "Idle"
            case .dnd:
                return "Do Not Disturb"
            case .offline, nil:
                return "Offline"
            }
        }

        return "\(session.onlineCount) Online"
    }

    private var isOnline: Bool {
        isDirectMessage ? partner?.status == .online : session.onlineCount > 0
    }

    // discord's: the person's own status line under their name, their presence already sits on
    // the avatar beside it
    private var customStatus: String? {
        guard isDirectMessage, group == nil, let text = partner?.customStatus, !text.isEmpty else {
            return nil
        }

        return text
    }

    var body: some View {
        HStack(spacing: 8) {
            if group != nil {
                GroupAvatar(size: 30)
            } else if isDirectMessage {
                AvatarView(user: partner, size: 30, showsStatus: true)
            }

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    if !isDirectMessage {
                        Image(systemName: "number")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.muted)
                    }

                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Theme.header)
                        .lineLimit(1)

                    Image(systemName: "chevron.right")
                        .font(.caption2.bold())
                        .foregroundStyle(Theme.muted)
                }

                HStack(spacing: 4) {
                    if let customStatus {
                        Image(systemName: "bubble.left.fill")
                            .font(.caption2)
                            .foregroundStyle(Theme.muted)

                        Text(customStatus)
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    } else {
                        // a direct message's presence is already on the avatar beside it
                        if !isDirectMessage || group != nil {
                            Circle()
                                .fill(isOnline ? Theme.green : Theme.muted)
                                .frame(width: 7, height: 7)
                        }

                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
        }
        .fixedSize()
    }
}

private struct ChannelWelcome: View {
    let title: String
    let isDirectMessage: Bool
    let partner: PublicUser?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isDirectMessage {
                AvatarView(user: partner, size: 72)
            } else {
                Image(systemName: "number")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(Theme.header)
                    .frame(width: 68, height: 68)
                    .background(Theme.hover, in: .circle)
            }

            Text(isDirectMessage ? title : "Welcome to #\(title)!")
                .font(.title.bold())
                .foregroundStyle(Theme.header)

            Text(isDirectMessage
                ? "This is the beginning of your direct message history with \(title)."
                : "This is the start of the #\(title) channel.")
                .foregroundStyle(Theme.muted)
        }
        .padding(16)
        .padding(.top, 24)
    }
}

// where the message box would be in a channel this account can read but not post in
private struct ReadOnlyComposer: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")

            Text("You do not have permission to send messages in this channel.")
                .lineLimit(2)
        }
        .font(.subheadline)
        .foregroundStyle(Theme.muted)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(Theme.inputBackground, in: .rect(cornerRadius: 20))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.chatBackground.ignoresSafeArea())
    }
}
