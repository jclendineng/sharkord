import SwiftUI

// every channel and conversation with unread messages, across all servers. the server keeps
// no list of mentions, so this is the inbox the app can offer
struct UnreadsSheet: View {
    @Environment(ServerListStore.self) private var servers
    @Environment(\.dismiss) private var dismiss

    private var hasUnread: Bool {
        servers.sessions.contains { !$0.unreadChannels.isEmpty }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(servers.sessions) { server in
                    if !server.unreadChannels.isEmpty {
                        Section(server.displayName) {
                            ForEach(server.unreadChannels) { channel in
                                UnreadRow(channel: channel, onOpen: { open(channel, in: server) })
                                    .environment(server)
                            }
                        }
                    }
                }
                .listRowBackground(Theme.listBackground)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.deepBackground)
            .overlay {
                if !hasUnread {
                    ContentUnavailableView(
                        "You're all caught up",
                        systemImage: "bell",
                        description: Text("Unread channels and messages show up here.")
                    )
                }
            }
            .navigationTitle("Unreads")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: close)
                }
            }
        }
        .presentationBackground(Theme.deepBackground)
    }

    private func open(_ channel: Channel, in server: SessionStore) {
        dismiss()
        servers.open(channelId: channel.id, in: server)
    }

    private func close() {
        dismiss()
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
