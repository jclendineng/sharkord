import SwiftUI

struct DirectMessagesPanel: View {
    let onOpen: (Int) -> Void

    @Environment(SessionStore.self) private var session

    @State private var isNewMessagePresented = false

    var body: some View {
        List {
            ForEach(session.directMessages) { conversation in
                NavigationLink(value: ChatRoute(channelId: conversation.channelId)) {
                    ConversationRow(
                        user: session.usersById[conversation.userId],
                        lastMessageAt: conversation.lastMessageAt,
                        unreadCount: session.unreadCounts[conversation.channelId, default: 0]
                    )
                }
                .listRowBackground(Theme.listBackground)
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
            .background(Theme.listBackground)
        }
        .sheet(isPresented: $isNewMessagePresented) {
            NewDirectMessageSheet(onOpened: onOpen)
        }
    }

    private func openNewMessage() {
        isNewMessagePresented = true
    }
}

private struct ConversationRow: View {
    let user: PublicUser?
    let lastMessageAt: Int
    let unreadCount: Int

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(user: user, size: 44, showsStatus: true)

            VStack(alignment: .leading, spacing: 2) {
                Text(user?.name ?? "Unknown")
                    .font(.body.weight(unreadCount > 0 ? .bold : .semibold))
                    .foregroundStyle(Theme.header)

                Text(MessageDate.timestamp(Date(timeIntervalSince1970: TimeInterval(lastMessageAt) / 1000)))
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }

            Spacer()

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
