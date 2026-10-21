import SwiftUI

// discord's member list down the right of a wide chat: who is online, then who is not, each
// opening their profile beside the row
struct MembersColumn: View {
    static let width: CGFloat = 240

    let channelId: Int
    // how much larger than its smallest it is drawn, growing with a wide mac window
    var scale: CGFloat = 1

    // a mac's starts a third larger than its smallest and grows with the chat past that, its rows
    // and text too, up to a limit, so a narrower window does not shrink it to nothing
    static let minimumScale: CGFloat = 1.35

    static func scale(forChatWidth width: CGFloat) -> CGFloat {
        let scale = min(max(width / 1100, minimumScale), 1.9)

        // in steps, so a window being resized does not redraw the list at every point
        return (scale * 20).rounded() / 20
    }

    @Environment(SessionStore.self) private var session

    // who can see a private channel, nil for a public one, which everyone can
    @State private var channelMemberIds: Set<Int>?

    private var isPrivateChannel: Bool {
        session.channel(channelId)?.private == true
    }

    // discord's: who is online under the role they show as, then everyone else online, then
    // whoever is offline in one group
    private var sections: [(title: String, users: [PublicUser])] {
        let visible = session.members.filter { channelMemberIds?.contains($0.id) ?? true }
        let sorted = visible.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let online = sorted.filter { $0.status != .offline }
        let offline = sorted.filter { $0.status == .offline }
        let byRole = Dictionary(grouping: online) { session.displayRole(for: $0) }

        let roleSections = byRole.keys
            .compactMap { $0 }
            .sorted(by: Role.ranksAbove)
            .map { role in (title: role.name, users: byRole[role] ?? []) }

        let plain = byRole[nil] ?? []

        return (roleSections + [("Online", plain), ("Offline", offline)]).filter { !$0.users.isEmpty }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(sections, id: \.title) { section in
                    Text("\(section.title.uppercased()) · \(section.users.count)")
                        .font(.system(size: 12 * scale, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 10)
                        .padding(.top, 16)
                        .padding(.bottom, 4)

                    ForEach(section.users) { user in
                        MemberColumnRow(user: user, channelId: channelId, scale: scale)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .task(id: channelId) {
            await loadChannelMembers()
        }
        .frame(width: Self.width * scale)
        .background(Theme.chatBackground)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Theme.panelEdge)
                .frame(width: 1)
        }
    }
}

extension MembersColumn {
    // the full list stays up if this fails, which is what the column showed before
    private func loadChannelMembers() async {
        guard isPrivateChannel else {
            channelMemberIds = nil
            return
        }

        let ids: [Int]? = try? await session.request("channels.getMembers", ["channelId": channelId])

        channelMemberIds = ids.map(Set.init)
    }
}

private struct MemberColumnRow: View {
    let user: PublicUser
    let channelId: Int
    let scale: CGFloat

    @Environment(SessionStore.self) private var session
    @Environment(ServerListStore.self) private var servers

    @State private var isProfilePresented = false
    @State private var isHovered = false
    @State private var isMenuPresented = false
    @State private var menuAnchor = UnitPoint.center

    private var isOffline: Bool {
        user.status == .offline
    }

    var body: some View {
        Button(action: showProfile) {
            HStack(spacing: 10 * scale) {
                AvatarView(user: user, size: 32 * scale, showsStatus: true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(user.name)
                        .font(.system(size: 15 * scale, weight: .medium))
                        .foregroundStyle(Color(hex: session.roleColor(for: user) ?? "#F2F3F5"))
                        .lineLimit(1)

                    if let customStatus = user.customStatus, !customStatus.isEmpty {
                        Text(customStatus)
                            .font(.system(size: 12 * scale))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }
            // discord dims who is away, but only enough to tell them apart: 0.45 left the name
            // under the contrast a dark theme needs to stay readable
            .opacity(isOffline && !isHovered ? 0.6 : 1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5 * scale)
            .background(isHovered || isMenuPresented ? Theme.hover : .clear, in: .rect(cornerRadius: 6))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover(perform: setHovered)
        // discord's right click on a member, beside the pointer
        .onSecondaryClick(perform: showMenu)
        .actionsPresentation(isPresented: $isMenuPresented, anchor: menuAnchor) {
            MemberActionsSheet(user: user, channelId: channelId, onShowProfile: showProfileFromMenu, onMessage: openDirectMessage)
                .environment(session)
                .environment(servers)
        }
        // handed the stores by hand: on a mac a presentation is worked out before it inherits
        // to the left, over the chat, as discord's is: the column sits at the window's right edge,
        // where a profile opening rightwards was squeezed into what little room was left. a fixed
        // size, so it can never be narrower than its content: a mac popover takes no ideal height
        // and opened short, the note cut off under a scroll bar
        .popover(isPresented: $isProfilePresented, arrowEdge: .trailing) {
            MemberProfileSheet(user: user, onMessage: openDirectMessage)
                .frame(width: 340 * scale, height: 600 * scale)
                .presentationCompactAdaptation(.popover)
                .environment(session)
                .environment(servers)
        }
    }

    private func setHovered(_ hovered: Bool) {
        isHovered = hovered
    }

    private func showProfile() {
        isProfilePresented = true
    }

    private func showMenu(_ click: SecondaryClick) {
        menuAnchor = click.anchor
        isMenuPresented = true
    }

    private func showProfileFromMenu() {
        isMenuPresented = false
        isProfilePresented = true
    }

    private func openDirectMessage() {
        isProfilePresented = false
        isMenuPresented = false

        Task {
            guard let channelId = try? await session.openDirectMessage(with: user.id) else {
                return
            }

            servers.open(channelId: channelId, in: session)
        }
    }
}
