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
                        Button(action: message) {
                            Label("Message", systemImage: "bubble.left.fill")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Theme.blurple, in: .rect(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
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
                }
                .padding(16)
            }
        }
        .background(Theme.deepBackground)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.deepBackground)
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
