import SwiftUI

struct ChannelListPanel: View {
    @Environment(ServerListStore.self) private var servers
    @Environment(SessionStore.self) private var session

    @State private var collapsedCategoryIds: Set<Int> = []
    @State private var isInvitePresented = false
    @State private var isServerSheetPresented = false
    // what the mac's server dropdown opened, shown here once it has closed
    @State private var menuSheet: ServerMenuSheet?

    private let isOnMac = ProcessInfo.processInfo.isiOSAppOnMac

    // a sheet on a phone or ipad, discord's dropdown under the server name on a mac
    private var isServerSheetShown: Binding<Bool> {
        Binding(
            get: { !isOnMac && isServerSheetPresented },
            set: { isServerSheetPresented = $0 }
        )
    }

    private var isServerMenuShown: Binding<Bool> {
        Binding(
            get: { isOnMac && isServerSheetPresented },
            set: { isServerSheetPresented = $0 }
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                header

                ForEach(session.channelSections) { section in
                    if let title = section.title {
                        CategoryHeader(
                            title: title,
                            category: session.categories.first { $0.id == section.id },
                            isCollapsed: collapsedCategoryIds.contains(section.id),
                            onToggle: { toggle(section.id) }
                        )
                    }

                    ForEach(visibleChannels(in: section)) { channel in
                        ChannelRow(
                            channel: channel,
                            unreadCount: session.unreadCounts[channel.id, default: 0],
                            isSelected: channel.id == session.lastChannelId
                        )
                        .accessibilityIdentifier("\(channel.type == .text ? "channel" : "voice")-\(channel.id)")

                        if channel.type == .voice {
                            VoiceParticipants(channelId: channel.id)
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            SessionBanners()
        }
        // handed over by hand: on a mac a sheet's background is worked out before it inherits
        // anything, so a sheet reading a store it was not given crashed on opening
        .sheet(isPresented: $isInvitePresented) {
            InviteSheet()
                .environment(session)
                .environment(servers)
                .appSheet()
        }
        .sheet(isPresented: isServerSheetShown) {
            ServerSheet()
                .environment(session)
                .environment(servers)
                .appSheet(addsClose: true)
        }
        .serverMenuSheet($menuSheet)
        .onChange(of: servers.serverSheetRequest, initial: true) { _, request in
            guard request == ObjectIdentifier(session) else {
                return
            }

            servers.serverSheetRequest = nil
            isServerSheetPresented = true
        }
    }

    // scrolls away with the channels, like discord
    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: showServerSheet) {
                PanelHeader(title: session.serverName) {
                    Image(systemName: isOnMac ? "chevron.down" : "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, -8)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .popover(isPresented: isServerMenuShown, arrowEdge: .top) {
                ServerSheet(onOpen: openFromMenu)
                    .frame(width: 360, height: 600)
                    .macPopover()
                    .environment(session)
                    .environment(servers)
            }

            HStack(spacing: 8) {
                SearchLink(route: SearchRoute()) {
                    Label("Search", systemImage: "magnifyingglass")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(Theme.panelControl, in: .rect(cornerRadius: 12))
                }

                Button("Invite", systemImage: "person.badge.plus", action: showInvite)
                    .labelStyle(.iconOnly)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .frame(width: 44, height: 40)
                    .background(Theme.panelControl, in: .rect(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 4)
            .padding(.bottom, 10)

            Theme.divider.frame(height: 1)
                .padding(.horizontal, 4)
        }
    }

    private func showServerSheet() {
        isServerSheetPresented = true
    }

    private func openFromMenu(_ sheet: ServerMenuSheet) {
        isServerSheetPresented = false
        menuSheet = sheet
    }

    private func showInvite() {
        isInvitePresented = true
    }

    // a collapsed category still shows its unread channels, like discord
    private func visibleChannels(in section: SessionStore.ChannelSection) -> [Channel] {
        guard collapsedCategoryIds.contains(section.id) else {
            return section.channels
        }

        return section.channels.filter { session.unreadCounts[$0.id, default: 0] > 0 }
    }

    private func toggle(_ categoryId: Int) {
        withAnimation(.snappy) {
            if collapsedCategoryIds.contains(categoryId) {
                collapsedCategoryIds.remove(categoryId)
            } else {
                collapsedCategoryIds.insert(categoryId)
            }
        }
    }
}

private struct CategoryHeader: View {
    let title: String
    // nil for the pinned section, which has nothing of its own to set
    let category: ChannelCategory?
    let isCollapsed: Bool
    let onToggle: () -> Void

    @Environment(SessionStore.self) private var session
    @Environment(ServerListStore.self) private var servers

    @State private var isActionsPresented = false
    @State private var isPressed = false
    @State private var isHovered = false
    @State private var menuAnchor = UnitPoint.center
    @State private var wantedSheet: WantedSheet?
    @State private var shownSheet: WantedSheet?

    // what the menu asked for, opened once it has gone
    private enum WantedSheet: String, Identifiable {
        case mute
        case edit
        case createChannel

        var id: String {
            rawValue
        }
    }

    var body: some View {
        // plain gestures, as a channel row has, so a long press does not also collapse it
        label
            .onHover(perform: setHovered)
            .onTapGesture(perform: onToggle)
            .onLongPressGesture(minimumDuration: 0.3, perform: showActions, onPressingChanged: setPressed)
            .onSecondaryClick(perform: showActionsAtPointer)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "More Options", showActions)
            .actionsPresentation(isPresented: $isActionsPresented, anchor: menuAnchor, onDismiss: showWantedSheet) {
                if let category {
                    CategoryActionsSheet(
                        category: category,
                        onMute: { request(.mute) },
                        onEdit: { request(.edit) },
                        onCreateChannel: { request(.createChannel) }
                    )
                    .environment(session)
                    .environment(servers)
                }
            }
            .sheet(item: $shownSheet) { sheet in
                if let category {
                    wanted(sheet, for: category)
                        .environment(session)
                        .environment(servers)
                        .appSheet()
                }
            }
    }

    @ViewBuilder
    private func wanted(_ sheet: WantedSheet, for category: ChannelCategory) -> some View {
        switch sheet {
        case .mute:
            MuteDurationSheet(title: "Mute Category", subtitle: category.name, channelIds: session.channelIds(in: category.id))
        case .edit:
            CategoryEditor(category: category)
        case .createChannel:
            NewChannelSheet(
                type: .text,
                categories: session.categories.sorted { $0.position < $1.position },
                categoryId: category.id
            )
        }
    }

    private func request(_ sheet: WantedSheet) {
        wantedSheet = sheet
        isActionsPresented = false
    }

    private func showWantedSheet() {
        shownSheet = wantedSheet
        wantedSheet = nil
    }

    private func showActions() {
        guard category != nil else {
            return
        }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        // the menu takes over from the press, the header lets go as it rises
        isPressed = false
        isActionsPresented = true
    }

    private func showActionsAtPointer(_ click: SecondaryClick) {
        guard category != nil else {
            return
        }

        menuAnchor = click.anchor
        isActionsPresented = true
    }

    // pressed or under the pointer, as a channel row is, and on a mac while its menu is beside it
    private var isHighlighted: Bool {
        isPressed || isHovered || (isOnMac && isActionsPresented)
    }

    private let isOnMac = ProcessInfo.processInfo.isiOSAppOnMac

    private var label: some View {
        HStack(spacing: 4) {
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .bold))
                .rotationEffect(.degrees(isCollapsed ? -90 : 0))

            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .tracking(0.3)

            Spacer()
        }
        .foregroundStyle(isHighlighted ? Theme.header : Theme.muted)
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .background(isHighlighted ? Theme.panelSelected : .clear, in: .rect(cornerRadius: 6))
        .animation(isHighlighted ? nil : .easeOut(duration: 0.15), value: isHighlighted)
        // the gap above stays out of the highlight, and out of reach of a press
        .padding(.top, 14)
        .contentShape(.rect)
    }

    private func setPressed(_ pressed: Bool) {
        // the pinned section has no menu, a press there only collapses it
        isPressed = pressed && category != nil
    }

    private func setHovered(_ hovered: Bool) {
        isHovered = hovered
    }
}

private struct ChannelRow: View {
    @Environment(SessionStore.self) private var session
    @Environment(ServerListStore.self) private var servers

    @State private var isVoiceSheetPresented = false
    @State private var isActionsSheetPresented = false
    @State private var menuAnchor = UnitPoint.center
    // see ConversationRow, the mute lengths open once the menu has gone
    @State private var wantsMute = false
    @State private var isMutePresented = false
    @State private var wantsInvite = false
    @State private var isInvitePresented = false
    @State private var wantsEdit = false
    @State private var isEditPresented = false
    @State private var isPressed = false
    @State private var isHovered = false

    let channel: Channel
    let unreadCount: Int
    let isSelected: Bool

    private var isMuted: Bool {
        session.isMuted(channel.id)
    }

    private var isUnread: Bool {
        unreadCount > 0 && !isMuted
    }

    private var foreground: Color {
        isSelected || isUnread ? Theme.header : Theme.muted
    }

    private var icon: String {
        switch channel.type {
        case .text:
            "number"
        case .voice:
            "speaker.wave.2.fill"
        }
    }

    var body: some View {
        // plain gestures rather than a link or button: a recognised long press cancels the
        // tap, where a button still fires when the finger lifts after one
        label
            .background(isHighlighted ? Theme.panelSelected : .clear, in: .rect(cornerRadius: 6))
            // on at once under the finger, a quick fade as it lets go
            .animation(isHighlighted ? nil : .easeOut(duration: 0.15), value: isHighlighted)
            .onHover(perform: setHovered)
            .onTapGesture(perform: open)
            .onLongPressGesture(minimumDuration: 0.3, perform: showActions, onPressingChanged: setPressed)
            .onSecondaryClick(perform: showActionsAtPointer)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "More Options", showActions)
            .actionsPresentation(isPresented: $isActionsSheetPresented, anchor: menuAnchor, onDismiss: showWantedSheet) {
                ChannelActionsSheet(channel: channel, onMute: requestMute, onInvite: requestInvite, onEdit: requestEdit)
                    .environment(session)
                    .environment(servers)
            }
            .sheet(isPresented: $isMutePresented) {
                MuteDurationSheet(title: "Mute Channel", subtitle: "#\(channel.name)", channelIds: [channel.id])
                    .environment(session)
                    .environment(servers)
                    .appSheet()
            }
            .sheet(isPresented: $isInvitePresented) {
                InviteSheet()
                    .environment(session)
                    .environment(servers)
                    .appSheet()
            }
            .sheet(isPresented: $isEditPresented) {
                NavigationStack {
                    ChannelEditor(channel: channel)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel", action: closeEditor)
                            }
                        }
                }
                .environment(session)
                .environment(servers)
                .appSheet()
            }
            .sheet(isPresented: $isVoiceSheetPresented) {
                VoiceChannelSheet(channel: channel)
                    .environment(session)
                    .environment(servers)
                    .appSheet()
            }
    }

    private func open() {
        switch channel.type {
        case .text:
            session.requestedChannelId = channel.id
        case .voice:
            showVoiceSheet()
        }
    }

    // pressed or under the pointer, as discord lights a channel up, and on a mac while its menu
    // is beside it. a phone's menu covers the list, so the row lets go the moment it rises
    private var isHighlighted: Bool {
        isPressed || (!isSelected && (isHovered || (isOnMac && isActionsSheetPresented)))
    }

    private let isOnMac = ProcessInfo.processInfo.isiOSAppOnMac

    private func setPressed(_ pressed: Bool) {
        isPressed = pressed
    }

    private func setHovered(_ hovered: Bool) {
        isHovered = hovered
    }

    private func requestMute() {
        wantsMute = true
        isActionsSheetPresented = false
    }

    private func requestInvite() {
        wantsInvite = true
        isActionsSheetPresented = false
    }

    private func closeEditor() {
        isEditPresented = false
    }

    private func requestEdit() {
        wantsEdit = true
        isActionsSheetPresented = false
    }

    private func showWantedSheet() {
        if wantsEdit {
            wantsEdit = false
            isEditPresented = true
        }

        if wantsMute {
            wantsMute = false
            isMutePresented = true
        }

        if wantsInvite {
            wantsInvite = false
            isInvitePresented = true
        }
    }

    // like discord, a voice channel shows who is in it before anyone joins
    private func showVoiceSheet() {
        isVoiceSheetPresented = true
    }

    private func showActions() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        isPressed = false
        isActionsSheetPresented = true
    }

    private func showActionsAtPointer(_ click: SecondaryClick) {
        menuAnchor = click.anchor
        isActionsSheetPresented = true
    }

    private var label: some View {
        HStack(spacing: 8) {
            // discord's: the channel's own symbol with a small lock on it when it is private
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .frame(width: 24)
                .overlay(alignment: .topTrailing) {
                    if channel.private {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 8, weight: .bold))
                            .padding(1.5)
                            .background(Theme.panelBackground, in: .circle)
                            .offset(x: 2, y: -2)
                    }
                }

            Text(channel.name)
                .font(.body.weight(isUnread ? .semibold : .medium))
                .lineLimit(1)

            Spacer()

            if isMuted {
                Image(systemName: "bell.slash.fill")
                    .font(.caption)
            }
        }
        .foregroundStyle(foreground)
        .opacity(isMuted && !isSelected ? 0.5 : 1)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(isSelected ? Theme.panelSelected : .clear, in: .rect(cornerRadius: 8))
        .contentShape(.rect)
        .overlay(alignment: .leading) {
            if isUnread {
                UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: 4, topTrailingRadius: 4)
                    .fill(Theme.header)
                    .frame(width: 4, height: 8)
                    .offset(x: -8)
            }
        }
    }
}

private struct VoiceParticipants: View {
    @Environment(SessionStore.self) private var session

    let channelId: Int

    var body: some View {
        if session.hidesNames(in: channelId) {
            faces
        } else {
            rows
        }
    }

    // discord's hidden names: just the faces, side by side under the channel
    private var faces: some View {
        HStack(spacing: 4) {
            ForEach(session.voiceParticipants(in: channelId), id: \.user?.id) { participant in
                AvatarView(user: participant.user, size: 22)
                    .overlay {
                        if participant.user.map({ session.speakingUserIds.contains($0.id) }) == true {
                            Circle()
                                .strokeBorder(Theme.green, lineWidth: 2)
                                .padding(-2)
                        }
                    }
            }
        }
        .padding(.leading, 40)
        .padding(.vertical, 3)
    }

    private var rows: some View {
        ForEach(session.voiceParticipants(in: channelId), id: \.user?.id) { participant in
            VoiceParticipantRow(user: participant.user, state: participant.state, channelId: channelId)
        }
    }
}

// someone in a voice channel under it in the list: a tap opens their profile, a long press or a
// right click their menu, with moving them for anyone who can. tall enough to hit apart from the
// channel below, and lit while pressed as a channel row is
private struct VoiceParticipantRow: View {
    let user: PublicUser?
    let state: VoiceUserState
    let channelId: Int

    @Environment(SessionStore.self) private var session
    @Environment(ServerListStore.self) private var servers

    @State private var isMenuPresented = false
    @State private var isProfilePresented = false
    @State private var wantsProfile = false
    @State private var menuAnchor = UnitPoint.center
    @State private var isPressed = false
    @State private var isHovered = false

    private let isOnMac = ProcessInfo.processInfo.isiOSAppOnMac

    private var isHighlighted: Bool {
        isPressed || isHovered || (isOnMac && isMenuPresented)
    }

    private var isSpeaking: Bool {
        user.map { session.speakingUserIds.contains($0.id) } ?? false
    }

    var body: some View {
        label
            .background(isHighlighted ? Theme.panelSelected : .clear, in: .rect(cornerRadius: 6))
            .animation(isHighlighted ? nil : .easeOut(duration: 0.15), value: isHighlighted)
            .padding(.leading, 32)
            .onHover(perform: setHovered)
            .onTapGesture(perform: showProfile)
            .onLongPressGesture(minimumDuration: 0.3, perform: showMenu, onPressingChanged: setPressed)
            .onSecondaryClick(perform: showMenuAtPointer)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "More Options", showMenu)
            .actionsPresentation(isPresented: $isMenuPresented, anchor: menuAnchor, onDismiss: showWantedProfile) {
                if let user {
                    MemberActionsSheet(
                        user: user,
                        channelId: nil,
                        onShowProfile: requestProfile,
                        onMessage: openDirectMessage,
                        voiceChannelId: channelId
                    )
                    .environment(session)
                    .environment(servers)
                }
            }
            .sheet(isPresented: $isProfilePresented) {
                if let user {
                    MemberProfileSheet(user: user, onMessage: openDirectMessage)
                        .environment(session)
                        .environment(servers)
                        .appSheet(addsClose: true)
                }
            }
    }

    private var label: some View {
        HStack(spacing: 8) {
            AvatarView(user: user, size: 22)
                .overlay {
                    if isSpeaking {
                        Circle()
                            .strokeBorder(Theme.green, lineWidth: 2)
                            .padding(-2)
                    }
                }

            Text(user?.name ?? "Unknown")
                .font(.subheadline)
                .foregroundStyle(isHighlighted ? Theme.header : Theme.muted)
                .lineLimit(1)

            Spacer()

            if state.micMuted {
                Image(systemName: "mic.slash.fill")
            }

            if state.soundMuted {
                Image(systemName: "speaker.slash.fill")
            }
        }
        .font(.caption)
        .foregroundStyle(Theme.muted)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(.rect)
    }

    private func setPressed(_ pressed: Bool) {
        isPressed = pressed
    }

    private func setHovered(_ hovered: Bool) {
        isHovered = hovered
    }

    private func showProfile() {
        guard user != nil else {
            return
        }

        isProfilePresented = true
    }

    private func showMenu() {
        guard user != nil else {
            return
        }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        isPressed = false
        isMenuPresented = true
    }

    private func showMenuAtPointer(_ click: SecondaryClick) {
        guard user != nil else {
            return
        }

        menuAnchor = click.anchor
        isMenuPresented = true
    }

    // the profile opens once the menu has gone, a sheet cannot rise while another is closing
    private func requestProfile() {
        wantsProfile = true
        isMenuPresented = false
    }

    private func showWantedProfile() {
        if wantsProfile {
            wantsProfile = false
            isProfilePresented = true
        }
    }

    private func openDirectMessage() {
        isProfilePresented = false
        isMenuPresented = false

        guard let user else {
            return
        }

        Task {
            guard let channelId = try? await session.openDirectMessage(with: user.id) else {
                return
            }

            servers.open(channelId: channelId, in: session)
        }
    }
}
