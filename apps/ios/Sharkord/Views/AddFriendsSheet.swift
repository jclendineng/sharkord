import SwiftUI

// adding friends: requests waiting on you to accept, the ones you sent, and everyone on the
// server to ask, searchable by name
struct AddFriendsSheet: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""

    private func users(_ ids: [Int]) -> [PublicUser] {
        ids.compactMap { session.usersById[$0] }
    }

    // members who are neither you nor already linked to you, filtered by the search
    private var others: [PublicUser] {
        let linked = Set(session.friendLists.friends + session.friendLists.incoming + session.friendLists.outgoing)
        let search = query.trimmingCharacters(in: .whitespaces).lowercased()

        return session.members
            .filter { $0.id != session.ownUserId && !linked.contains($0.id) }
            .filter { search.isEmpty || $0.name.lowercased().contains(search) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                let incoming = users(session.friendLists.incoming)
                let outgoing = users(session.friendLists.outgoing)

                if !incoming.isEmpty {
                    Section("Requests") {
                        ForEach(incoming) { user in
                            FriendRow(user: user) {
                                IconButton(title: "Accept", systemImage: "checkmark", tint: Theme.green) {
                                    change("accept", user)
                                }

                                IconButton(title: "Ignore", systemImage: "xmark", tint: Theme.muted) {
                                    change("remove", user)
                                }
                            }
                        }
                    }
                }

                if !outgoing.isEmpty {
                    Section("Sent") {
                        ForEach(outgoing) { user in
                            FriendRow(user: user) {
                                IconButton(title: "Cancel Request", systemImage: "xmark", tint: Theme.muted) {
                                    change("remove", user)
                                }
                            }
                        }
                    }
                }

                Section("Add") {
                    ForEach(others) { user in
                        FriendRow(user: user) {
                            IconButton(title: "Add Friend", systemImage: "person.badge.plus", tint: Theme.blurple) {
                                change("request", user)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.deepBackground)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search members")
            .navigationTitle("Add Friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: close)
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.deepBackground)
    }

    private func change(_ action: String, _ user: PublicUser) {
        Task {
            await session.changeFriendship(action, with: user.id)
        }
    }

    private func close() {
        dismiss()
    }
}

private struct FriendRow<Actions: View>: View {
    let user: PublicUser
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(user: user, size: 36, showsStatus: true)

            Text(user.name)
                .foregroundStyle(Theme.header)
                .lineLimit(1)

            Spacer(minLength: 8)

            actions
        }
        .listRowBackground(Theme.listBackground)
    }
}

private struct IconButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(title, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .font(.body.weight(.semibold))
            .foregroundStyle(tint)
            .frame(width: 36, height: 36)
            .background(Theme.deepBackground, in: .circle)
            .buttonStyle(.plain)
    }
}
