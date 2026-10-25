import SwiftUI

// one invite from the server's list: its link, settings and who joined with it. a deleted invite
// keeps the people who joined, for the record
struct InviteDetailScreen: View {
    let invite: AdminInvite
    let onDeleted: () -> Void

    @Environment(SessionStore.self) private var session
    @Environment(ServerListStore.self) private var servers
    @Environment(\.dismiss) private var dismiss

    @State private var isCopied = false
    @State private var isDeleteConfirmPresented = false
    @State private var errorMessage: String?
    @State private var profileUser: PublicUser?

    private var joins: [AdminInvite.Join] {
        invite.joins ?? []
    }

    // uses the server counted with nobody to show: sign ups from before it kept who joined, or
    // accounts deleted since
    private var unlistedUses: Int {
        max(invite.uses - joins.count, 0)
    }

    var body: some View {
        SettingsForm {
            Section {
                Text(invite.code)
                    .font(.body.monospaced())
                    .foregroundStyle(invite.isDeleted ? Theme.muted : Theme.header)
                    .textSelection(.enabled)

                if !invite.isDeleted {
                    Button(action: copy) {
                        Label(isCopied ? "Copied" : "Copy Link", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                    }
                }
            } footer: {
                if invite.isDeleted {
                    Text("This invite was deleted and no longer works. It is kept so you can see who joined with it.")
                        .wrappingFooter()
                }
            }

            Section("Details") {
                LabeledContent("Uses", value: invite.usesText)
                LabeledContent(invite.isDeleted ? "Status" : "Expires", value: invite.expiryText)

                if let creator = invite.creator {
                    LabeledContent("Created By", value: creator.name)
                }

                LabeledContent("Created", value: AdminInvite.date(invite.createdAt).formatted(date: .abbreviated, time: .shortened))

                if let role = invite.role {
                    LabeledContent("Gives Role", value: role.name)
                }
            }

            Section {
                if joins.isEmpty && unlistedUses == 0 {
                    Text("Nobody has joined with this invite yet.")
                        .foregroundStyle(Theme.muted)
                }

                ForEach(joins, id: \.userId) { join in
                    JoinRow(join: join, user: session.usersById[join.userId], onSelect: showProfile)
                }
            } header: {
                Text("Joined With This Invite")
            } footer: {
                if unlistedUses > 0 {
                    Text("\(unlistedUses) \(unlistedUses == 1 ? "use isn't" : "uses aren't") listed: from before Sharkord kept who joined, or an account deleted since.")
                        .wrappingFooter()
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(Theme.red)
                }
            }

            if !invite.isDeleted {
                SettingsActions {
                    Button("Delete Invite", role: .destructive, action: confirmDelete)
                }
            }
        }
        .settingsListStyle()
        .navigationTitle("Invite")
        .inlineNavigationTitle()
        .alert("Delete this invite?", isPresented: $isDeleteConfirmPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive, action: delete)
        } message: {
            Text(AdminInvite.deleteMessage)
        }
        // handed over by hand: on a mac a sheet's background is worked out before it inherits
        // anything, so a sheet reading a store it was not given crashed on opening
        .sheet(item: $profileUser) { user in
            MemberProfileSheet(user: user, onMessage: { openDirectMessage(with: user) })
                .environment(session)
                .environment(servers)
                .appSheet()
        }
    }

    private func copy() {
        guard let address = session.address else {
            return
        }

        // the web client's invite link, see table-invite.tsx
        Platform.copy("\(address.baseURL.absoluteString)/?invite=\(invite.code)")
        isCopied = true
    }

    private func confirmDelete() {
        isDeleteConfirmPresented = true
    }

    private func delete() {
        Task {
            do {
                try await session.perform("invites.delete", ["inviteId": invite.id])
                onDeleted()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func showProfile(_ user: PublicUser) {
        profileUser = user
    }

    private func openDirectMessage(with user: PublicUser) {
        guard user.id != session.ownUserId else {
            return
        }

        Task {
            do {
                let channelId = try await session.openDirectMessage(with: user.id)

                servers.open(channelId: channelId, in: session)
            } catch {
                session.showError(error)
            }
        }
    }
}

private struct JoinRow: View {
    let join: AdminInvite.Join
    // nil for someone the session doesn't know, such as an account that left
    let user: PublicUser?
    let onSelect: (PublicUser) -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 12) {
                AvatarView(user: user, size: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(user?.name ?? "Unknown user")
                        .foregroundStyle(Theme.header)

                    Text("Joined \(AdminInvite.date(join.createdAt).formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .disabled(user == nil)
    }

    private func select() {
        if let user {
            onSelect(user)
        }
    }
}
