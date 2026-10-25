import SwiftUI

// discord's long press sheet for a channel
struct ChannelActionsSheet: View {
    let channel: Channel
    // the row opens the mute lengths once this sheet has gone
    let onMute: () -> Void
    // the mac's menu hands the invite to its row, a sheet shown from the menu left it open behind
    var onInvite: (() -> Void)?
    // the editor opens from the row once this has gone, as the mute lengths do
    let onEdit: () -> Void

    @Environment(SessionStore.self) private var session
    @Environment(ServerListStore.self) private var servers
    @Environment(\.dismiss) private var dismiss
    @Environment(\.closePointerMenu) private var closePointerMenu
    @Environment(\.isPointerMenu) private var isPointerMenu

    @State private var isInvitePresented = false
    @State private var isNotificationsPresented = false

    private var isMuted: Bool {
        session.isMuted(channel.id)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: isPointerMenu ? 0 : 16) {
                // discord's menu opens straight on its rows
                if !isPointerMenu {
                    HStack(spacing: 12) {
                        ServerIcon(server: session)
                            .frame(width: 44, height: 44)
                            .clipShape(.rect(cornerRadius: 12))

                        Text(channel.type == .text ? "#\(channel.name)" : channel.name)
                            .font(.title3.bold())
                            .foregroundStyle(Theme.header)
                            .lineLimit(1)
                    }
                    .padding(.top, 20)
                }

                ActionGroup(isFirst: isPointerMenu) {
                    ActionRow(title: "Invite", systemImage: "person.badge.plus", action: showInvite)
                    ActionRow(
                        title: session.isPinned(channel.id) ? "Unpin Channel" : "Pin Channel to Top",
                        systemImage: session.isPinned(channel.id) ? "pin.slash.fill" : "pin.fill",
                        action: togglePinned
                    )

                    // the app opens it, a voice channel has no chat for it to land on
                    if channel.type == .text {
                        ActionRow(title: "Copy Link", systemImage: "link", action: copyLink)
                    }
                }

                ActionGroup {
                    ActionRow(title: "Mark As Read", systemImage: "eye", action: markAsRead)

                    if isPointerMenu && !isMuted {
                        SubmenuRow(title: "Mute Channel") {
                            MuteChoices(onPick: mute)
                        }
                    } else {
                        ActionRow(
                            title: isMuted ? "Unmute Channel" : "Mute Channel",
                            systemImage: isMuted ? "bell.fill" : "bell.slash.fill",
                            action: toggleMuted
                        )
                    }

                    if isPointerMenu {
                        SubmenuRow(
                            title: "Notification Settings",
                            subtitle: NotificationLevelChoices.title(for: session.notificationLevel(for: channel.id))
                        ) {
                            NotificationLevelChoices(selected: session.notificationLevel(for: channel.id), onPick: setLevel)
                        }
                    } else {
                        ActionRow(title: "Notification Settings", systemImage: "app.badge", action: showNotifications)
                    }
                }

                if channel.type == .voice {
                    ActionGroup {
                        ActionRow(
                            title: session.hidesNames(in: channel.id) ? "Show Names" : "Hide Names",
                            systemImage: "person.crop.circle",
                            action: toggleNames
                        )
                    }
                }

                if session.can(.manageChannels) {
                    ActionGroup {
                        ActionRow(title: "Edit Channel", systemImage: "gearshape.fill", action: onEdit)

                        if channel.categoryId != nil {
                            ActionRow(title: "Duplicate Channel", systemImage: "plus.square.on.square", action: duplicate)
                        }
                    }
                }
            }
            .padding(.horizontal, isPointerMenu ? 6 : 16)
            .fittedSheet()
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.deepBackground)
        // handed over by hand: on a mac a sheet's background is worked out before it inherits
        // anything, so a sheet reading a store it was not given crashed on opening
        .sheet(isPresented: $isInvitePresented) {
            InviteSheet()
                .environment(session)
                .environment(servers)
                .appSheet()
        }
        .sheet(isPresented: $isNotificationsPresented) {
            ChannelNotificationsSheet(channel: channel)
                .environment(session)
                .environment(servers)
                .appSheet()
        }

    }

    private func showInvite() {
        if isPointerMenu, let onInvite {
            onInvite()
        } else {
            isInvitePresented = true
        }
    }

    private func togglePinned() {
        session.togglePinned(channel.id)
        closeMenu()
    }

    private func copyLink() {
        Platform.copy(session.link(to: channel.id))
        closeMenu()
    }

    private func toggleNames() {
        session.toggleHidesNames(in: channel.id)
        closeMenu()
    }

    // discord's clone: the same name, kind and category, private and with its topic if it was
    private func duplicate() {
        struct NewChannelInput: Encodable {
            let type: ChannelType
            let name: String
            let categoryId: Int
        }

        struct UpdateInput: Encodable {
            let channelId: Int
            let name: String
            let topic: String?
            let `private`: Bool
        }

        guard let categoryId = channel.categoryId else {
            return
        }

        Task {
            do {
                let channelId: Int = try await session.perform(
                    "channels.add",
                    NewChannelInput(type: channel.type, name: channel.name, categoryId: categoryId)
                )

                if channel.private || channel.topic != nil {
                    try await session.perform(
                        "channels.update",
                        UpdateInput(channelId: channelId, name: channel.name, topic: channel.topic, private: channel.private)
                    )
                }
            } catch {
                session.showError(error)
            }
        }

        closeMenu()
    }

    private func markAsRead() {
        Task {
            await session.markAsRead(channel.id)
        }

        closeMenu()
    }

    // muting asks for how long first, unmuting goes straight back to the default
    private func toggleMuted() {
        guard isMuted else {
            onMute()
            return
        }

        Task {
            await session.setNotificationLevel(.mentions, for: channel.id)
        }

        closeMenu()
    }

    private func showNotifications() {
        isNotificationsPresented = true
    }

    private func mute(for duration: MuteDuration) {
        Task {
            await session.setNotificationLevel(.none, for: channel.id, muteForMinutes: duration.minutes)
        }

        closeMenu()
    }

    private func setLevel(_ level: ChannelNotificationLevel) {
        Task {
            await session.setNotificationLevel(level, for: channel.id)
        }

        closeMenu()
    }

    // a sheet on a touch screen, the pointer menu on a mac, where dismiss has nothing to close
    private func closeMenu() {
        if let closePointerMenu {
            closePointerMenu()
        } else {
            dismiss()
        }
    }
}

// a mac menu row with more choices beside it, discord's rows with a chevron. the pointer
// reaching it opens them, a click does the same, and the pointer moving on to another row of
// the menu closes them again
struct SubmenuRow<Submenu: View>: View {
    let title: String
    // what is picked now, under the title as discord shows it
    var subtitle: String?
    @ViewBuilder let submenu: () -> Submenu

    // handed on by hand: the submenu is drawn by the menu layer at the window's root, which
    // has no server of its own, and an emoji reading it crashed
    @Environment(SessionStore.self) private var session: SessionStore?

    @State private var id = UUID()
    @State private var frame = CGRect.zero

    private let menus = PointerMenuState.shared

    private var isOpen: Bool {
        menus.submenu?.id == id
    }

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(.medium))

                    if let subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(Theme.muted)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 18)
            }
            .foregroundStyle(Theme.header)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(isOpen ? Theme.hover : .clear, in: .rect(cornerRadius: 4))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { newFrame in
            frame = newFrame
        }
        .onHover(perform: hovered)
    }

    private func hovered(_ isHovered: Bool) {
        if isHovered {
            open()
        }
    }

    private func open() {
        guard !isOpen else {
            return
        }

        let content = VStack(spacing: 0) {
            submenu()
        }
        .environment(session)

        PointerMenus.showSubmenu(id, beside: frame, content: AnyView(content))
    }
}

// how long to mute for, discord's list from 15 minutes to until it is turned back on
struct MuteChoices: View {
    let onPick: (MuteDuration) -> Void

    var body: some View {
        ForEach(MuteDuration.allCases) { duration in
            ActionRow(title: duration.title, systemImage: "") {
                onPick(duration)
            }
        }
    }
}

// which messages notify, the current one filled in like discord's radio buttons
struct NotificationLevelChoices: View {
    // nil for a category whose channels differ
    let selected: ChannelNotificationLevel?
    let onPick: (ChannelNotificationLevel) -> Void

    private static let levels: [(level: ChannelNotificationLevel, title: String)] = [
        (.all, "All Messages"),
        (.mentions, "Only @mentions"),
        (.none, "Nothing")
    ]

    static func title(for level: ChannelNotificationLevel) -> String {
        levels.first { $0.level == level }?.title ?? ""
    }

    var body: some View {
        ForEach(Self.levels, id: \.title) { choice in
            ActionRow(
                title: choice.title,
                systemImage: choice.level == selected ? "largecircle.fill.circle" : "circle"
            ) {
                onPick(choice.level)
            }
        }
    }
}

struct ChannelNotificationsSheet: View {
    let channel: Channel

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SettingsForm {
                Section {
                    LevelRow(level: .all, title: "All Messages", channel: channel)
                    LevelRow(level: .mentions, title: "Only @mentions", channel: channel)
                    LevelRow(level: .none, title: "Nothing", channel: channel)
                } footer: {
                    Text("Replies to you count as mentions. Direct messages notify for every message unless set to nothing.")
                        .wrappingFooter()
                }
            }
            .settingsListStyle()
            .navigationTitle("Notifications")
            .inlineNavigationTitle()
            .toolbar {
                ActionToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: close)
                }
            }
        }
        .sheetDetents([.medium])
        .presentationBackground(Theme.deepBackground)
    }

    private func close() {
        dismiss()
    }
}

private struct LevelRow: View {
    let level: ChannelNotificationLevel
    let title: String
    let channel: Channel

    @Environment(SessionStore.self) private var session

    private var isSelected: Bool {
        session.notificationLevel(for: channel.id) == level
    }

    var body: some View {
        Button(action: select) {
            HStack {
                Text(title)
                    .foregroundStyle(Theme.header)

                Spacer()

                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? Theme.blurple : Theme.muted)
            }
            .contentShape(.rect)
        }
    }

    private func select() {
        Task {
            await session.setNotificationLevel(level, for: channel.id)
        }
    }
}

extension EnvironmentValues {
    // a long press sheet shown as discord's mac right click menu, compact rows by the pointer
    @Entry var isPointerMenu = false
    // a row in a submenu, which keeps the submenu open while the pointer is on it
    @Entry var isInSubmenu = false
}

struct ActionGroup<Content: View>: View {
    // the first in a menu has nothing above it to divide from
    var isFirst = false
    @ViewBuilder let content: Content

    @Environment(\.isPointerMenu) private var isPointerMenu

    // a hairline between rows, inset past the icons, like discord's grouped lists. a menu has
    // one between groups instead
    var body: some View {
        if isPointerMenu {
            VStack(spacing: 0) {
                if isFirst {
                    Color.clear
                        .frame(height: 6)
                } else {
                    Theme.divider
                        .frame(height: 1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                }

                content
            }
        } else {
            groupedRows
        }
    }

    private var groupedRows: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { rows in
                ForEach(rows.indices, id: \.self) { index in
                    rows[index]

                    if index < rows.count - 1 {
                        Theme.divider.frame(height: 1)
                            .padding(.leading, 56)
                    }
                }
            }
        }
        .background(Theme.listBackground, in: .rect(cornerRadius: 14))
        // a row lit under the pointer keeps the group's corners
        .clipShape(.rect(cornerRadius: 14))
    }
}

struct ActionRow: View {
    let title: String
    let systemImage: String
    var tint = Theme.header
    let action: () -> Void

    @Environment(\.isPointerMenu) private var isPointerMenu
    @Environment(\.isInSubmenu) private var isInSubmenu

    @State private var isHovered = false

    private var isDestructive: Bool {
        tint == Theme.red
    }

    private var hoverBackground: Color {
        isDestructive ? Theme.red : Theme.hover
    }

    private var hoverForeground: Color {
        isDestructive ? .white : Theme.header
    }

    var body: some View {
        if isPointerMenu {
            menuRow
        } else {
            sheetRow
        }
    }

    // discord's menu row: a small icon, then the title, filled while the pointer is on it
    private var menuRow: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if !systemImage.isEmpty {
                    Image(systemName: systemImage)
                        .font(.system(size: 13))
                        .frame(width: 18)
                }

                Text(title)
                    .font(.subheadline.weight(.medium))

                Spacer(minLength: 0)
            }
            .foregroundStyle(isHovered ? hoverForeground : tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(isHovered ? hoverBackground : .clear, in: .rect(cornerRadius: 4))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover(perform: setHovered)
    }

    private var sheetRow: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 18))
                    .frame(width: 26)

                Text(title)

                Spacer()
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .hoverHighlight(cornerRadius: 0)
    }

    private func setHovered(_ hovered: Bool) {
        isHovered = hovered

        // the pointer moving on to another row of the menu closes a submenu open beside it
        if hovered && isPointerMenu && !isInSubmenu {
            PointerMenus.hideSubmenu()
        }
    }
}
