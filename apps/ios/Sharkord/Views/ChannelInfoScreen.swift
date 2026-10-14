import SwiftUI

// discord's channel screen, opened from the name at the top of the chat: search, notification
// settings and the channel's settings up top, then its members, media, pins, links and files
struct ChannelInfoScreen: View {
    let channelId: Int

    @Environment(SessionStore.self) private var session
    @Environment(ServerListStore.self) private var servers
    @Environment(\.dismiss) private var dismiss

    @State private var model: SearchHomeModel?
    @State private var isInvitePresented = false
    @State private var isNotificationsPresented = false
    @State private var profileUser: PublicUser?

    private static let tabs: [SearchTab] = [.members, .media, .pins, .links, .files]

    private var channel: Channel? {
        session.channel(channelId)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let channel {
                header(channel)
            }

            if let model {
                SearchHome(
                    model: model,
                    onOpenChannel: openChannel,
                    onOpenMessage: openMessage,
                    onOpenUser: showProfile,
                    only: Self.tabs,
                    onInvite: showInvite
                )
            }
        }
        .background(Theme.deepBackground)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.deepBackground, for: .navigationBar)
        .toolbarBackgroundVisibility(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: SearchRoute(channelId: channelId)) {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel("Search")
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("Notification Settings", systemImage: "bell.fill", action: showNotifications)
            }

            if session.can(.manageChannels), let channel {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        ChannelEditor(channel: channel)
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                    .accessibilityLabel("Channel Settings")
                }
            }
        }
        .sheet(isPresented: $isInvitePresented) {
            InviteSheet()
        }
        .sheet(isPresented: $isNotificationsPresented) {
            if let channel {
                ChannelNotificationsSheet(channel: channel)
            }
        }
        .sheet(item: $profileUser) { user in
            MemberProfileSheet(user: user, onMessage: { openDirectMessage(with: user) })
        }
        .onAppear(perform: makeModel)
    }

    private func header(_ channel: Channel) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "number")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.header)
                .frame(width: 46, height: 46)
                .background(Theme.listBackground, in: .rect(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 2) {
                Text(channel.name)
                    .font(.title3.bold())
                    .foregroundStyle(Theme.header)
                    .lineLimit(1)

                Text("Text Channel")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    // its own model rather than the search's, so the tab picked here never moves search's
    private func makeModel() {
        guard model == nil else {
            return
        }

        let model = SearchHomeModel(scope: channel)

        model.tab = .members
        self.model = model
    }

    // a pin or a link in this channel goes back to the chat it came from
    private func openChannel(_ id: Int) {
        if id == channelId {
            dismiss()
        } else {
            servers.open(channelId: id, in: session)
        }
    }

    // in this channel the chat this screen was opened from takes it, when it shows again
    private func openMessage(channelId id: Int, messageId: Int) {
        if id == channelId {
            session.messages(for: id).pendingJumpMessageId = messageId
            dismiss()
        } else {
            servers.open(channelId: id, messageId: messageId, in: session)
        }
    }

    private func openDirectMessage(with user: PublicUser) {
        guard user.id != session.ownUserId else {
            return
        }

        Task {
            do {
                let channelId = try await session.openDirectMessage(with: user.id)

                servers.open(channelId: channelId, in: session)
            } catch {
                session.showError(error)
            }
        }
    }

    private func showProfile(_ user: PublicUser) {
        profileUser = user
    }

    private func showInvite() {
        isInvitePresented = true
    }

    private func showNotifications() {
        isNotificationsPresented = true
    }
}
