import SwiftUI

struct ServerRail: View {
    let onSelectServer: (SessionStore) -> Void
    let onSelectDirectMessages: () -> Void

    @Environment(ServerListStore.self) private var servers
    @Environment(SessionStore.self) private var session

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                RailItem(
                    isSelected: servers.isShowingDirectMessages,
                    hasUnread: false,
                    badge: session.directMessagesUnreadCount,
                    action: onSelectDirectMessages
                ) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(servers.isShowingDirectMessages ? .white : Theme.text)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(servers.isShowingDirectMessages ? Theme.blurple : Theme.listBackground)
                }

                Capsule()
                    .fill(Theme.divider)
                    .frame(width: 32, height: 2)

                ForEach(servers.sessions) { server in
                    ServerRailItem(
                        server: server,
                        isSelected: server === session && !servers.isShowingDirectMessages,
                        onSelect: onSelectServer
                    )
                }

                RailItem(isSelected: false, hasUnread: false, badge: 0, action: addServer) {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Theme.green)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.listBackground)
                }
            }
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
        .frame(width: 72)
    }

    private func addServer() {
        servers.addServer()
    }
}

private struct ServerRailItem: View {
    let server: SessionStore
    let isSelected: Bool
    let onSelect: (SessionStore) -> Void

    @Environment(ServerListStore.self) private var servers

    var body: some View {
        RailItem(
            isSelected: isSelected,
            hasUnread: server.hasUnreadChannels,
            badge: isSelected ? 0 : server.directMessagesUnreadCount,
            action: select
        ) {
            ServerIcon(server: server)
                .opacity(server.phase == .signedOut ? 0.4 : 1)
        }
        .contextMenu {
            Button("Log Out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive, action: remove)
        }
    }

    private func select() {
        onSelect(server)
    }

    private func remove() {
        servers.remove(server)
    }
}

private struct ServerIcon: View {
    let server: SessionStore

    private var initials: String {
        server.displayName
            .split(separator: " ")
            .prefix(3)
            .compactMap(\.first)
            .map(String.init)
            .joined()
    }

    var body: some View {
        if let logo = server.serverInfo?.logo, let address = server.address {
            AsyncImage(url: address.fileURL(logo)) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                placeholder
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Text(initials)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Theme.header)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.listBackground)
    }
}

// the pill on the left edge is tall for the selected item and a dot for unread ones
private struct RailItem<Content: View>: View {
    let isSelected: Bool
    let hasUnread: Bool
    let badge: Int
    let action: () -> Void
    @ViewBuilder let content: Content

    private var pillHeight: CGFloat? {
        if isSelected {
            return 40
        }

        return hasUnread ? 8 : nil
    }

    var body: some View {
        Button(action: action) {
            content
                .frame(width: 48, height: 48)
                .clipShape(.rect(cornerRadius: isSelected ? 16 : 24))
                .overlay(alignment: .bottomTrailing) {
                    if badge > 0 {
                        Text(badge > 99 ? "99+" : "\(badge)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(Theme.red, in: .capsule)
                            .overlay {
                                Capsule().stroke(Theme.deepBackground, lineWidth: 3)
                            }
                            .offset(x: 4, y: 4)
                    }
                }
                .frame(maxWidth: .infinity)
                .overlay(alignment: .leading) {
                    if let pillHeight {
                        UnevenRoundedRectangle(bottomTrailingRadius: 4, topTrailingRadius: 4)
                            .fill(Theme.header)
                            .frame(width: 4, height: pillHeight)
                    }
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .animation(.snappy, value: isSelected)
    }
}
