import SwiftUI

struct ChannelListPanel: View {
    @Environment(ServerListStore.self) private var servers
    @Environment(SessionStore.self) private var session

    @State private var collapsedCategoryIds: Set<Int> = []
    @State private var isInvitePresented = false
    @State private var isServerSheetPresented = false
    @State private var isInviteQueued = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                header

                ForEach(session.channelSections) { section in
                    if let title = section.title {
                        CategoryHeader(
                            title: title,
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
        .sheet(isPresented: $isServerSheetPresented, onDismiss: showQueuedInvite) {
            ServerSheet(onInvite: queueInvite)
                .environment(session)
                .environment(servers)
                .appSheet(addsClose: true)
        }
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
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, -8)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

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

    // a sheet cannot open while another one is still closing
    private func queueInvite() {
        isInviteQueued = true
    }

    private func showQueuedInvite() {
        if isInviteQueued {
            isInviteQueued = false
            isInvitePresented = true
        }
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
    let isCollapsed: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .rotationEffect(.degrees(isCollapsed ? -90 : 0))

                Text(title.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(0.3)

                Spacer()
            }
            .foregroundStyle(Theme.muted)
            .padding(.top, 18)
            .padding(.bottom, 4)
            .padding(.horizontal, 4)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
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
            .onHover(perform: setHovered)
            .onTapGesture(perform: open)
            .onLongPressGesture(minimumDuration: 0.3, perform: showActions, onPressingChanged: setPressed)
            .onSecondaryClick(perform: showActionsAtPointer)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "More Options", showActions)
            .actionsPresentation(isPresented: $isActionsSheetPresented, anchor: menuAnchor, onDismiss: showMuteIfWanted) {
                ChannelActionsSheet(channel: channel, onMute: requestMute)
                    .environment(session)
                    .environment(servers)
            }
            .sheet(isPresented: $isMutePresented) {
                MuteDurationSheet(title: "Mute Channel", subtitle: "#\(channel.name)", channelId: channel.id)
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

    // pressed, under the pointer, or showing its menu, as discord lights a channel up
    private var isHighlighted: Bool {
        isPressed || (!isSelected && (isHovered || isActionsSheetPresented))
    }

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

    private func showMuteIfWanted() {
        if wantsMute {
            wantsMute = false
            isMutePresented = true
        }
    }

    // like discord, a voice channel shows who is in it before anyone joins
    private func showVoiceSheet() {
        isVoiceSheetPresented = true
    }

    private func showActions() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
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
        ForEach(session.voiceParticipants(in: channelId), id: \.user?.id) { participant in
            HStack(spacing: 8) {
                AvatarView(user: participant.user, size: 22)

                Text(participant.user?.name ?? "Unknown")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)

                Spacer()

                if participant.state.micMuted {
                    Image(systemName: "mic.slash.fill")
                }

                if participant.state.soundMuted {
                    Image(systemName: "speaker.slash.fill")
                }
            }
            .font(.caption)
            .foregroundStyle(Theme.muted)
            .padding(.leading, 40)
            .padding(.trailing, 8)
            .padding(.vertical, 3)
            .contentShape(.rect)
            .contextMenu {
                if let user = participant.user, session.can(.moveMembers) {
                    MoveToVoiceMenu(user: user, fromChannelId: channelId)
                }
            }
        }
    }
}

// the web's drag of a member to another voice channel, for anyone who can move members
struct MoveToVoiceMenu: View {
    let user: PublicUser
    let fromChannelId: Int

    @Environment(SessionStore.self) private var session

    private var targets: [Channel] {
        session.channelSections
            .flatMap(\.channels)
            .filter { $0.type == .voice && $0.id != fromChannelId }
    }

    var body: some View {
        Menu("Move To", systemImage: "arrow.right.arrow.left") {
            ForEach(targets) { channel in
                Button(channel.name, systemImage: "speaker.wave.2.fill") {
                    move(to: channel.id)
                }
            }
        }
    }

    private func move(to channelId: Int) {
        Task {
            await session.moveToVoice(userId: user.id, channelId: channelId)
        }
    }
}
