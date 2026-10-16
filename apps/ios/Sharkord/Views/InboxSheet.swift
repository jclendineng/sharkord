import SwiftUI

// discord's inbox. the server keeps a list of mentions per account, so the mentions tab asks
// every server for its own and merges them, newest first
struct InboxSheet: View {
    enum Tab: String, CaseIterable {
        case mentions = "Mentions"
        case unreads = "Unreads"
    }

    @Environment(ServerListStore.self) private var servers
    @Environment(\.dismiss) private var dismiss

    @State private var tab = Tab.mentions

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Inbox", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { tab in
                        Text(tab.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                switch tab {
                case .mentions:
                    MentionsList(onOpen: open)
                case .unreads:
                    UnreadsList(onOpen: open)
                }
            }
            .background(Theme.deepBackground)
            .navigationTitle("Inbox")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // on a mac the bell's popover opens as a sheet that a click outside does not
                // close, so it gets the x the other sheets have, and escape closes it too
                if ProcessInfo.processInfo.isiOSAppOnMac {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", systemImage: "xmark", action: close)
                            .keyboardShortcut(.cancelAction)
                    }
                } else {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", action: close)
                    }
                }
            }
        }
        .presentationBackground(Theme.deepBackground)
    }

    private func open(_ channelId: Int, in server: SessionStore) {
        dismiss()
        servers.open(channelId: channelId, in: server)
    }

    private func close() {
        dismiss()
    }
}

private struct ServerMention: Identifiable {
    let server: SessionStore
    let message: Message

    var id: String { "\(ObjectIdentifier(server).hashValue)-\(message.id)" }
}

private struct MentionsList: View {
    let onOpen: (Int, SessionStore) -> Void

    @Environment(ServerListStore.self) private var servers

    @State private var mentions: [ServerMention] = []
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(Theme.red)
                    .listRowBackground(Theme.listBackground)
            }

            ForEach(mentions) { mention in
                MentionRow(message: mention.message, onOpen: { onOpen(mention.message.channelId, mention.server) })
                    .environment(mention.server)
                    .listRowBackground(Theme.listBackground)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .overlay {
            if isLoading {
                ProgressView()
            } else if mentions.isEmpty && errorMessage == nil {
                ContentUnavailableView(
                    "No mentions yet",
                    systemImage: "at",
                    description: Text("Messages that mention you or reply to you show up here.")
                )
            }
        }
        .refreshable {
            await load()
        }
        .task {
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

        return "#\(channel.name) · \(session.displayName)"
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 12) {
                AvatarView(user: author, size: 36)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(author?.name ?? message.pluginId ?? "Unknown")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(hex: session.roleColor(for: author) ?? "#F2F3F5"))

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
    let onOpen: (Int, SessionStore) -> Void

    @Environment(ServerListStore.self) private var servers

    private var hasUnread: Bool {
        servers.sessions.contains { !$0.unreadChannels.isEmpty }
    }

    var body: some View {
        List {
            ForEach(servers.sessions) { server in
                if !server.unreadChannels.isEmpty {
                    Section(server.displayName) {
                        ForEach(server.unreadChannels) { channel in
                            UnreadRow(channel: channel, onOpen: { onOpen(channel.id, server) })
                                .environment(server)
                        }
                    }
                }
            }
            .listRowBackground(Theme.listBackground)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
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
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Theme.red, in: .capsule)
            }
        }
    }
}
