import SwiftUI

struct DirectMessagesPanel: View {
    let onOpen: (Int) -> Void

    @Environment(SessionStore.self) private var session

    @State private var isNewMessagePresented = false

    var body: some View {
        List {
            ForEach(conversations) { conversation in
                ConversationRow(
                    conversation: conversation,
                    user: session.usersById[conversation.userId],
                    unreadCount: session.unreadCounts[conversation.channelId, default: 0],
                    onOpen: { onOpen(conversation.channelId) }
                )
                .listRowBackground(Theme.panelBackground)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
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

                Button("New Message", systemImage: "square.and.pencil", action: openNewMessage)
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .foregroundStyle(Theme.text)
            }
            .background(Theme.panelBackground)
        }
        .sheet(isPresented: $isNewMessagePresented) {
            NewDirectMessageSheet(onOpened: onOpen)
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

private struct ConversationRow: View {
    let conversation: DirectMessageConversation
    let user: PublicUser?
    let unreadCount: Int
    let onOpen: () -> Void

    @Environment(SessionStore.self) private var session

    @State private var isPressed = false
    @State private var isActionsPresented = false

    var body: some View {
        // plain gestures, as the channel rows: a recognised long press cancels the tap, where a
        // link still fires when the finger lifts after one
        label
            .contentShape(.rect)
            .background(isPressed ? Theme.panelSelected : .clear, in: .rect(cornerRadius: 6))
            .onTapGesture(perform: onOpen)
            .onLongPressGesture(minimumDuration: 0.35, perform: showActions, onPressingChanged: setPressed)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "More Options", showActions)
            .sheet(isPresented: $isActionsPresented) {
                DirectMessageActionsSheet(conversation: conversation, user: user)
            }
    }

    private func setPressed(_ pressed: Bool) {
        isPressed = pressed
    }

    private func showActions() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        isActionsPresented = true
    }

    private var label: some View {
        HStack(spacing: 12) {
            AvatarView(user: user, size: 44, showsStatus: true)

            VStack(alignment: .leading, spacing: 2) {
                Text(user?.name ?? "Unknown")
                    .font(.body.weight(unreadCount > 0 ? .bold : .semibold))
                    .foregroundStyle(Theme.header)

                Text(MessageDate.timestamp(Date(timeIntervalSince1970: TimeInterval(conversation.lastMessageAt) / 1000)))
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }

            Spacer()

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
        .padding(.vertical, 4)
    }
}

// discord's long press sheet for a conversation: who it is with, their profile, close it, pin it
// to the top, mark it read, mute it
private struct DirectMessageActionsSheet: View {
    let conversation: DirectMessageConversation
    let user: PublicUser?

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
                    AvatarView(user: user, size: 48)

                    Text("@\(user?.name ?? "Unknown")")
                        .font(.title3.bold())
                        .foregroundStyle(Theme.header)
                        .lineLimit(1)
                }
                .padding(.top, 20)

                ActionGroup {
                    if user != nil {
                        ActionRow(title: "Profile", systemImage: "person.crop.circle", action: showProfile)
                    }

                    ActionRow(title: "Close DM", systemImage: "person.badge.minus", action: close)
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

    private func markAsRead() {
        Task {
            await session.markAsRead(channelId)
        }

        dismiss()
    }

    // muting is the "nothing" notification level, unmuting goes back to the default
    private func toggleMuted() {
        let level: ChannelNotificationLevel = isMuted ? .mentions : .none

        Task {
            await session.setNotificationLevel(level, for: channelId)
        }

        dismiss()
    }
}

private struct NewDirectMessageSheet: View {
    let onOpened: (Int) -> Void

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var errorMessage: String?

    private var users: [PublicUser] {
        let others = session.members
            .filter { $0.id != session.ownUserId }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        guard !query.isEmpty else {
            return others
        }

        return others.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(Theme.red)
                }

                ForEach(users) { user in
                    Button(action: { open(user) }) {
                        HStack(spacing: 12) {
                            AvatarView(user: user, size: 36, showsStatus: true)

                            Text(user.name)
                                .foregroundStyle(Theme.header)
                        }
                    }
                    .listRowBackground(Theme.listBackground)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.listBackground)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Find a friend")
            .navigationTitle("New Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: close)
                }
            }
        }
        .presentationBackground(Theme.listBackground)
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
