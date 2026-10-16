import SwiftUI

struct ServerRail: View {
    static let width: CGFloat = 72

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
                        .background(servers.isShowingDirectMessages ? Theme.blurple : Theme.panelControl)
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
                        .background(Theme.panelControl)
                }
            }
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
        // the rail runs up under a mac's title bar, where the fade a scroll view draws below a
        // top bar showed as a grey block over the dark rail
        .scrollEdgeEffectHidden(true, for: .top)
        .frame(width: Self.width)
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

    @State private var frame = CGRect.zero

    var body: some View {
        RailItem(
            isSelected: isSelected,
            hasUnread: server.hasUnreadChannels,
            badge: isSelected ? 0 : server.directMessagesUnreadCount,
            action: select
        ) {
            ServerIcon(server: server)
                .opacity(server.phase == .signedOut ? 0.4 : 1)
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .named(HomeView.coordinateSpace))
                } action: { newFrame in
                    frame = newFrame
                }
        }
        // discord keeps the icon in place and opens a menu beside it, the system context
        // menu lifts the whole row out instead
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.3).onEnded(longPressed))
        .onSecondaryClick(perform: rightClicked)
    }

    // releasing a long press also counts as a tap, which must not switch servers
    private func select() {
        guard servers.railMenu == nil else {
            return
        }

        onSelect(server)
    }

    private func longPressed(_: Bool) {
        showMenu()
    }

    // the menu already opens beside the icon, wherever on it the click was
    private func rightClicked(_: SecondaryClick) {
        showMenu()
    }

    private func showMenu() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        servers.railMenu = ServerListStore.RailMenu(server: server, iconFrame: frame)
    }
}

struct ServerIcon: View {
    let server: SessionStore

    var body: some View {
        if let logo = server.serverInfo?.logo, let address = server.address {
            CachedFileImage(file: logo, url: address.fileURL(logo)) {
                placeholder
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Text(server.initials)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Theme.header)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.panelControl)
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
                                Capsule().stroke(Theme.railBackground, lineWidth: 3)
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
