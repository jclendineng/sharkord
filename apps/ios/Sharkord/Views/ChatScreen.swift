import SwiftUI

struct ChatScreen: View {
    let channelId: Int

    @Environment(SessionStore.self) private var session
    @Environment(ServerListStore.self) private var servers
    @Environment(\.dismiss) private var dismiss
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

            if canShowMembers && showsMemberList {
                MembersColumn(channelId: channelId)
                    .transition(.opacity)
            }
        }
        .onGeometryChange(for: Bool.self, of: { $0.size.width >= 520 + MembersColumn.width }) { hasRoom in
            hasRoomForMembers = hasRoom
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

                    ChatDropdownPanel(dropdown: dropdown, channelId: channelId, searchModel: searchModel, onClose: closeDropdown)
                        .transition(.move(edge: .top))
                }
            }
            .clipped()
            .animation(.easeOut(duration: 0.2), value: dropdown)
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
                NavigationLink(value: ChannelInfoRoute(channelId: channelId)) {
                    ChatTitle(
                        title: title,
                        partner: partner,
                        isDirectMessage: channel?.isDm == true,
                        group: session.group(for: channelId)
                    )
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded(dismissKeyboard))
            }

            if canShowMembers {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: toggleMemberList) {
                        Image(systemName: showsMemberList ? "person.2.fill" : "person.2")
                            .foregroundStyle(showsMemberList ? Theme.header : Theme.text)
                    }
                    .accessibilityLabel(showsMemberList ? "Hide Member List" : "Show Member List")
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
                }
                .accessibilityLabel("Pinned Messages")
                // pins hang off the button on an ipad, a phone gets a sheet and a mac the
                // dropdown. handed the stores by hand: a popover from the toolbar does not
                // inherit them
                .popover(isPresented: $isPinsPresented) {
                    PinnedMessagesSheet(channelId: channelId)
                        .frame(idealWidth: 420, idealHeight: 560)
                        .environment(session)
                        .environment(servers)
                }
            }

            if ProcessInfo.processInfo.isiOSAppOnMac {
                // discord's mac: the box itself sits in the top bar, the results drop down under
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 8) {
                        SearchBox(
                            model: searchModel,
                            prompt: searchModel.prompt(in: session, directMessages: false),
                            isFocused: $isSearchFocused
                        )
                        .frame(width: 240)

                        FilterMenu(isFiltering: !searchModel.filters.isEmpty, onChoose: chooseFilter)
                    }
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

    private func toggleMemberList() {
        showsMemberList.toggle()
    }

    private func showPins() {
        dismissKeyboard()

        if ProcessInfo.processInfo.isiOSAppOnMac {
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
}

// the mac's pins or search below the top bar, as tall as the window allows
private struct ChatDropdownPanel: View {
    let dropdown: ChatDropdown
    let channelId: Int
    let searchModel: SearchQueryModel
    let onClose: () -> Void

    var body: some View {
        switch dropdown {
        case .pins:
            panel(width: 420, maxHeight: 560) {
                PinnedMessagesSheet(channelId: channelId, onClose: onClose)
            }
        case .search:
            // wide enough for every tab of the strip without it scrolling
            panel(width: 500, maxHeight: 640) {
                NavigationStack {
                    SearchScreen(channelId: channelId, directMessages: false, model: searchModel, showsSearchBox: false)
                }
            }
        }
    }

    private func panel(width: CGFloat, maxHeight: CGFloat, @ViewBuilder content: () -> some View) -> some View {
        content()
            .frame(width: width)
            .frame(maxHeight: maxHeight)
            .background(Theme.deepBackground)
            .clipShape(.rect(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.panelEdge, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
            .padding(.top, 8)
            .padding(.trailing, 12)
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
