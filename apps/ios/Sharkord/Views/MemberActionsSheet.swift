import SwiftUI

// discord's menu on a member, a right click on a mac and a long press elsewhere: their profile,
// a mention in the message box, a direct message, the note on their profile, and for someone
// who manages roles, which roles they hold
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
