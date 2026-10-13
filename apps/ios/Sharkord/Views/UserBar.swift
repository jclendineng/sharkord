import SwiftUI

struct UserBar: View {
    @Environment(ServerListStore.self) private var servers
    @Environment(SessionStore.self) private var session

    @State private var isProfilePresented = false
    @State private var isUnreadsPresented = false

    // the message when there is one, like discord, otherwise what was picked
    private var statusText: String {
        if let customStatus = session.ownCustomStatus, !customStatus.isEmpty {
            return customStatus
        }

        return session.ownPresence.title
    }

    private var hasUnread: Bool {
        servers.sessions.contains { !$0.unreadChannels.isEmpty }
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: showProfile) {
                HStack(spacing: 12) {
                    AvatarView(user: session.ownUser, size: 44, showsStatus: true)

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(session.ownUser?.name ?? session.displayName)
                                .font(.headline)
                                .foregroundStyle(Theme.header)
                                .lineLimit(1)

                            Image(systemName: "chevron.down")
                                .font(.caption.bold())
                                .foregroundStyle(Theme.muted)
                        }

                        Text(statusText)
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            Button("Unreads", systemImage: "bell.fill", action: showUnreads)
                .labelStyle(.iconOnly)
                .font(.title3)
                .foregroundStyle(Theme.muted)
                .frame(width: 44, height: 44)
                .overlay(alignment: .topTrailing) {
                    if hasUnread {
                        Circle()
                            .fill(Theme.red)
                            .frame(width: 10, height: 10)
                            .offset(x: -8, y: 8)
                    }
                }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.listBackground, in: .rect(cornerRadius: 28))
        .overlay {
            RoundedRectangle(cornerRadius: 28).stroke(Theme.divider, lineWidth: 1)
        }
        .sheet(isPresented: $isProfilePresented) {
            ProfileScreen()
        }
        .sheet(isPresented: $isUnreadsPresented) {
            InboxSheet()
        }
    }

    private func showProfile() {
        isProfilePresented = true
    }

    private func showUnreads() {
        isUnreadsPresented = true
    }
}
