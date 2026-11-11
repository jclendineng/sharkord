import SwiftUI

// discord's menu on a member, a right click on a mac and a long press elsewhere: their profile,
// a mention in the message box, a direct message, the note on their profile, and for someone
// who manages roles, which roles they hold, and a kick or ban for a moderator
struct MemberActionsSheet: View {
    let user: PublicUser
    // the chat a mention goes into, none where there is no chat behind the list
    let channelId: Int?
    let onShowProfile: () -> Void
    let onMessage: () -> Void
    // the voice channel they are in, when the menu opens on them there, which offers moving them
    var voiceChannelId: Int?

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.closePointerMenu) private var closePointerMenu
    @Environment(\.isPointerMenu) private var isPointerMenu

    private var isSelf: Bool {
        user.id == session.ownUserId
    }

    // the owner role is given at setup, never from a menu
    private var assignableRoles: [Role] {
        session.rolesById.values
            .filter { $0.id != 1 }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // the web's drag of a member to another voice channel
    private var moveTargets: [Channel] {
        guard let voiceChannelId, session.can(.moveMembers) else {
            return []
        }

        return session.channelSections
            .flatMap(\.channels)
            .filter { $0.type == .voice && $0.id != voiceChannelId }
    }

    // the server refuses a kick of someone with no open session, so it is offered only to
    // someone online. who outranks whom is left to the server, which says so in a toast
    private var canKick: Bool {
        guard !isSelf, user.banned != true, session.can(.kickMembers) else {
            return false
        }

        return user.status.map { $0 != .offline } ?? false
    }

    // an unban is on the members screen, beside the ban's reason
    private var canBan: Bool {
        !isSelf && user.banned != true && session.can(.banMembers)
    }

    private var canManageRoles: Bool {
        session.can(.assignRoles) && !assignableRoles.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: isPointerMenu ? 0 : 16) {
                // discord's menu opens straight on its rows
                if !isPointerMenu {
                    HStack(spacing: 12) {
                        AvatarView(user: user, size: 44)

                        Text(user.name)
                            .font(.title3.bold())
                            .foregroundStyle(Theme.header)
                            .lineLimit(1)
                    }
                    .padding(.top, 20)
                }

                ActionGroup(isFirst: isPointerMenu) {
                    ActionRow(title: "Profile", systemImage: "person.crop.circle", action: showProfile)

                    if channelId != nil {
                        ActionRow(title: "Mention", systemImage: "at", action: mention)
                    }

                    if !isSelf {
                        ActionRow(title: "Message", systemImage: "bubble.left", action: message)
                        ActionRow(title: "Add Note", systemImage: "note.text", action: showProfile)
                    }
                }

                if !moveTargets.isEmpty {
                    ActionGroup {
                        if isPointerMenu {
                            SubmenuRow(title: "Move To", systemImage: "arrow.right.circle") {
                                moveRows
                            }
                        } else {
                            moveRows
                        }
                    }
                }

                if canManageRoles {
                    ActionGroup {
                        // a submenu beside the pointer on a mac, a sheet lists them in place
                        if isPointerMenu {
                            SubmenuRow(title: "Roles", systemImage: "shield") {
                                roleRows
                            }
                        } else {
                            roleRows
                        }
                    }
                }

                if canKick || canBan {
                    ActionGroup {
                        if canKick {
                            ActionRow(title: "Kick", systemImage: "person.fill.xmark", tint: Theme.red, action: kick)
                        }

                        if canBan {
                            ActionRow(title: "Ban", systemImage: "hammer.fill", tint: Theme.red, action: ban)
                        }
                    }
                }

                if !isSelf, session.supports(.blocking) {
                    ActionGroup {
                        if session.isBlocked(user.id) {
                            ActionRow(title: "Unblock", systemImage: "nosign", action: unblock)
                        } else {
                            ActionRow(title: "Block", systemImage: "nosign", tint: Theme.red, action: block)
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
    }

    private var moveRows: some View {
        ForEach(moveTargets) { channel in
            ActionRow(title: isPointerMenu ? channel.name : "Move to \(channel.name)", systemImage: "speaker.wave.2.fill") {
                move(to: channel.id)
            }
        }
    }

    private func move(to channelId: Int) {
        close()

        Task {
            await session.moveToVoice(userId: user.id, channelId: channelId)
        }
    }

    private var roleRows: some View {
        ForEach(assignableRoles) { role in
            ActionRow(
                title: role.name,
                systemImage: user.roleIds.contains(role.id) ? "checkmark" : (isPointerMenu ? "" : "circle")
            ) {
                toggle(role)
            }
        }
    }

    // a sheet on a touch screen, the pointer menu on a mac, where dismiss has nothing to close
    private func close() {
        if let closePointerMenu {
            closePointerMenu()
        } else {
            dismiss()
        }
    }

    private func showProfile() {
        close()
        onShowProfile()
    }

    private func message() {
        close()
        onMessage()
    }

    // asked about once the menu has gone, over the whole window
    private func block() {
        close()
        session.userAwaitingBlock = user
    }

    private func kick() {
        close()
        session.moderationAwaiting = PendingModeration(user: user, action: .kick)
    }

    private func ban() {
        close()
        session.moderationAwaiting = PendingModeration(user: user, action: .ban)
    }

    private func unblock() {
        close()

        Task {
            await session.changeFriendship("unblock", with: user.id)
        }
    }

    private func mention() {
        if let channelId {
            session.messages(for: channelId).pendingMention = .user(user)
        }

        close()
    }

    private func toggle(_ role: Role) {
        struct RoleInput: Encodable {
            let userId: Int
            let roleId: Int
        }

        let hasRole = user.roleIds.contains(role.id)

        close()

        Task {
            do {
                try await session.perform(hasRole ? "users.removeRole" : "users.addRole", RoleInput(userId: user.id, roleId: role.id))
            } catch {
                session.showError(error)
            }
        }
    }
}
