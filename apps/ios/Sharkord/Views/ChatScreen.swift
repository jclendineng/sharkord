import SwiftUI

struct ChatScreen: View {
    let channelId: Int

    @Environment(SessionStore.self) private var session
    @Environment(ServerListStore.self) private var servers
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.showChannelList) private var showChannelList
    // set only while the channel list sits beside the chat, see HomeView
    @Environment(\.expandChat) private var expandChat

    @State private var isPinsPresented = false
    @State private var dropdown: ChatDropdown?
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

    // a mac window with room for it beside the conversation, never a direct message
    private var canShowMembers: Bool {
        ProcessInfo.processInfo.isiOSAppOnMac
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
                    .frame(width: 420)
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
        .animation(.easeOut(duration: 0.12), value: showsMemberList)
        // discord's mac pins and search slide down from under the top bar at its right edge,
        // a click anywhere else in the chat puts them away
        .overlay(alignment: .topTrailing) {
            ZStack(alignment: .topTrailing) {
                if let dropdown {
                    Color.clear
                        .contentShape(.rect)
                        .onTapGesture(perform: closeDropdown)

                    // fades and settles in from its corner, as discord's do; slid down from under
                    // the top bar it looked to come out of the bar itself
                    ChatDropdownPanel(dropdown: dropdown, channelId: channelId, searchModel: searchModel, onClose: closeDropdown, onOpenThread: openThreadFromList)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing)))

                    // escape puts it away, as it does the server's search card
                    Button("Close", action: closeDropdown)
                        .keyboardShortcut(.cancelAction)
                        .hidden()
                }
            }
            .animation(.snappy(duration: 0.18), value: dropdown)
        }
        .onChange(of: session.requestedChannelId) { _, requestedChannelId in
            if requestedChannelId != nil {
                closeDropdown()
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            SessionBanners(showsVoiceTakenOver: expandChat == nil)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.chatBackground, for: .navigationBar)
        .toolbarBackgroundVisibility(.visible, for: .navigationBar)
        .toolbarVisibility(.hidden, for: .tabBar)
        .toolbar {
            if let showChannelList {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Channels", systemImage: "chevron.left", action: showChannelList)
                        .tint(Theme.header)
                }
            }

            PlainToolbarItem(placement: .topBarLeading) {
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

            if canShowMembers {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: toggleMemberList) {
                        Image(systemName: isMemberListShown ? "person.2.fill" : "person.2")
                            .foregroundStyle(isMemberListShown ? Theme.header : Theme.text)
                            .hoverPop()
                    }
                    .accessibilityLabel(isMemberListShown ? "Hide Member List" : "Show Member List")
                }
            }

            if canShowThreadPanel {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: showThreads) {
                        Image(systemName: "bubble.left.and.text.bubble.right")
                            .foregroundStyle(Theme.text)
                            .hoverPop()
                    }
                    .accessibilityLabel("Threads")
                }
            }

            if ProcessInfo.processInfo.isiOSAppOnMac && channel?.isDm == false {
                ToolbarItem(placement: .topBarTrailing) {
                    NotificationBell(channelId: channelId)
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button(action: showPins) {
                    Image(systemName: "pin")
                        .foregroundStyle(Theme.text)
                        .hoverPop()
                }
                .accessibilityLabel("Pinned Messages")
                // pins hang off the button on an ipad, a phone and a mac get the dropdown.
                // handed the stores by hand: a popover from the toolbar does not inherit them
                .popover(isPresented: $isPinsPresented) {
                    PinnedMessagesSheet(channelId: channelId)
                        .frame(idealWidth: 420, idealHeight: 560)
                        .environment(session)
                        .environment(servers)
                }
            }

            // discord's mac keeps the inbox at the top right rather than in the user bar
            if ProcessInfo.processInfo.isiOSAppOnMac {
                ToolbarItem(placement: .topBarTrailing) {
                    InboxButton(action: showInbox)
                }
            }

            if ProcessInfo.processInfo.isiOSAppOnMac {
                // discord's mac: the box itself sits in the top bar, the results drop down under.
                // the principal place, the bar's trailing group collapses a text field to nothing
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        SearchBox(
                            model: searchModel,
                            prompt: searchModel.prompt(in: session, directMessages: false),
                            isFocused: $isSearchFocused
                        )
                        .frame(width: 240)

                        FilterMenu(isFiltering: !searchModel.filters.isEmpty, onChoose: chooseFilter)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .topBarTrailing) {
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
            await session.markAsRead(channelId)
        }
        .onDisappear {
            store.isVisible = false
        }
        // a group left, or a channel deleted, takes its chat with it back to the list
        .onChange(of: channel == nil) { _, isGone in
            if isGone {
                dismiss()
            }
        }
    }

    // a mac's channel, threads being a channel's
    private var canShowThreadPanel: Bool {
        ProcessInfo.processInfo.isiOSAppOnMac && channel?.isDm == false
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
        if threadParent != nil {
            threadParent = nil
            showsMemberList = true
            return
        }

        showsMemberList.toggle()
    }

    private func showPins() {
        dismissKeyboard()

        if ProcessInfo.processInfo.isiOSAppOnMac || horizontalSizeClass == .compact {
            toggleDropdown(.pins)
        } else {
            isPinsPresented = true
        }
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

    private func toggleDropdown(_ shown: ChatDropdown) {
        dropdown = dropdown == shown ? nil : shown
    }

    private func closeDropdown() {
        dropdown = nil
        isSearchFocused = false
    }

    // before another screen goes over the chat: swiftui gives a field its focus back when the
    // chat shows again, so a keyboard still up on leaving would come back unasked
    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
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
            .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
            .padding(.top, 8)
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
    }
}

// discord's bell in a server channel's top bar: mute for a while, or which messages notify
private struct NotificationBell: View {
    let channelId: Int

    @Environment(SessionStore.self) private var session

    private var isMuted: Bool {
        session.isMuted(channelId)
    }

    private var level: Binding<ChannelNotificationLevel> {
        Binding(
            get: { session.notificationLevel(for: channelId) },
            set: setLevel
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

            Picker("Notifications", selection: level) {
                Text("All Messages").tag(ChannelNotificationLevel.all)
                Text("Only @mentions").tag(ChannelNotificationLevel.mentions)
                Text("Nothing").tag(ChannelNotificationLevel.none)
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: isMuted ? "bell.slash.fill" : "bell.fill")
                .foregroundStyle(Theme.text)
                .hoverPop()
        }
        .accessibilityLabel("Notification Settings")
    }

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
        .fixedSize()
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
            Image(systemName: "tray.fill")
                .foregroundStyle(Theme.text)
                .hoverPop()
                .overlay(alignment: .topTrailing) {
                    if hasUnread {
                        Circle()
                            .fill(Theme.red)
                            .frame(width: 8, height: 8)
                            .offset(x: 4, y: -3)
                    }
                }
        }
        .accessibilityLabel("Inbox")
    }
}
