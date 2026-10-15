import SwiftUI

// discord's profile sheet for someone else, opened from the member list: banner, avatar over
// its edge, name and roles, a button to message them, then what they wrote about themselves
struct MemberProfileSheet: View {
    let user: PublicUser
    let onMessage: () -> Void

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    private var isOwn: Bool {
        user.id == session.ownUserId
    }

    private var roles: [Role] {
        user.roleIds.compactMap { session.rolesById[$0] }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ProfileBanner(user: user)

                AvatarView(user: user, size: 92, showsStatus: true)
                    .padding(6)
                    .background(Theme.deepBackground, in: .circle)
                    .padding(.leading, 12)
                    .offset(y: -50)
                    .padding(.bottom, -50)

                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(user.name)
                            .font(.title.bold())
                            .foregroundStyle(Theme.header)

                        if let customStatus = user.customStatus, !customStatus.isEmpty {
                            Text(customStatus)
                                .font(.subheadline)
                                .foregroundStyle(Theme.text)
                        }

                        if !roles.isEmpty {
                            FlowLayout(spacing: 6) {
                                ForEach(roles) { role in
                                    RoleChip(role: role)
                                }
                            }
                            .padding(.top, 4)
                        }
                    }

                    if !isOwn {
                        HStack(spacing: 10) {
                            friendButton

                            Button(action: message) {
                                Image(systemName: "bubble.left.fill")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Theme.header)
                                    .frame(width: 48, height: 46)
                                    .background(Theme.listBackground, in: .rect(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Message")
                        }
                    }

                    if let bio = user.bio, !bio.isEmpty {
                        ProfileCard(title: "About Me") {
                            Text(bio)
                                .foregroundStyle(Theme.text)
                        }
                    }

                    if let memberSince = user.memberSince {
                        ProfileCard(title: "Member Since") {
                            Label(memberSince.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                                .foregroundStyle(Theme.text)
                        }
                    }

                    if !isOwn {
                        NoteCard(userId: user.id)
                    }
                }
                .padding(16)
            }
        }
        .background(Theme.deepBackground)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.deepBackground)
    }

    // discord's button for where you stand: add them, accept their request, a request waiting on
    // them, or friends, each a tap from the next step
    @ViewBuilder
    private var friendButton: some View {
        switch session.friendStatus(with: user.id) {
        case .none:
            wideButton("Add Friend", systemImage: "person.badge.plus", filled: true) {
                change("request")
            }
        case .incoming:
            wideButton("Accept Request", systemImage: "checkmark", filled: true) {
                change("accept")
            }
        case .outgoing:
            Menu {
                Button("Cancel Request", systemImage: "xmark", role: .destructive) {
                    change("remove")
                }
            } label: {
                wideLabel("Pending", systemImage: "clock", filled: false)
            }
        case .friends:
            Menu {
                Button("Remove Friend", systemImage: "person.badge.minus", role: .destructive) {
                    change("remove")
                }
            } label: {
                wideLabel("Friends", systemImage: "person.fill.checkmark", filled: false)
            }
        }
    }

    private func wideButton(_ title: String, systemImage: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            wideLabel(title, systemImage: systemImage, filled: filled)
        }
        .buttonStyle(.plain)
    }

    private func wideLabel(_ title: String, systemImage: String, filled: Bool) -> some View {
        Label(title, systemImage: systemImage)
            .font(.body.weight(.semibold))
            .foregroundStyle(filled ? .white : Theme.header)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(filled ? Theme.blurple : Theme.listBackground, in: .rect(cornerRadius: 10))
    }

    private func change(_ action: String) {
        Task {
            await session.changeFriendship(action, with: user.id)
        }
    }

    // the sheet goes first, then the direct message opens in its place: a navigation started
    // while the sheet is still closing is dropped
    private func message() {
        dismiss()

        Task {
            try? await Task.sleep(for: .milliseconds(350))
            onMessage()
        }
    }
}

// discord's note on a profile, only ever seen by whoever wrote it. saved when the field is left
// or the sheet goes away, and missing on a server from before notes
private struct NoteCard: View {
    let userId: Int

    @Environment(SessionStore.self) private var session

    @State private var note = ""
    @State private var saved: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        if saved != nil {
            ProfileCard(title: "Note (only visible to you)") {
                TextField("Tap to add a note", text: $note, axis: .vertical)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1...6)
                    .focused($isFocused)
                    .onChange(of: isFocused) { _, focused in
                        if !focused {
                            save()
                        }
                    }
                    .onDisappear(perform: save)
            }
        } else {
            Color.clear
                .frame(height: 0)
                .task {
                    await load()
                }
        }
    }

    private func load() async {
        guard let loaded: String = try? await session.request("users.getNote", ["userId": userId]) else {
            return
        }

        note = loaded
        saved = loaded
    }

    private func save() {
        struct NoteInput: Encodable {
            let userId: Int
            let note: String
        }

        let text = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(256))

        guard text != saved else {
            return
        }

        saved = text

        Task {
            do {
                try await session.perform("users.setNote", NoteInput(userId: userId, note: text))
            } catch {
                session.showError(error)
            }
        }
    }
}
