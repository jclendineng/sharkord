import SwiftUI

struct UserBar: View {
    // the ipad's, sized to sit under the channel list like discord's rather than fill a phone
    var isCompact = false

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

    private var cornerRadius: CGFloat {
        isCompact ? 22 : 28
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: showProfile) {
                HStack(spacing: isCompact ? 10 : 12) {
                    AvatarView(user: session.ownUser, size: isCompact ? 36 : 44, showsStatus: true)

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(session.ownUser?.name ?? session.displayName)
                                .font(isCompact ? .subheadline.weight(.semibold) : .headline)
                                .foregroundStyle(Theme.header)
                                .lineLimit(1)

                            Image(systemName: "chevron.down")
                                .font(.caption.bold())
                                .foregroundStyle(Theme.muted)
                        }

                        Text(statusText)
                            .font(isCompact ? .caption : .subheadline)
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            Button("Unreads", systemImage: "bell.fill", action: showUnreads)
                .labelStyle(.iconOnly)
                .font(isCompact ? .body : .title3)
                .foregroundStyle(Theme.muted)
                .frame(width: isCompact ? 36 : 44, height: isCompact ? 36 : 44)
                .overlay(alignment: .topTrailing) {
                    if hasUnread {
                        Circle()
                            .fill(Theme.red)
                            .frame(width: 10, height: 10)
                            .offset(x: -8, y: 8)
                    }
                }
        }
        .padding(.horizontal, isCompact ? 10 : 12)
        .padding(.vertical, isCompact ? 7 : 10)
        .background(Color(hex: "#202125"), in: .rect(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.06), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
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
