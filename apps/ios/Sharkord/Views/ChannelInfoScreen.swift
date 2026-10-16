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
    @State private var isAddingToGroup = false
    @State private var isRenamingGroup = false
    @State private var isConfirmingLeave = false
    @State private var groupName = ""

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
                    onInvite: inviteAction
                )
            }
        }
        .background(Theme.deepBackground)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.deepBackground, for: .navigationBar)
        .toolbarBackgroundVisibility(.visible, for: .navigationBar)
        .escapeGoesBack()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SearchLink(route: SearchRoute(channelId: channelId)) {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel("Search")
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("Notification Settings", systemImage: "bell.fill", action: showNotifications)
            }

            if let group {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Add Friends", systemImage: "person.badge.plus", action: showAddToGroup)
                            .disabled(group.memberIds.count + 1 >= GroupLimits.maxMembers)
                        Button("Rename Group", systemImage: "pencil", action: showRename)
                        Button("Leave Group", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive, action: confirmLeave)
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("Group Options")
                }
            }

            if session.can(.manageChannels), let channel, !channel.isDm {
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
        // handed over by hand: a sheet opened from the toolbar on a mac does not inherit them
        .sheet(isPresented: $isInvitePresented) {
            InviteSheet()
                .environment(session)
                .environment(servers)
                .appSheet()
        }
        .sheet(isPresented: $isNotificationsPresented) {
            if let channel {
                ChannelNotificationsSheet(channel: channel)
                    .environment(session)
                    .environment(servers)
                    .appSheet()
            }
        }
        .sheet(item: $profileUser) { user in
            MemberProfileSheet(user: user, onMessage: { openDirectMessage(with: user) })
                .environment(session)
                .environment(servers)
                .appSheet(addsClose: true)
        }
        .sheet(isPresented: $isAddingToGroup) {
            if let group {
                NavigationStack {
                    GroupFriendPicker(mode: .add(channelId: channelId, memberIds: group.memberIds), onDone: addedToGroup)
                }
                .presentationBackground(Theme.deepBackground)
                .environment(session)
                .environment(servers)
                .appSheet()
            }
        }
        .alert("Rename Group", isPresented: $isRenamingGroup) {
            TextField("Group name", text: $groupName)
            Button("Save", action: rename)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Leave it empty to show the people in it instead.")
        }
        .confirmationDialog("Leave this group?", isPresented: $isConfirmingLeave, titleVisibility: .visible) {
            Button("Leave Group", role: .destructive, action: leave)
        } message: {
            Text("You won't see it again unless someone adds you back.")
        }
        .onAppear(perform: makeModel)
    }

    private var isDirectMessage: Bool {
        channel?.isDm == true
    }

    private var group: GroupInfo? {
        session.group(for: channelId)
    }

    // nobody is invited into a direct message
    private var inviteAction: (() -> Void)? {
        if isDirectMessage {
            return nil
        }

        return showInvite
    }

    // the person a direct message is with, their avatar and name in place of the channel's
    private var partner: PublicUser? {
        session.directMessagePartner(for: channelId)
    }

    @ViewBuilder
    private func icon(_ channel: Channel) -> some View {
        if group != nil {
            GroupAvatar(size: 46)
        } else if channel.isDm {
            AvatarView(user: partner, size: 46, showsStatus: true)
        } else {
            Image(systemName: "number")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.header)
                .frame(width: 46, height: 46)
                .background(Theme.listBackground, in: .rect(cornerRadius: 12))
        }
    }

    private func subtitle(_ channel: Channel) -> String {
        guard channel.isDm else {
            return "Text Channel"
        }

        if let group {
            return "\(group.memberIds.count + 1) Members"
        }

        if let customStatus = partner?.customStatus, !customStatus.isEmpty {
            return customStatus
        }

        return "Direct Message"
    }

    private func header(_ channel: Channel) -> some View {
        HStack(spacing: 12) {
            icon(channel)

            VStack(alignment: .leading, spacing: 2) {
                Text(channel.isDm ? session.conversationTitle(for: channelId) : channel.name)
                    .font(.title3.bold())
                    .foregroundStyle(Theme.header)
                    .lineLimit(1)

                Text(subtitle(channel))
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
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

    private func showAddToGroup() {
        isAddingToGroup = true
    }

    private func addedToGroup(_ channelId: Int) {
        isAddingToGroup = false
        // the members tab lists who is in it, a fresh model loads them again
        model = nil
        makeModel()
    }

    private func showRename() {
        groupName = group?.name ?? ""
        isRenamingGroup = true
    }

    private func rename() {
        struct RenameInput: Encodable {
            let channelId: Int
            let name: String?
        }

        let trimmed = String(groupName.trimmingCharacters(in: .whitespaces).prefix(GroupLimits.maxNameLength))

        Task {
            do {
                try await session.perform("dms.renameGroup", RenameInput(channelId: channelId, name: trimmed.isEmpty ? nil : trimmed))
                await session.loadDirectMessages()
            } catch {
                session.showError(error)
            }
        }
    }

    private func confirmLeave() {
        isConfirmingLeave = true
    }

    private func leave() {
        let channelId = channelId

        dismiss()

        Task {
            await session.leaveGroup(channelId)
        }
    }

    private func showInvite() {
        isInvitePresented = true
    }

    private func showNotifications() {
        isNotificationsPresented = true
    }
}
