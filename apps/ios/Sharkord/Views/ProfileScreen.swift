import SwiftUI

struct ProfileScreen: View {
    @Environment(ServerListStore.self) private var servers
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    private var user: PublicUser? {
        session.ownUser
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Color(hex: user?.profileColor ?? "#5865F2")
                        .frame(height: 120)

                    AvatarView(user: user, size: 88, showsStatus: true)
                        .padding(6)
                        .background(Theme.deepBackground, in: .circle)
                        .padding(.leading, 16)
                        .offset(y: -50)
                        .padding(.bottom, -50)

                    VStack(alignment: .leading, spacing: 16) {
                        Text(user?.name ?? "")
                            .font(.title.bold())
                            .foregroundStyle(Theme.header)

                        if let bio = user?.bio, !bio.isEmpty {
                            card("About Me") {
                                Text(bio)
                                    .foregroundStyle(Theme.text)
                            }
                        }

                        card("Server") {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.serverName)
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
            .ignoresSafeArea(edges: .top)
        }
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.muted)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.listBackground, in: .rect(cornerRadius: 12))
    }

    private func signOut() {
        dismiss()
        servers.remove(session)
    }
}
