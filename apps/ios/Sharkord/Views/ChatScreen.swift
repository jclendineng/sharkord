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
        .safeAreaInset(edge: .top, spacing: 0) {
            if session.phase == .reconnecting {
                ReconnectingBanner()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.chatBackground, for: .navigationBar)
        .toolbarBackgroundVisibility(.visible, for: .navigationBar)
        .toolbarVisibility(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ChatTitle(title: title, partner: partner, isDirectMessage: channel?.isDm == true)
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

private struct ChatTitle: View {
    let title: String
    let partner: PublicUser?
    let isDirectMessage: Bool

    var body: some View {
        HStack(spacing: 6) {
            if isDirectMessage {
                AvatarView(user: partner, size: 24, showsStatus: true)
            } else {
                Image(systemName: "number")
                    .foregroundStyle(Theme.muted)
            }

            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.header)
                .lineLimit(1)
        }
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
