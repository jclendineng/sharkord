import SwiftUI

struct ChatScreen: View {
    let channelId: Int

    @Environment(SessionStore.self) private var session
    @Environment(ServerListStore.self) private var servers
    @Environment(\.dismiss) private var dismiss
    @Environment(\.showChannelList) private var showChannelList
    // set only while the channel list sits beside the chat, see HomeView
    @Environment(\.expandChat) private var expandChat

    @State private var dropdown: ChatDropdown?
    @State private var dropdownFrame = CGRect.zero
    // the mac's search box lives in the top bar and types into the dropdown's search
    @State private var searchModel = SearchQueryModel()
    @FocusState private var isSearchFocused: Bool
    // a yes or no rather than the width itself: the width changes every frame of the ipad's
    // card sliding, and redrawing the chat each frame dropped the top bar's buttons until it
    // settled
    @State private var hasRoomForMembers = false
    // the member list grows with a wide mac window, in steps, see MembersColumn
    @State private var membersScale = MembersColumn.minimumScale
    // the mac's thread panel, which takes the member list's place beside the conversation
    @State private var threadParent: Message?
    @State private var chatWidth: CGFloat = 0

    @Environment(\.usesDesktopLayout) private var usesDesktopLayout
    @Environment(\.usesDesktopSearch) private var usesDesktopSearch
    // discord's member list beside a server channel, on by default, the header's button hides it
    @AppStorage("showsMemberList") private var showsMemberList = true

    private var store: ChannelMessagesStore {
        session.messages(for: channelId)
    }

    private var channel: Channel? {
        session.channel(channelId)
    }

    private var partner: PublicUser? {
        session.directMessagePartner(for: channelId)
    }

    private var title: String {
        if channel?.isDm == true {
            return session.conversationTitle(for: channelId)
        }

        return channel?.name ?? ""
    }

    private var canUpload: Bool {
        guard let settings = session.settings, settings.storageUploadEnabled else {
            return false
        }

        return channel?.isDm != true || settings.storageFileSharingInDirectMessages
    }

    // a wide window with room for it beside the conversation, never a direct message. an ipad
    // in landscape has the same room a mac window does, and used to be left out entirely
    private var canShowMembers: Bool {
        (Platform.isMac || Platform.isPad)
            && channel?.isDm == false
            && hasRoomForMembers
    }

    private var conversation: some View {
        MessageListView(store: store) {
            ChannelWelcome(title: title, isDirectMessage: channel?.isDm == true, partner: partner)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if session.can("SEND_MESSAGES", inChannel: channelId) {
                ComposerView(
                    placeholder: channel?.isDm == true ? "Message @\(title)" : "Message #\(title)",
                    canUpload: canUpload,
                    store: store
                )
            } else {
                ReadOnlyComposer()
            }
        }
        // a panel in the keyboard's place never rides the keyboard: the two trade places, or the
        // keyboard comes up over the panel for its search, see AttachPanelModel
        .ignoresSafeArea(store.attachPanel.isHandingOff || store.attachPanel.isOpen ? .keyboard : [], edges: .bottom)
    }

    var body: some View {
        HStack(spacing: 0) {
            conversation
                .environment(\.openThreadPanel, canShowThreadPanel ? openThreadPanel : nil)

            if let threadParent {
                Theme.divider
                    .frame(width: 1)

                ThreadScreen(parent: threadParent, onClose: closeThreadPanel)
                    .frame(width: Platform.isMac ? 420 : min(420, chatWidth * 0.45))
                    .id(threadParent.id)
                    .transition(.opacity)
            } else if canShowMembers && showsMemberList {
                MembersColumn(channelId: channelId, scale: membersScale)
                    .transition(.opacity)
            }
        }
        .onGeometryChange(for: Bool.self, of: { $0.size.width >= 520 + MembersColumn.width * MembersColumn.minimumScale }) { hasRoom in
            hasRoomForMembers = hasRoom
        }
        .onGeometryChange(for: CGFloat.self, of: { MembersColumn.scale(forChatWidth: $0.size.width) }) { scale in
            membersScale = scale
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width in
            chatWidth = width
        }
        // a rotation that takes the room away puts the panel's thread away with it
        .onChange(of: canShowThreadPanel) { _, canShow in
            if !canShow {
                threadParent = nil
            }
        }
        .animation(.easeOut(duration: 0.12), value: showsMemberList)
        // a mac click in the chat puts the panel away and still opens what it landed on, a
        // person's profile or a link, where the catcher below would take the click for itself
        .simultaneousGesture(
            TapGesture().onEnded(closeDropdown),
            isEnabled: dropdown != nil && Platform.isMac
        )
        // discord's mac pins and search slide down from under the top bar at its right edge,
        // a click anywhere else in the chat puts them away
        .overlay(alignment: .topTrailing) {
            ZStack(alignment: .topTrailing) {
                if let dropdown {
                    if !Platform.isMac {
                        Color.clear
                            .contentShape(.rect)
                            .onTapGesture(perform: closeDropdown)
                    }

                    // fades and settles in from its corner, as discord's do; slid down from under
                    // the top bar it looked to come out of the bar itself
                    ChatDropdownPanel(dropdown: dropdown, channelId: channelId, searchModel: searchModel, onClose: closeDropdown, onOpenThread: openThreadFromList)
                        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { frame in
                            dropdownFrame = frame
                        }
                        .popTransition(scale: 0.96, anchor: .topTrailing)

                    // escape puts it away, as it does the server's search card
                    Button("Close", action: closeDropdown)
                        .keyboardShortcut(.cancelAction)
                        .hidden()
                }
            }
            .animation(.snappy(duration: 0.18), value: dropdown)
        }
        .onChange(of: dropdown != nil) { _, isOpen in
            servers.isChatDropdownOpen = isOpen
        }
        .onChange(of: servers.chatDropdownDismissals) {
            closeDropdown()
        }
        // a right click elsewhere in the window puts it away as a click does, and opens its own
        // menu as well
        .onChange(of: PointerMenuState.shared.rightClicks) {
            closeDropdownOnRightClick()
        }
        .onChange(of: session.requestedChannelId) { _, requestedChannelId in
            if requestedChannelId != nil {
                closeDropdown()
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            SessionBanners(showsVoiceTakenOver: expandChat == nil)
        }
        // the chat's own buttons, applied under the toolbar so the bar keeps its own
        .phoneButtons()
        .inlineNavigationTitle()
        .navigationBarBackground(Theme.chatBackground)
        .navigationBarBackgroundVisible()
        .tabBarHidden()
        .toolbar {
            if let showChannelList {
                ToolbarItem(placement: .barLeading) {
                    Button("Channels", systemImage: "chevron.left", action: showChannelList)
                        .tint(Theme.header)
                }
            }

            PlainToolbarItem(placement: .barLeading) {
                ChatTitle(
                    title: title,
                    partner: partner,
                    isDirectMessage: channel?.isDm == true,
                    group: session.group(for: channelId)
                )
                // the link laid over the title rather than around it: an item that is only a link
                // is drawn by the mac's bar as a button showing nothing but its first icon
                .overlay {
                    NavigationLink(value: ChannelInfoRoute(channelId: channelId)) {
                        Color.clear
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded(dismissKeyboard))
                }
            }

            // discord's mac: the search box and one flat row of icons, each the same size and the
            // same distance apart. the bar's own glass grouped them into capsules of two, the
            // bell's menu with a chevron
            if Platform.isMac {
                PlainToolbarItem(placement: .barTrailing) {
                    HStack(spacing: 4) {
                        // with the icons rather than in the middle of the bar, where it took the
                        // room they needed and a narrow window put them away under a chevron
                        if usesDesktopSearch {
                            desktopSearch
                                .padding(.trailing, 8)
                        }

                        if canShowThreadPanel {
                            HeaderButton(title: "Threads", systemImage: "bubble.left.and.text.bubble.right", action: showThreads)
                        }

                        if channel?.isDm == false {
                            NotificationBell(channelId: channelId)
                        }

                        HeaderButton(title: "Pinned Messages", systemImage: "pin.fill", action: showPins)

                        if canShowMembers {
                            HeaderButton(
                                title: isMemberListShown ? "Hide Member List" : "Show Member List",
                                systemImage: "person.2.fill",
                                isOn: isMemberListShown,
                                action: toggleMemberList
                            )
                        }

                        InboxButton(action: showInbox)
                    }
                }
            } else {
                if canShowMembers {
                    ToolbarItem(placement: .barTrailing) {
                        Button(action: toggleMemberList) {
                            Image(systemName: isMemberListShown ? "person.2.fill" : "person.2")
                                .foregroundStyle(isMemberListShown ? Theme.header : Theme.text)
                                .hoverPop()
                        }
                        .accessibilityLabel(isMemberListShown ? "Hide Member List" : "Show Member List")
                        // the icon grows under the pointer, as discord's do. the system's own circle drawn behind
                        // it on top of that read as a shadow
                        .noHoverEffect()
                    }
                }

                if canShowThreadPanel {
                    ToolbarItem(placement: .barTrailing) {
                        Button(action: showThreads) {
                            Image(systemName: "bubble.left.and.text.bubble.right")
                                .foregroundStyle(Theme.text)
                                .hoverPop()
                        }
                        .accessibilityLabel("Threads")
                        .noHoverEffect()
                    }
                }

                ToolbarItem(placement: .barTrailing) {
                    Button(action: showPins) {
                        Image(systemName: "pin")
                            .foregroundStyle(Theme.text)
                            .hoverPop()
                    }
                    .accessibilityLabel("Pinned Messages")
                    .noHoverEffect()
                }
            }

            if hasDesktopRoom && usesDesktopSearch {
                // the box itself sits in the top bar, the results drop down under. a wide ipad's
                // in the middle of the bar, a mac's in its icon row
                if !Platform.isMac {
                    ToolbarItem(placement: .principal) {
                        desktopSearch
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
            } else {
                ToolbarItem(placement: .barTrailing) {
                    SearchLink(route: SearchRoute(channelId: channelId)) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(Theme.text)
                    }
                    .simultaneousGesture(TapGesture().onEnded(dismissKeyboard))
                    .accessibilityLabel("Search")
                }
            }
        }
        .onChange(of: isSearchFocused) { _, isFocused in
            if isFocused {
                dropdown = .search
            }
        }
        .onChange(of: searchModel.query) { _, query in
            if !query.isEmpty {
                dropdown = .search
            }
        }
        .onChange(of: searchModel.focusRequest) {
            isSearchFocused = true
        }
        .task {
            searchModel.applyOpening(channel: channel, directMessages: false)
            servers.recordVisit(to: channelId, in: session)
            session.rememberChannel(channelId)
            session.shownChannelId = channelId
            store.isVisible = true

            let unreadCount = session.unreadCounts[channelId, default: 0]

            await store.loadIfNeeded()
            store.setUnreadMarker(count: unreadCount)
            await jumpToFirstUnreadIfAsked()
            await session.markAsRead(channelId)
        }
        .onDisappear {
            servers.isChatDropdownOpen = false
            store.isVisible = false
        }
        // a jump asked for while this chat is already open, by a tapped notification or a search
        // result in it, which the task above only makes when the chat first appears
        .onChange(of: store.pendingJumpMessageId) { _, messageId in
            if messageId != nil {
                Task {
                    await store.loadIfNeeded()
                }
            }
        }
        // the same for an unread channel picked in the inbox while its chat is already open
        .onChange(of: store.pendingJumpToFirstUnread) { _, isAsked in
            if isAsked {
                Task {
                    store.setUnreadMarker(count: session.unreadCounts[channelId, default: 0])
                    await jumpToFirstUnreadIfAsked()
                    await session.markAsRead(channelId)
                }
            }
        }
        // a group left, or a channel deleted, takes its chat with it back to the list
        .onChange(of: channel == nil) { _, isGone in
            if isGone {
                dismiss()
            }
        }
    }

    // the desktop layout's top bar and thread panel, once the chat is wide enough for them beside
    // the conversation. an ipad in portrait is not, and pushes threads and opens search from
    // its magnifier instead
    private var desktopSearch: some View {
        HStack(spacing: 8) {
            SearchBox(
                model: searchModel,
                prompt: searchModel.prompt(in: session, directMessages: false),
                isFocused: $isSearchFocused
            )
            .frame(width: 240)

            FilterMenu(isFiltering: searchModel.filters.narrowsPastChannel, onChoose: chooseFilter)
        }
    }

    private var hasDesktopRoom: Bool {
        Platform.isMac || (usesDesktopLayout && chatWidth >= 640)
    }

    // a channel's threads, never a direct message's
    private var canShowThreadPanel: Bool {
        hasDesktopRoom && channel?.isDm == false
    }

    private func openThreadPanel(_ parent: Message) {
        threadParent = parent
    }

    private func openThreadFromList(_ parent: Message) {
        closeDropdown()
        threadParent = parent
    }

    private func showThreads() {
        toggleDropdown(.threads)
    }

    private func showInbox() {
        toggleDropdown(.inbox)
    }

    private func closeThreadPanel() {
        threadParent = nil
    }

    // on screen, not just wanted: a thread panel stands in its place
    private var isMemberListShown: Bool {
        showsMemberList && threadParent == nil
    }

    // the thread panel stands in the member list's place, so the button brings the list back
    // in its stead rather than doing nothing under it
    private func toggleMemberList() {
        // the inbox or pins over the list would hide what it just showed
        closeDropdown()

        if threadParent != nil {
            threadParent = nil
            showsMemberList = true
            return
        }

        showsMemberList.toggle()
    }

    private func showPins() {
        dismissKeyboard()

        toggleDropdown(.pins)
    }

    // a filter picked from the menu beside the box goes in as its token, the dropdown listing
    // its choices; a date filter is picked in the dropdown, which owns the date wheel
    private func chooseFilter(_ picker: FilterPicker) {
        dropdown = .search

        if picker.isDate {
            searchModel.pendingDatePicker = picker
            return
        }

        searchModel.token = picker
        searchModel.query = ""
        isSearchFocused = true
    }

    private func jumpToFirstUnreadIfAsked() async {
        guard store.pendingJumpToFirstUnread else {
            return
        }

        store.pendingJumpToFirstUnread = false

        // read on another device by now, the chat stays where it opened rather than going to
        // the oldest message loaded
        guard store.unreadMarker != nil else {
            return
        }

        await store.jumpToFirstUnread()
        store.unreadMarker = nil
    }

    private func toggleDropdown(_ shown: ChatDropdown) {
        dropdown = dropdown == shown ? nil : shown
    }

    private func closeDropdown() {
        dropdown = nil
        isSearchFocused = false
    }

    private func closeDropdownOnRightClick() {
        let point = PointerMenuState.shared.rightClickPoint

        if dropdown != nil, !dropdownFrame.contains(point) {
            closeDropdown()
        }
    }

    // before another screen goes over the chat: swiftui gives a field its focus back when the
    // chat shows again, so a keyboard still up on leaving would come back unasked
    private func dismissKeyboard() {
        Platform.dismissKeyboard()
    }
}

private enum ChatDropdown {
    case pins
    case search
    case threads
    case inbox
}

// pins, search, threads or the inbox below the top bar, as tall as the window allows
private struct ChatDropdownPanel: View {
    let dropdown: ChatDropdown
    let channelId: Int
    let searchModel: SearchQueryModel
    let onClose: () -> Void
    let onOpenThread: (Message) -> Void

    var body: some View {
        switch dropdown {
        case .pins:
            panel(width: 420, maxHeight: 560) {
                PinnedMessagesSheet(channelId: channelId, onClose: onClose)
            }
        case .inbox:
            panel(width: 420, maxHeight: 560) {
                InboxSheet(onClose: onClose)
            }
        case .threads:
            panel(width: 420, maxHeight: 560) {
                ThreadsListPanel(channelId: channelId, onOpen: onOpenThread)
            }
        case .search:
            // wide enough for every tab of the strip without it scrolling
            panel(width: 500, maxHeight: 640) {
                SearchScreen(channelId: channelId, directMessages: false, model: searchModel, showsSearchBox: false)
            }
        }
    }

    private func panel(width: CGFloat, maxHeight: CGFloat, @ViewBuilder content: () -> some View) -> some View {
        // as wide as a phone allows, less the margins
        content()
            .frame(maxWidth: width)
            .frame(maxHeight: maxHeight)
            .background(Theme.deepBackground)
            .clipShape(.rect(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.panelEdge, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
            // one layer with its shadow: faded on its own, the shadow showed through the half clear
            // card as a dark box
            .compositingGroup()
            .padding(.top, 8)
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
    }
}

// discord's bell in a server channel's top bar: mute for a while, or which messages notify
private struct NotificationBell: View {
    let channelId: Int

    @Environment(SessionStore.self) private var session
    @Environment(ServerListStore.self) private var servers

    #if os(macOS)
    @State private var clickWatch = BellClickWatch()
    #endif

    private var isMuted: Bool {
        session.isMuted(channelId)
    }

    private func isLevel(_ level: ChannelNotificationLevel) -> Binding<Bool> {
        Binding(
            get: { session.notificationLevel(for: channelId) == level },
            set: { isOn in
                if isOn {
                    setLevel(level)
                }
            }
        )
    }

    var body: some View {
        Menu {
            if isMuted {
                Button("Unmute Channel", action: unmute)
            } else {
                Menu("Mute Channel") {
                    ForEach(MuteDuration.allCases) { duration in
                        Button(duration.title) {
                            mute(for: duration)
                        }
                    }
                }
            }

            Divider()

            // toggles rather than an inline picker, which a mac menu drew greyed out with a
            // stray checkmark row of its own. the window's phone switch style has to be undone
            // here too: a menu cannot draw it, and showed the same greyed rows
            Section("Notifications") {
                Toggle("All Messages", isOn: isLevel(.all))
                Toggle("Only @mentions", isOn: isLevel(.mentions))
                Toggle("Nothing", isOn: isLevel(.none))
            }
            .toggleStyle(.automatic)
        } label: {
            HeaderIcon(systemImage: isMuted ? "bell.slash.fill" : "bell.fill")
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityLabel("Notification Settings")
        .help("Notification Settings")
        #if os(macOS)
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { frame in
            clickWatch.frame = frame
        }
        .onAppear(perform: watchClicks)
        .onDisappear(perform: clickWatch.stop)
        #endif
    }

    #if os(macOS)
    private func watchClicks() {
        let servers = servers

        clickWatch.start {
            if servers.isChatDropdownOpen {
                servers.chatDropdownDismissals += 1
            }
        }
    }
    #endif

    private func setLevel(_ newLevel: ChannelNotificationLevel) {
        Task {
            await session.setNotificationLevel(newLevel, for: channelId)
        }
    }

    private func mute(for duration: MuteDuration) {
        Task {
            await session.setNotificationLevel(.none, for: channelId, muteForMinutes: duration.minutes)
        }
    }

    private func unmute() {
        setLevel(.mentions)
    }
}

#if os(macOS)
// a mac menu opens on the mouse going down and tracks the pointer itself, so no swiftui gesture
// on the bell hears the click. this does, and puts the chat's open panel away as any other click
// outside it would
private final class BellClickWatch {
    var frame = CGRect.zero

    private var monitor: Any?

    func start(onClick: @escaping () -> Void) {
        guard monitor == nil else {
            return
        }

        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            if let self, let content = event.window?.contentView {
                let point = content.convert(event.locationInWindow, from: nil)

                if frame.contains(point) {
                    onClick()
                }
            }

            return event
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }

        monitor = nil
    }
}
#endif

// an icon in the mac's header row, the same size as the search filter beside it
private struct HeaderIcon: View {
    let systemImage: String
    var isOn = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(isOn ? Theme.header : Theme.muted)
            .frame(width: 36, height: 36)
            .contentShape(.rect)
            .hoverHighlight(cornerRadius: 8)
    }
}

private struct HeaderButton: View {
    let title: String
    let systemImage: String
    var isOn = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HeaderIcon(systemImage: systemImage, isOn: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .help(title)
    }
}

// ios 26 wraps every toolbar item in a glass capsule, which makes a plain title look like a
// button that does nothing
private struct PlainToolbarItem<Content: View>: ToolbarContent {
    let placement: ToolbarItemPlacement
    @ViewBuilder let content: Content

    var body: some ToolbarContent {
        ToolbarItem(placement: placement) {
            content
        }
        .sharedBackgroundVisibility(.hidden)
    }
}

// discord's header: the name with a chevron, and who is around under it
private struct ChatTitle: View {
    let title: String
    let partner: PublicUser?
    let isDirectMessage: Bool
    var group: GroupInfo?

    @Environment(SessionStore.self) private var session

    private var subtitle: String {
        if let group {
            return "\(group.memberIds.count + 1) Members"
        }

        if isDirectMessage {
            switch partner?.status {
            case .online:
                return "Online"
            case .idle:
                return "Idle"
            case .dnd:
                return "Do Not Disturb"
            case .offline, nil:
                return "Offline"
            }
        }

        return "\(session.onlineCount) Online"
    }

    private var isOnline: Bool {
        isDirectMessage ? partner?.status == .online : session.onlineCount > 0
    }

    // discord's: the person's own status line under their name, their presence already sits on
    // the avatar beside it
    private var customStatus: String? {
        guard isDirectMessage, group == nil, let text = partner?.customStatus, !text.isEmpty else {
            return nil
        }

        return text
    }

    var body: some View {
        HStack(spacing: 8) {
            if group != nil {
                GroupAvatar(size: 30)
            } else if isDirectMessage {
                AvatarView(user: partner, size: 30, showsStatus: true)
            }

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    if !isDirectMessage {
                        Image(systemName: "number")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.muted)
                    }

                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Theme.header)
                        .lineLimit(1)

                    Image(systemName: "chevron.right")
                        .font(.caption2.bold())
                        .foregroundStyle(Theme.muted)
                }

                HStack(spacing: 4) {
                    if let customStatus {
                        Image(systemName: "bubble.left.fill")
                            .font(.caption2)
                            .foregroundStyle(Theme.muted)

                        Text(customStatus)
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    } else {
                        // a direct message's presence is already on the avatar beside it
                        if !isDirectMessage || group != nil {
                            Circle()
                                .fill(isOnline ? Theme.green : Theme.muted)
                                .frame(width: 7, height: 7)
                        }

                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
        }
        // a fixed slot rather than a fixed-size title: .fixedSize() forced the whole name into
        // the bar and pushed search and pins off, while an unbounded text collapsed to a couple
        // of characters under the toolbar's minimum width. a slot truncates a long name instead
        .frame(width: Platform.isPad ? 220 : 160, alignment: .leading)
    }
}

private struct ChannelWelcome: View {
    let title: String
    let isDirectMessage: Bool
    let partner: PublicUser?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isDirectMessage {
                AvatarView(user: partner, size: 72)
            } else {
                Image(systemName: "number")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(Theme.header)
                    .frame(width: 68, height: 68)
                    .background(Theme.hover, in: .circle)
            }

            Text(isDirectMessage ? title : "Welcome to #\(title)!")
                .font(.title.bold())
                .foregroundStyle(Theme.header)

            Text(isDirectMessage
                ? "This is the beginning of your direct message history with \(title)."
                : "This is the start of the #\(title) channel.")
                .foregroundStyle(Theme.muted)
        }
        .padding(16)
        .padding(.top, 24)
    }
}

// where the message box would be in a channel this account can read but not post in
private struct ReadOnlyComposer: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")

            Text("You do not have permission to send messages in this channel.")
                .lineLimit(2)
        }
        .font(.subheadline)
        .foregroundStyle(Theme.muted)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(Theme.inputBackground, in: .rect(cornerRadius: 20))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.chatBackground.ignoresSafeArea())
    }
}

// drops down under the top bar as pins and threads do
private struct InboxButton: View {
    let action: () -> Void

    @Environment(ServerListStore.self) private var servers

    private var hasUnread: Bool {
        servers.sessions.contains { !$0.unreadChannels.isEmpty }
    }

    var body: some View {
        Button(action: action) {
            HeaderIcon(systemImage: "tray.fill")
                .overlay(alignment: .topTrailing) {
                    if hasUnread {
                        Circle()
                            .fill(Theme.red)
                            .frame(width: 8, height: 8)
                            .offset(x: -8, y: 8)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Inbox")
        .help("Inbox")
    }
}
