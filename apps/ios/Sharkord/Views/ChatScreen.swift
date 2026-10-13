import SwiftUI

struct ChatScreen: View {
    let channelId: Int

    @Environment(SessionStore.self) private var session

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
            return partner?.name ?? "Direct Message"
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
            ComposerView(
                placeholder: channel?.isDm == true ? "Message @\(title)" : "Message #\(title)",
                canUpload: canUpload,
                store: store
            )
        }
        // while the keyboard and the attachment panel trade places, see AttachPanelModel
        .ignoresSafeArea(store.attachPanel.isHandingOff ? .keyboard : [], edges: .bottom)
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
                ChatTitle(title: title, partner: partner, isDirectMessage: channel?.isDm == true)
            }

            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: SearchRoute()) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Theme.text)
                }
            }
        }
        .task {
            session.rememberChannel(channelId)
            store.isVisible = true
            await store.loadIfNeeded()
            await session.markAsRead(channelId)
        }
        .onDisappear {
            store.isVisible = false
        }
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

    @Environment(SessionStore.self) private var session

    private var subtitle: String {
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

    var body: some View {
        HStack(spacing: 8) {
            if isDirectMessage {
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
                    Circle()
                        .fill(isOnline ? Theme.green : Theme.muted)
                        .frame(width: 7, height: 7)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
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
