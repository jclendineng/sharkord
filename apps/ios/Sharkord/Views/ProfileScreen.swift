import SwiftUI

// discord's own profile sheet: banner, avatar over its edge, edit button, then cards
struct ProfileScreen: View {
    @Environment(ServerListStore.self) private var servers
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var isEditPresented = false
    @State private var isSettingsPresented = false
    @State private var isStatusPresented = false
    @State private var isFriendsPresented = false

    private var user: PublicUser? {
        session.ownUser
    }

    private var roles: [Role] {
        user?.roleIds.compactMap { session.rolesById[$0] } ?? []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ProfileBanner(user: user)

                HStack(alignment: .bottom, spacing: 6) {
                    AvatarView(user: user, size: 92, showsStatus: true)
                        .padding(6)
                        .background(Theme.deepBackground, in: .circle)

                    // discord's thought bubble beside the avatar, the status message or a nudge
                    Button(action: setStatus) {
                        Label(
                            session.ownCustomStatus ?? "Set a status",
                            systemImage: session.ownCustomStatus == nil ? "plus.circle.fill" : "bubble.left.fill"
                        )
                        .font(.subheadline.italic())
                        .foregroundStyle(session.ownCustomStatus == nil ? Theme.muted : Theme.text)
                        .lineLimit(2)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Theme.listBackground, in: .capsule)
                        .overlay {
                            Capsule().stroke(Theme.divider, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 18)
                }
                .padding(.leading, 12)
                .padding(.trailing, 16)
                .offset(y: -50)
                .padding(.bottom, -50)

                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(user?.name ?? "")
                            .font(.title.bold())
                            .foregroundStyle(Theme.header)

                        Text(session.displayName)
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)

                        if !roles.isEmpty {
                            FlowLayout(spacing: 6) {
                                ForEach(roles) { role in
                                    RoleChip(role: role)
                                }
                            }
                            .padding(.top, 4)
                        }
                    }

                    Button(action: edit) {
                        Label("Edit Profile", systemImage: "pencil")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Theme.blurple, in: .rect(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)

                    if let bio = user?.bio, !bio.isEmpty {
                        ProfileCard(title: "About Me") {
                            Text(bio)
                                .foregroundStyle(Theme.text)
                        }
                    }

                    if let memberSince = user?.memberSince {
                        ProfileCard(title: "Member Since") {
                            Label(memberSince.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                                .foregroundStyle(Theme.text)
                        }
                    }

                    Button(action: showFriends) {
                        HStack {
                            Text("Friends")
                                .font(.headline)
                                .foregroundStyle(Theme.header)

                            Spacer()

                            Text("\(session.friendLists.friends.count)")
                                .foregroundStyle(Theme.muted)

                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Theme.muted)
                        }
                        .padding(16)
                        .background(Theme.listBackground, in: .rect(cornerRadius: 12))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)

                    ProfileCard(title: "Server") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.displayName)
                                .foregroundStyle(Theme.text)

                            if let host = session.address?.baseURL.host() {
                                Text(host)
                                    .font(.caption)
                                    .foregroundStyle(Theme.muted)
                            }
                        }
                    }

                    Button(role: .destructive, action: signOut) {
                        Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .foregroundStyle(Theme.red)
                    .background(Theme.listBackground, in: .rect(cornerRadius: 12))
                }
                .padding(16)
            }
        }
        .background(Theme.deepBackground)
        .overlay(alignment: .topLeading) {
            Button("Close", systemImage: "xmark", action: close)
                .labelStyle(.iconOnly)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(.black.opacity(0.35), in: .circle)
                .padding(14)
        }
        .overlay(alignment: .topTrailing) {
            Button("Settings", systemImage: "gearshape.fill", action: showSettings)
                .labelStyle(.iconOnly)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(.black.opacity(0.35), in: .circle)
                .padding(14)
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsSheet()
        }
        .sheet(isPresented: $isFriendsPresented) {
            AddFriendsSheet()
        }
        .sheet(isPresented: $isStatusPresented) {
            SetStatusSheet()
        }
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $isEditPresented) {
            EditProfileSheet()
        }
    }

    private func showFriends() {
        isFriendsPresented = true
    }

    private func setStatus() {
        isStatusPresented = true
    }

    private func showSettings() {
        isSettingsPresented = true
    }

    private func edit() {
        isEditPresented = true
    }

    private func close() {
        dismiss()
    }

    private func signOut() {
        dismiss()
        servers.remove(session)
    }
}

struct ProfileBanner: View {
    let user: PublicUser?

    @Environment(SessionStore.self) private var session

    var body: some View {
        Color(hex: user?.profileColor ?? "#5865F2")
            .frame(height: 130)
            .overlay {
                if let banner = user?.banner, let address = session.address {
                    CachedFileImage(file: banner, url: address.fileURL(banner)) {
                        Color.clear
                    }
                }
            }
            .clipped()
    }
}

struct ProfileCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.muted)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.listBackground, in: .rect(cornerRadius: 12))
    }
}

// the flair beside a name, a role in its own color
struct RoleChip: View {
    let role: Role

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color(hex: role.color))
                .frame(width: 9, height: 9)

            Text(role.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.text)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Theme.listBackground, in: .capsule)
    }
}
