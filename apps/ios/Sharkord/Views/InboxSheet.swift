import SwiftUI

// discord's inbox. the server keeps a list of mentions per account, so the mentions tab asks
// every server for its own and merges them, newest first
struct InboxSheet: View {
    enum Tab: String, CaseIterable {
        case mentions = "Mentions"
        case unreads = "Unreads"
    }

    // set when it is the mac's dropdown under the chat's top bar rather than a presentation,
    // which dismiss would not close
    var onClose: (() -> Void)?

    @Environment(ServerListStore.self) private var servers
    @Environment(\.dismiss) private var dismiss

    @State private var tab = Tab.mentions
    @State private var mentionsReloads = 0
    @State private var isMarkingRead = false

    var body: some View {
        if onClose != nil {
            // the mac's dropdown names itself, as pins does: a navigation title there would go
            // up into the chat's own bar
            VStack(spacing: 0) {
                Text("Inbox")
                    .font(.headline)
                    .foregroundStyle(Theme.header)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                Theme.divider
                    .frame(height: 1)

                content
            }
        } else {
            NavigationStack {
                content
                    .navigationTitle("Inbox")
                    .inlineNavigationTitle()
                    .toolbar {
                        ActionToolbarItem(placement: .confirmationAction) {
                            Button("Done", action: close)
                        }
                    }
            }
            .presentationBackground(Theme.deepBackground)
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            Picker("Inbox", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Text(tab.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            switch tab {
            case .mentions:
                MentionsList(reloads: mentionsReloads, markAll: markAll, onOpen: openMention)
            case .unreads:
                UnreadsList(markAll: markAll, onOpen: openUnread)
            }
        }
        .background(Theme.deepBackground)
    }

    private var markAll: MarkAllBar {
        MarkAllBar(isMarking: isMarkingRead, action: markAllAsRead)
    }

    private func markAllAsRead() {
        isMarkingRead = true

        Task {
            for server in servers.sessions where server.phase == .connected {
                await server.markAllAsRead()
            }

            isMarkingRead = false
            mentionsReloads += 1
        }
    }

    // at the message, as a notification's tap is, or its thread for a reply inside one
    private func openMention(_ message: Message, in server: SessionStore) {
        close()
        servers.open(channelId: message.channelId, messageId: message.id, threadParentId: message.parentMessageId, in: server)
    }

    private func openUnread(_ channelId: Int, in server: SessionStore) {
        close()
        servers.open(channelId: channelId, atFirstUnread: true, in: server)
    }

    private func close() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }
}

// under the tabs, where a list's bulk action goes, and only while the tab has something to clear
private struct MarkAllBar: View {
    let isMarking: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            Spacer()

            Button("Mark All As Read", action: action)
                .buttonStyle(.borderless)
                .font(.subheadline)
                .disabled(isMarking)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }
}

private struct ServerMention: Identifiable {
    let server: SessionStore
    let message: Message

    var id: String { "\(ObjectIdentifier(server).hashValue)-\(message.id)" }
}

private struct MentionsList: View {
    // bumped to load the list again, after the inbox was marked as read
    let reloads: Int
    let markAll: MarkAllBar
    let onOpen: (Message, SessionStore) -> Void

    @Environment(ServerListStore.self) private var servers

    @State private var mentions: [ServerMention] = []
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            if !mentions.isEmpty {
                markAll
            }

            list
        }
    }

    private var list: some View {
        List {
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(Theme.redText)
                    .listRowBackground(Theme.groupedRowBackground)
            }

            ForEach(mentions) { mention in
                MentionRow(message: mention.message, onOpen: { onOpen(mention.message, mention.server) })
                    .environment(mention.server)
                    .listRowBackground(Theme.groupedRowBackground)
                    // a divider under the last row reads as a stray line above the empty space
                    .listRowSeparator(mention.id == mentions.last?.id ? .hidden : .automatic, edges: .bottom)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .listHoverHighlight()
        .overlay {
            if isLoading {
                ProgressView()
            } else if mentions.isEmpty && errorMessage == nil {
                ContentUnavailableView(
                    "No new mentions",
                    systemImage: "at",
                    description: Text("Mentions and replies to you that you haven't read show up here.")
                )
            }
        }
        .refreshable {
            await load()
        }
        .task(id: reloads) {
            await load()
        }
    }

    private func load() async {
        var loaded: [ServerMention] = []
        var failure: String?

        for server in servers.sessions where server.phase == .connected {
            do {
                let messages = try await server.mentions()

                loaded += messages.map { ServerMention(server: server, message: $0) }
            } catch {
                failure = error.localizedDescription
            }
        }

        mentions = loaded.sorted { $0.message.createdAt > $1.message.createdAt }
        errorMessage = failure
        isLoading = false
    }
}

private struct MentionRow: View {
    let message: Message
    let onOpen: () -> Void

    @Environment(SessionStore.self) private var session

    private var author: PublicUser? {
        message.userId.flatMap { session.usersById[$0] }
    }

    private var place: String {
        guard let channel = session.channel(message.channelId) else {
            return session.displayName
        }

        return String(localized: "#\(channel.name) · \(session.displayName)")
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 12) {
                AvatarView(user: author, size: 36)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(author?.name ?? message.pluginId ?? "Unknown")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(session.nameColor(for: author))

                        Text(MessageDate.timestamp(message.createdDate))
                            .font(.caption2)
                            .foregroundStyle(Theme.muted)
                    }
                    .lineLimit(1)

                    Text(place)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)

                    if let content = message.content {
                        MessageContentView(html: content)
                            .lineLimit(4)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct UnreadsList: View {
    let markAll: MarkAllBar
    let onOpen: (Int, SessionStore) -> Void

    @Environment(ServerListStore.self) private var servers

    private var hasUnread: Bool {
        servers.sessions.contains { !$0.unreadChannels.isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            if hasUnread {
                markAll
            }

            list
        }
    }

    private var list: some View {
        List {
            ForEach(servers.sessions) { server in
                if !server.unreadChannels.isEmpty {
                    Section(server.displayName) {
                        ForEach(server.unreadChannels) { channel in
                            UnreadRow(channel: channel, onOpen: { onOpen(channel.id, server) })
                                .environment(server)
                                .listRowBackground(Theme.groupedRowBackground)
                        }
                    }
                }
            }
            .listRowBackground(Theme.groupedRowBackground)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .listHoverHighlight()
        .overlay {
            if !hasUnread {
                ContentUnavailableView(
                    "You're all caught up",
                    systemImage: "bell",
                    description: Text("Unread channels and messages show up here.")
                )
            }
        }
    }
}

private struct UnreadRow: View {
    let channel: Channel
    let onOpen: () -> Void

    @Environment(SessionStore.self) private var session

    private var partner: PublicUser? {
        session.directMessagePartner(for: channel.id)
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                if channel.isDm {
                    AvatarView(user: partner, size: 32, showsStatus: true)
                } else {
                    Image(systemName: "number")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 32)
                }

                Text(channel.isDm ? partner?.name ?? "Direct Message" : channel.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.header)
                    .lineLimit(1)

                Spacer()

                Text("\(session.unreadCounts[channel.id, default: 0])")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Theme.red, in: .capsule)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
