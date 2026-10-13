import SwiftUI

// discord's own profile sheet: banner, avatar over its edge, edit button, then cards
struct ProfileScreen: View {
    @Environment(ServerListStore.self) private var servers
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var isEditPresented = false
    @State private var isSettingsPresented = false

    private var user: PublicUser? {
        session.ownUser
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
                        Text(user?.name ?? "")
                            .font(.title.bold())
                            .foregroundStyle(Theme.header)

                        Text(session.displayName)
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
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
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $isEditPresented) {
            EditProfileSheet()
        }
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

private struct ProfileBanner: View {
    let user: PublicUser?

    @Environment(SessionStore.self) private var session

    var body: some View {
        Color(hex: user?.profileColor ?? "#5865F2")
            .frame(height: 130)
            .overlay {
                if let banner = user?.banner, let address = session.address {
                    AsyncImage(url: address.fileURL(banner)) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
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
