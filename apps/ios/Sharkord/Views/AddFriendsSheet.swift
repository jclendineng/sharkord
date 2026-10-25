import SwiftUI

// discord's add friends, for one server: there is no central directory to share yourself into,
// everyone you could add is already here. add by username, then requests waiting on you, the
// ones you sent, and everyone else on the server to ask
struct AddFriendsSheet: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            AddFriendsScreen()
                .toolbar {
                    ActionToolbarItem(placement: .confirmationAction) {
                        Button("Done", action: close)
                    }
                }
        }
        .sheetDetents([.large])
        .presentationBackground(Theme.deepBackground)
    }

    private func close() {
        dismiss()
    }
}

// the screen itself, so the new message sheet can push it too
struct AddFriendsScreen: View {
    @Environment(SessionStore.self) private var session

    @State private var query = ""

    private func users(_ ids: [Int]) -> [PublicUser] {
        ids.compactMap { session.usersById[$0] }
    }

    // members who are neither you nor already linked to you, filtered by the search
    private var others: [PublicUser] {
        let lists = session.friendLists
        let linked = Set(lists.friends + lists.incoming + lists.outgoing)
        let search = query.trimmingCharacters(in: .whitespaces).lowercased()

        return session.members
            .filter { $0.id != session.ownUserId && !linked.contains($0.id) }
            .filter { search.isEmpty || $0.name.lowercased().contains(search) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List {
            Section {
                NavigationLink {
                    AddByUsernameScreen()
                } label: {
                    Label("Add by Username", systemImage: "at")
                        .foregroundStyle(Theme.header)
                }
                .listRowBackground(Theme.listBackground)
            }

            let incoming = users(session.friendLists.incoming)
            let outgoing = users(session.friendLists.outgoing)

            if !incoming.isEmpty {
                Section("Requests") {
                    ForEach(incoming) { user in
                        FriendRow(user: user) {
                            RoundIconButton(title: "Accept", systemImage: "checkmark", tint: Theme.green) {
                                change("accept", user)
                            }

                            RoundIconButton(title: "Ignore", systemImage: "xmark", tint: Theme.muted) {
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
                            RoundIconButton(title: "Cancel Request", systemImage: "xmark", tint: Theme.muted) {
                                change("remove", user)
                            }
                        }
                    }
                }
            }

            let friends = users(session.friendLists.friends)
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

            if !friends.isEmpty {
                Section("Friends") {
                    ForEach(friends) { user in
                        FriendRow(user: user) {
                            RoundIconButton(title: "Remove Friend", systemImage: "person.badge.minus", tint: Theme.muted) {
                                change("remove", user)
                            }
                        }
                    }
                }
            }

            Section("People on \(session.displayName)") {
                ForEach(others) { user in
                    FriendRow(user: user) {
                        RoundIconButton(title: "Add Friend", systemImage: "person.badge.plus", tint: Theme.blurple) {
                            change("request", user)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .listHoverHighlight()
        .background(Theme.deepBackground)
        .searchable(text: $query, placement: .alwaysShown, prompt: "Search people")
        .navigationTitle("Add Friends")
        .inlineNavigationTitle()
    }

    private func change(_ action: String, _ user: PublicUser) {
        Task {
            await session.changeFriendship(action, with: user.id)
        }
    }
}

// discord's add by username: one field, a request to whoever on the server goes by that name
private struct AddByUsernameScreen: View {
    @Environment(SessionStore.self) private var session

    @State private var name = ""
    @State private var message: String?
    @State private var isSent = false

    @FocusState private var isFocused: Bool

    private var canSend: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Who would you like to add as a friend?")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.muted)

            TextField("Enter a username", text: $name)
                .noAutocapitalization()
                .autocorrectionDisabled()
                .focused($isFocused)
                .onSubmit(send)
                .foregroundStyle(Theme.header)
                .padding(.horizontal, 14)
                .frame(height: 52)
                .background(Theme.inputBackground, in: .rect(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isFocused ? Theme.blurple : Theme.divider, lineWidth: 1)
                }

            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(isSent ? Theme.green : Theme.red)
            }

            Button(action: send) {
                Text("Send Friend Request")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white.opacity(canSend ? 1 : 0.5))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Theme.blurple.opacity(canSend ? 1 : 0.5), in: .rect(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .padding(.top, 14)

            Spacer(minLength: 0)
        }
        .padding(18)
        .background(Theme.deepBackground)
        .navigationTitle("Add by Username")
        .inlineNavigationTitle()
        .onAppear(perform: focus)
    }

    private func focus() {
        isFocused = true
    }

    private func send() {
        let wanted = name.trimmingCharacters(in: .whitespaces)

        guard let user = session.members.first(where: { $0.name.caseInsensitiveCompare(wanted) == .orderedSame }) else {
            isSent = false
            message = "Nobody on \(session.displayName) goes by \(wanted)."
            return
        }

        Task {
            await session.changeFriendship("request", with: user.id)
            isSent = true
            message = "Friend request sent to \(user.name)."
            name = ""
        }
    }
}

struct FriendRow<Actions: View>: View {
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

struct RoundIconButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(Theme.deepBackground, in: .circle)
                .contentShape(.circle)
        }
            .buttonStyle(.plain)
    }
}
