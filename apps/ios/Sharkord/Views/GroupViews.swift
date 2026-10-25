import SwiftUI

// a group conversation's picture, there being no one person to show
struct GroupAvatar: View {
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: "person.2.fill")
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Theme.blurple, in: .circle)
    }
}

// discord's new group: tick up to nine friends and create it. the same list adds friends to a
// group that exists, counting the people already in it
struct GroupFriendPicker: View {
    enum Mode {
        case create
        case add(channelId: Int, memberIds: [Int])
    }

    let mode: Mode
    let onDone: (_ channelId: Int) -> Void

    @Environment(SessionStore.self) private var session

    @State private var query = ""
    @State private var picked: Set<Int> = []
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var existing: [Int] {
        if case .add(_, let memberIds) = mode {
            return memberIds
        }

        return []
    }

    // you and whoever is already in it count towards the ten
    private var count: Int {
        1 + existing.count + picked.count
    }

    private var friends: [PublicUser] {
        let search = query.trimmingCharacters(in: .whitespaces)

        return session.friendLists.friends
            .filter { !existing.contains($0) }
            .compactMap { session.usersById[$0] }
            .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var canSave: Bool {
        guard !isSaving else {
            return false
        }

        switch mode {
        case .create:
            return picked.count >= 2
        case .add:
            return !picked.isEmpty
        }
    }

    private var title: String {
        switch mode {
        case .create:
            "New Group"
        case .add:
            "Add Friends"
        }
    }

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(Theme.red)
                    .listRowBackground(Theme.listBackground)
            }

            if friends.isEmpty {
                Text(query.isEmpty ? "Add friends first, a group is made of your friends." : "No friends by that name.")
                    .foregroundStyle(Theme.muted)
                    .listRowBackground(Theme.listBackground)
            }

            ForEach(friends) { friend in
                Button {
                    toggle(friend)
                } label: {
                    HStack(spacing: 12) {
                        AvatarView(user: friend, size: 40, showsStatus: true)

                        Text(friend.name)
                            .foregroundStyle(Theme.header)
                            .lineLimit(1)

                        Spacer(minLength: 0)

                        Image(systemName: picked.contains(friend.id) ? "checkmark.square.fill" : "square")
                            .font(.title2)
                            .foregroundStyle(picked.contains(friend.id) ? Theme.blurple : Theme.muted)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(!picked.contains(friend.id) && count >= GroupLimits.maxMembers)
                .listRowBackground(Theme.listBackground)
            }
        }
        .scrollContentBackground(.hidden)
        .listHoverHighlight()
        .background(Theme.deepBackground)
        .searchable(text: $query, placement: .alwaysShown, prompt: "Search")
        .titleWithSubtitle(title, subtitle: "\(count) of \(GroupLimits.maxMembers) members")
        .inlineNavigationTitle()
        .toolbar {
            ActionToolbarItem(placement: .confirmationAction) {
                Button(saveTitle, action: save)
                    .disabled(!canSave)
            }
        }
    }

    private var saveTitle: String {
        switch mode {
        case .create:
            "Create"
        case .add:
            "Add"
        }
    }

    private func toggle(_ friend: PublicUser) {
        if picked.contains(friend.id) {
            picked.remove(friend.id)
        } else {
            picked.insert(friend.id)
        }
    }

    private func save() {
        struct CreateInput: Encodable {
            let userIds: [Int]
        }

        struct AddInput: Encodable {
            let channelId: Int
            let userIds: [Int]
        }

        let userIds = Array(picked)

        isSaving = true
        errorMessage = nil

        Task {
            do {
                switch mode {
                case .create:
                    let created: OpenedDirectMessage = try await session.perform("dms.createGroup", CreateInput(userIds: userIds))

                    await session.loadDirectMessages()
                    onDone(created.channelId)
                case .add(let channelId, _):
                    try await session.perform("dms.addGroupMembers", AddInput(channelId: channelId, userIds: userIds))
                    await session.loadDirectMessages()
                    onDone(channelId)
                }
            } catch {
                errorMessage = error.localizedDescription
            }

            isSaving = false
        }
    }
}
