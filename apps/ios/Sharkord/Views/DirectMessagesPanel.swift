import SwiftUI

struct DirectMessagesPanel: View {
    let onOpen: (Int) -> Void

    @Environment(SessionStore.self) private var session

    @State private var isNewMessagePresented = false
    @State private var isAddFriendsPresented = false

    var body: some View {
        // a plain scroll of cards, as discord's, rather than a list, whose own touch handling held
        // a long press back
        ScrollView {
            LazyVStack(spacing: 8) {
                actions

                if !friends.isEmpty {
                    FriendsRow(friends: friends, onOpen: openDirectMessage(with:))
                }

                ForEach(conversations) { conversation in
                    ConversationRow(
                        conversation: conversation,
                        user: session.usersById[conversation.userId],
                        unreadCount: session.unreadCounts[conversation.channelId, default: 0],
                        onOpen: { onOpen(conversation.channelId) }
                    )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .overlay {
            if session.directMessages.isEmpty {
                ContentUnavailableView(
                    "No messages yet",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Start a conversation with someone on \(session.displayName).")
                )
            }
        }
        .refreshable {
            await session.loadDirectMessages()
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            PanelHeader(title: "Messages") {
                Spacer()
            }
            .background(Theme.panelBackground)
        }
        .sheet(isPresented: $isNewMessagePresented) {
            NewDirectMessageSheet(onOpened: onOpen)
        }
        .sheet(isPresented: $isAddFriendsPresented) {
            AddFriendsSheet()
        }
    }

    // discord's row under the title: search, add friends, a new message
    private var actions: some View {
        HStack(spacing: 8) {
            SearchLink(route: SearchRoute(channelId: nil, directMessages: true)) {
                Image(systemName: "magnifyingglass")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .frame(width: 44, height: 44)
                    .background(Theme.listBackground, in: .rect(cornerRadius: 12, style: .continuous))
            }
            .accessibilityLabel("Search")

            Button(action: openAddFriends) {
                Label("Add Friends", systemImage: "person.badge.plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.header)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Theme.listBackground, in: .rect(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)

            Button(action: openNewMessage) {
                Image(systemName: "square.and.pencil")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Theme.blurple, in: .rect(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New Message")
        }
        .padding(.bottom, 4)
    }

    private var friends: [PublicUser] {
        session.friendLists.friends
            .compactMap { session.usersById[$0] }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func openAddFriends() {
        isAddFriendsPresented = true
    }

    private func openDirectMessage(with user: PublicUser) {
        Task {
            do {
                onOpen(try await session.openDirectMessage(with: user.id))
            } catch {
                session.showError(error)
            }
        }
    }

    // pinned ones first, as discord keeps them on top, each group newest first
    private var conversations: [DirectMessageConversation] {
        let pinned = session.directMessages.filter { session.isPinned($0.channelId) }
        let rest = session.directMessages.filter { !session.isPinned($0.channelId) }

        return pinned + rest
    }

    private func openNewMessage() {
        isNewMessagePresented = true
    }
}

// discord's friends along the top of the messages, each opening your conversation with them
private struct FriendsRow: View {
    let friends: [PublicUser]
    let onOpen: (PublicUser) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(friends) { friend in
                    Button {
                        onOpen(friend)
                    } label: {
                        AvatarView(user: friend, size: 52, showsStatus: true)
                            .frame(width: 80, height: 80)
                            .background(Theme.listBackground, in: .rect(cornerRadius: 18, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Theme.divider, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(friend.name)
                }
            }
        }
        .scrollIndicators(.hidden)
        .padding(.bottom, 4)
    }
}

private struct ConversationRow: View {
    let conversation: DirectMessageConversation
    let user: PublicUser?
    let unreadCount: Int
    let onOpen: () -> Void

    @Environment(SessionStore.self) private var session

    @State private var isPressed = false
    @State private var isActionsPresented = false
    // mute was picked in the menu, its lengths open once the menu has gone: two sheets closing
    // at once brought the menu back for a moment
    @State private var wantsMute = false
    @State private var isMutePresented = false

    var body: some View {
        // plain gestures, as the channel rows: a recognised long press cancels the tap, where a
        // link still fires when the finger lifts after one
        // the card gives a little under the finger straight away, so the press feels fluid
        label
            .padding(12)
            .background(isPressed ? Theme.panelSelected : Theme.listBackground, in: .rect(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Theme.divider, lineWidth: 1)
            }
            .contentShape(.rect(cornerRadius: 16))
            .scaleEffect(isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.2), value: isPressed)
            .onTapGesture(perform: onOpen)
            .onLongPressGesture(minimumDuration: 0.3, perform: showActions, onPressingChanged: setPressed)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "More Options", showActions)
            .sheet(isPresented: $isActionsPresented, onDismiss: showMuteIfWanted) {
                DirectMessageActionsSheet(conversation: conversation, user: user, onMute: requestMute)
            }
            .sheet(isPresented: $isMutePresented) {
                MuteDurationSheet(
                    title: "Mute this conversation",
                    subtitle: "@\(user?.name ?? "Unknown")",
                    channelId: conversation.channelId
                )
            }
    }

    private func setPressed(_ pressed: Bool) {
        isPressed = pressed
    }

    private func requestMute() {
        wantsMute = true
        isActionsPresented = false
    }

    private func showMuteIfWanted() {
        if wantsMute {
            wantsMute = false
            isMutePresented = true
        }
    }

    private func showActions() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        isActionsPresented = true
    }

    // "Name: what they said", as discord's rows, or a word for a message that was only files
    private var preview: String? {
        guard let text = conversation.lastMessagePreview else {
            return nil
        }

        // your own last message reads "You:", as in discord
        let author = conversation.lastMessageUserId.flatMap { userId in
            userId == session.ownUserId ? "You" : session.usersById[userId]?.name
        }
        let body = text.isEmpty ? "Sent an attachment" : text

        return author.map { "\($0): \(body)" } ?? body
    }

    private var label: some View {
        HStack(spacing: 12) {
            if conversation.group != nil {
                GroupAvatar(size: 48)
            } else {
                AvatarView(user: user, size: 48, showsStatus: true)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(session.conversationTitle(for: conversation.channelId))
                        .font(.body.weight(unreadCount > 0 ? .bold : .semibold))
                        .foregroundStyle(Theme.header)
                        .lineLimit(1)

                    Spacer(minLength: 6)

                    indicators

                    Text(ShortAge.text(since: conversation.lastMessageAt))
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                }

                if let preview {
                    Text(preview)
                        .font(.subheadline)
                        .foregroundStyle(unreadCount > 0 ? Theme.header : Theme.text)
                        .lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder
    private var indicators: some View {
        HStack(spacing: 6) {
            if session.isMuted(conversation.channelId) {
                Image(systemName: "bell.slash.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }

            if session.isPinned(conversation.channelId) {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }

            if unreadCount > 0 {
                Text("\(unreadCount)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Theme.red, in: .capsule)
            }
        }
    }
}

// discord's short age on a conversation: now, 5m, 3h, 15d, 2mo, 1y
enum ShortAge {
    static func text(since milliseconds: Int, now: Date = .now) -> String {
        let seconds = max(0, now.timeIntervalSince1970 - Double(milliseconds) / 1000)
        let minutes = Int(seconds / 60)
        let hours = minutes / 60
        let days = hours / 24

        if minutes < 1 {
            return "now"
        }

        if hours < 1 {
            return "\(minutes)m"
        }

        if days < 1 {
            return "\(hours)h"
        }

        if days < 30 {
            return "\(days)d"
        }

        if days < 365 {
            return "\(days / 30)mo"
        }

        return "\(days / 365)y"
    }
}

// discord's long press sheet for a conversation: who it is with, their profile, close it, pin it
// to the top, mark it read, mute it
private struct DirectMessageActionsSheet: View {
    let conversation: DirectMessageConversation
    let user: PublicUser?
    // the row opens the mute lengths once this sheet has gone
    let onMute: () -> Void

    @Environment(SessionStore.self) private var session
    @Environment(ServerListStore.self) private var servers
    @Environment(\.dismiss) private var dismiss

    @State private var isProfilePresented = false

    private var channelId: Int {
        conversation.channelId
    }

    private var isMuted: Bool {
        session.isMuted(channelId)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    if conversation.group != nil {
                        GroupAvatar(size: 48)
                    } else {
                        AvatarView(user: user, size: 48)
                    }

                    Text(conversation.group == nil ? "@\(user?.name ?? "Unknown")" : session.conversationTitle(for: channelId))
                        .font(.title3.bold())
                        .foregroundStyle(Theme.header)
                        .lineLimit(1)
                }
                .padding(.top, 20)

                ActionGroup {
                    if user != nil, conversation.group == nil {
                        ActionRow(title: "Profile", systemImage: "person.crop.circle", action: showProfile)
                    }

                    ActionRow(title: "Close DM", systemImage: "person.badge.minus", action: close)

                    if conversation.group != nil {
                        ActionRow(title: "Leave Group", systemImage: "rectangle.portrait.and.arrow.right", tint: Theme.red, action: leaveGroup)
                    }
                }

                ActionGroup {
                    ActionRow(
                        title: session.isPinned(channelId) ? "Unpin" : "Pin",
                        systemImage: session.isPinned(channelId) ? "pin.slash.fill" : "pin.fill",
                        action: togglePinned
                    )
                }

                ActionGroup {
                    ActionRow(title: "Mark As Read", systemImage: "eye", action: markAsRead)
                    ActionRow(
                        title: isMuted ? "Unmute Conversation" : "Mute Conversation",
                        systemImage: isMuted ? "bell.fill" : "bell.slash.fill",
                        action: toggleMuted
                    )
                }
            }
            .padding(.horizontal, 16)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.deepBackground)
        .sheet(isPresented: $isProfilePresented) {
            if let user {
                MemberProfileSheet(user: user, onMessage: openConversation)
            }
        }

    }

    private func showProfile() {
        isProfilePresented = true
    }

    private func openConversation() {
        dismiss()
        servers.open(channelId: channelId, in: session)
    }

    private func close() {
        dismiss()

        Task {
            do {
                try await session.perform("dms.close", ["channelId": channelId])
                await session.loadDirectMessages()
            } catch {
                session.showError(error)
            }
        }
    }

    private func togglePinned() {
        session.togglePinned(channelId)
        dismiss()
    }

    private func leaveGroup() {
        dismiss()

        Task {
            await session.leaveGroup(channelId)
        }
    }

    private func markAsRead() {
        Task {
            await session.markAsRead(channelId)
        }

        dismiss()
    }

    // muting asks for how long first, unmuting goes straight back to the default
    private func toggleMuted() {
        guard isMuted else {
            onMute()
            return
        }

        Task {
            await session.setNotificationLevel(.mentions, for: channelId)
        }

        dismiss()
    }
}

// discord's new message: search everyone, add a friend, then your friends and everyone else on
// the server, a to z under their letter. a tap opens the conversation
private struct NewDirectMessageSheet: View {
    let onOpened: (Int) -> Void

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var errorMessage: String?

    private var matches: [PublicUser] {
        let search = query.trimmingCharacters(in: .whitespaces)

        return session.members
            .filter { $0.id != session.ownUserId }
            .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var friends: [PublicUser] {
        let ids = Set(session.friendLists.friends)

        return matches.filter { ids.contains($0.id) }
    }

    // everyone else under the first letter of their name
    private var others: [(letter: String, users: [PublicUser])] {
        let ids = Set(session.friendLists.friends)
        let rest = matches.filter { !ids.contains($0.id) }
        let groups = Dictionary(grouping: rest) { user in
            user.name.first.map { $0.isLetter ? String($0).uppercased() : "#" } ?? "#"
        }

        return groups.keys.sorted().map { (letter: $0, users: groups[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(Theme.red)
                        .listRowBackground(Theme.listBackground)
                }

                if query.isEmpty {
                    Section {
                        NavigationLink {
                            GroupFriendPicker(mode: .create, onDone: openGroup)
                        } label: {
                            Label("New Group", systemImage: "person.2.badge.plus")
                                .foregroundStyle(Theme.header)
                        }
                        .listRowBackground(Theme.listBackground)

                        NavigationLink {
                            AddFriendsScreen()
                        } label: {
                            Label("Add a Friend", systemImage: "person.badge.plus")
                                .foregroundStyle(Theme.header)
                        }
                        .listRowBackground(Theme.listBackground)
                    }
                }

                if !friends.isEmpty {
                    Section("Friends") {
                        ForEach(friends) { user in
                            row(user)
                        }
                    }
                }

                ForEach(others, id: \.letter) { group in
                    Section(group.letter) {
                        ForEach(group.users) { user in
                            row(user)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.deepBackground)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "To: Search people")
            .navigationTitle("New Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark", action: close)
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.deepBackground)
    }

    private func row(_ user: PublicUser) -> some View {
        Button {
            open(user)
        } label: {
            HStack(spacing: 12) {
                AvatarView(user: user, size: 40, showsStatus: true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(user.name)
                        .foregroundStyle(Theme.header)
                        .lineLimit(1)

                    if let customStatus = user.customStatus, !customStatus.isEmpty {
                        Text(customStatus)
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .listRowBackground(Theme.listBackground)
    }

    private func openGroup(_ channelId: Int) {
        dismiss()
        onOpened(channelId)
    }

    private func open(_ user: PublicUser) {
        Task {
            do {
                let channelId = try await session.openDirectMessage(with: user.id)

                dismiss()
                onOpened(channelId)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func close() {
        dismiss()
    }
}
