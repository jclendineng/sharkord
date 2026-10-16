import SwiftUI

// discord's member list down the right of a wide chat: who is online, then who is not, each
// opening their profile beside the row
struct MembersColumn: View {
    static let width: CGFloat = 240

    let channelId: Int

    @Environment(SessionStore.self) private var session

    // who can see a private channel, nil for a public one, which everyone can
    @State private var channelMemberIds: Set<Int>?

    private var isPrivateChannel: Bool {
        session.channel(channelId)?.private == true
    }

    private var sections: [(title: String, users: [PublicUser])] {
        let visible = session.members.filter { channelMemberIds?.contains($0.id) ?? true }
        let sorted = visible.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let online = sorted.filter { $0.status != .offline }
        let offline = sorted.filter { $0.status == .offline }

        return [("Online", online), ("Offline", offline)].filter { !$0.users.isEmpty }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(sections, id: \.title) { section in
                    Text("\(section.title.uppercased()) · \(section.users.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 10)
                        .padding(.top, 16)
                        .padding(.bottom, 4)

                    ForEach(section.users) { user in
                        MemberColumnRow(user: user, channelId: channelId)
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
        .frame(width: Self.width)
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
            HStack(spacing: 10) {
                AvatarView(user: user, size: 32, showsStatus: true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(user.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color(hex: session.roleColor(for: user) ?? "#F2F3F5"))
                        .lineLimit(1)

                    if let customStatus = user.customStatus, !customStatus.isEmpty {
                        Text(customStatus)
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }
            // discord dims who is away, the row stays readable
            .opacity(isOffline && !isHovered ? 0.45 : 1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isHovered || isMenuPresented ? Theme.hover : .clear, in: .rect(cornerRadius: 6))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover(perform: setHovered)
        // discord's right click on a member, beside the pointer
        .onSecondaryClick(perform: showMenu)
        .actionsPresentation(isPresented: $isMenuPresented, anchor: menuAnchor) {
            MemberActionsMenu(user: user, channelId: channelId, onShowProfile: showProfileFromMenu, onMessage: openDirectMessage)
                .environment(session)
                .environment(servers)
        }
        // handed the stores by hand: on a mac a presentation is worked out before it inherits
        .popover(isPresented: $isProfilePresented, arrowEdge: .leading) {
            MemberProfileSheet(user: user, onMessage: openDirectMessage)
                .frame(idealWidth: 340, idealHeight: 560)
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

// discord's menu on a member: their profile, a mention in the message box, a direct message, the
// note on their profile, and for someone who manages roles, which roles they hold
private struct MemberActionsMenu: View {
    let user: PublicUser
    let channelId: Int
    let onShowProfile: () -> Void
    let onMessage: () -> Void

    @Environment(SessionStore.self) private var session
    @Environment(\.closePointerMenu) private var closePointerMenu

    private var isSelf: Bool {
        user.id == session.ownUserId
    }

    // the owner role is given at setup, never from a menu
    private var assignableRoles: [Role] {
        session.rolesById.values
            .filter { $0.id != 1 }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            ActionGroup(isFirst: true) {
                ActionRow(title: "Profile", systemImage: "person.crop.circle", action: onShowProfile)
                ActionRow(title: "Mention", systemImage: "at", action: mention)

                if !isSelf {
                    ActionRow(title: "Message", systemImage: "bubble.left", action: onMessage)
                    ActionRow(title: "Add Note", systemImage: "note.text", action: onShowProfile)
                }
            }

            if session.can(.manageRoles) && !assignableRoles.isEmpty {
                ActionGroup {
                    SubmenuRow(title: "Roles") {
                        ForEach(assignableRoles) { role in
                            ActionRow(
                                title: role.name,
                                systemImage: user.roleIds.contains(role.id) ? "checkmark" : ""
                            ) {
                                toggle(role)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 6)
    }

    private func mention() {
        session.messages(for: channelId).pendingInsert = "@\(user.name) "
        closePointerMenu?()
    }

    private func toggle(_ role: Role) {
        struct RoleInput: Encodable {
            let userId: Int
            let roleId: Int
        }

        let hasRole = user.roleIds.contains(role.id)

        closePointerMenu?()

        Task {
            do {
                try await session.perform(hasRole ? "users.removeRole" : "users.addRole", RoleInput(userId: user.id, roleId: role.id))
            } catch {
                session.showError(error)
            }
        }
    }
}
