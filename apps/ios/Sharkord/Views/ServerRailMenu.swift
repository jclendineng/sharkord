import SwiftUI

// discord's long press menu for a server: the screen dims, the icon stays where it is and
// the menu opens beside it
struct ServerRailMenu: View {
    private static let width: CGFloat = 250

    let menu: ServerListStore.RailMenu

    @Environment(ServerListStore.self) private var servers

    @State private var height: CGFloat = 0
    @State private var isShown = false
    @State private var menuId = UUID()

    private var server: SessionStore {
        menu.server
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .onTapGesture(perform: close)

                card
                    .scaleEffect(isShown ? 1 : 0.85, anchor: .topLeading)
                    .opacity(isShown ? 1 : 0)
                    .offset(x: menu.iconFrame.maxX + 10, y: top(in: proxy.size))
            }
        }
        .transition(.opacity)
        .onAppear(perform: show)
        .onDisappear(perform: hidden)
    }

    // grows out of the icon like discord's, quick enough to feel attached to the finger. a right
    // click elsewhere on a mac moves to that menu or closes this one, as the others do
    private func show() {
        PointerMenus.opened(menuId, close: close)

        withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
            isShown = true
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(server.displayName)
                .font(.headline)
                .foregroundStyle(Theme.header)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

            Theme.divider.frame(height: 1)

            // each group keeps a margin, so a lit row sits whole inside the card's corners
            VStack(spacing: 0) {
                MenuRow(title: "Mark As Read", systemImage: "envelope.fill", action: markAsRead)

                if server.serverInfo?.pushEnabled == true {
                    MenuRow(
                        title: server.isPushEnabled ? "Mute Notifications" : "Unmute Notifications",
                        systemImage: server.isPushEnabled ? "bell.slash.fill" : "bell.fill",
                        action: togglePush
                    )
                }

                MenuRow(title: "More Options", systemImage: "gearshape.fill", action: moreOptions)
            }
            .padding(.vertical, 6)

            Theme.divider.frame(height: 1)

            MenuRow(title: "Log Out", systemImage: "rectangle.portrait.and.arrow.right", tint: Theme.red, action: logOut)
                .padding(.vertical, 6)
        }
        .frame(width: Self.width)
        .background(Theme.listBackground, in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16).stroke(Theme.divider, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { newHeight in
            height = newHeight
        }
    }

    // level with the icon, moved up when that would run off the bottom
    private func top(in size: CGSize) -> CGFloat {
        let preferred = menu.iconFrame.minY

        return max(8, min(preferred, size.height - height - 8))
    }

    private func close() {
        servers.railMenu = nil
    }

    private func hidden() {
        PointerMenus.closed(menuId)
    }

    private func markAsRead() {
        close()

        Task {
            await server.markAllAsRead()
        }
    }

    private func togglePush() {
        let enable = !server.isPushEnabled

        close()

        Task {
            await server.setPushEnabled(enable)
        }
    }

    private func moreOptions() {
        close()
        servers.showServerSheet(for: server)
    }

    private func logOut() {
        close()
        servers.remove(server)
    }
}

// filled while the pointer is on it, as the other menus' rows are, red for a destructive one
private struct MenuRow: View {
    let title: String
    let systemImage: String
    var tint = Theme.header
    let action: () -> Void

    @State private var isHovered = false

    private var isDestructive: Bool {
        tint == Theme.red
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .frame(width: 22)

                Text(title)

                Spacer()
            }
            .font(.body)
            .foregroundStyle(isHovered && isDestructive ? .white : tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(isHovered ? (isDestructive ? Theme.red : Theme.hover) : .clear, in: .rect(cornerRadius: 6))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover(perform: setHovered)
    }

    private func setHovered(_ hovered: Bool) {
        isHovered = hovered
    }
}
