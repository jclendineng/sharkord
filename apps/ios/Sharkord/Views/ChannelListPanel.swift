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
            if session.showsReconnectingBanner {
                ReconnectingBanner()
            }
        }
        .sheet(isPresented: $isInvitePresented) {
            InviteSheet()
        }
        .sheet(isPresented: $isServerSheetPresented, onDismiss: showQueuedInvite) {
            ServerSheet(onInvite: queueInvite)
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
                NavigationLink(value: SearchRoute()) {
                    Label("Search", systemImage: "magnifyingglass")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(Theme.deepBackground, in: .rect(cornerRadius: 12))
                }

                Button("Invite", systemImage: "person.badge.plus", action: showInvite)
                    .labelStyle(.iconOnly)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .frame(width: 44, height: 40)
                    .background(Theme.deepBackground, in: .rect(cornerRadius: 12))
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

    @State private var isVoiceSheetPresented = false
    @State private var isActionsSheetPresented = false

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
            channel.private ? "lock" : "number"
        case .voice:
            "speaker.wave.2.fill"
        }
    }

    var body: some View {
        row
            .simultaneousGesture(LongPressGesture().onEnded(showActions))
            .sheet(isPresented: $isActionsSheetPresented) {
                ChannelActionsSheet(channel: channel)
            }
    }

    @ViewBuilder
    private var row: some View {
        switch channel.type {
        case .text:
            NavigationLink(value: ChatRoute(channelId: channel.id)) {
                label
            }
            .buttonStyle(ChannelRowButtonStyle())
        case .voice:
            Button(action: showVoiceSheet) {
                label
            }
            .buttonStyle(ChannelRowButtonStyle())
            .sheet(isPresented: $isVoiceSheetPresented) {
                VoiceChannelSheet(channel: channel)
            }
        }
    }

    // like discord, a voice channel shows who is in it before anyone joins
    private func showVoiceSheet() {
        isVoiceSheetPresented = true
    }

    private func showActions(_: Bool) {
        isActionsSheetPresented = true
    }

    private var label: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .frame(width: 24)

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
        .background(isSelected ? Theme.hover : .clear, in: .rect(cornerRadius: 8))
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
        }
    }
}

private struct ChannelRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Theme.hover : .clear, in: .rect(cornerRadius: 6))
    }
}
