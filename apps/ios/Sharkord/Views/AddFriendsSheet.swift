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
        #if os(macOS)
        // a pushed page's back button in the bar's neutral colour, not a blurple disc
        .tint(Theme.header)
        #endif
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
        SettingsForm {
            Section {
                NavigationLink {
                    AddByUsernameScreen()
                } label: {
                    Label("Add by Username", systemImage: "at")
                        .foregroundStyle(Theme.header)
                }
                .listRowBackground(Theme.groupedRowBackground)
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
        .sheetSearchable(text: $query, prompt: "Search people")
        .sheetBarBackground()
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

    // a form as the page before it is, so on a mac it fills the sheet and keeps a bar, where a
    // bare stack left the sheet's lower half see through and its done button gone
    var body: some View {
        SettingsForm {
            Section {
                TextField("", text: $name, prompt: Text("Enter a username"))
                    .labelsHidden()
                    .noAutocapitalization()
                    .autocorrectionDisabled()
                    .focused($isFocused)
                    .onSubmit(send)
            } header: {
                Text("Who would you like to add as a friend?")
            } footer: {
                if let message {
                    Text(message)
                        .foregroundStyle(isSent ? Theme.greenText : Theme.redText)
                        .wrappingFooter()
                }
            }
        }
        .settingsListStyle()
        .navigationTitle("Add by Username")
        .inlineNavigationTitle()
        .toolbar {
            ActionToolbarItem(placement: .confirmationAction) {
                Button("Send Request", action: send)
                    .disabled(!canSend)
            }
        }
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
        .listRowBackground(Theme.groupedRowBackground)
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
