import SwiftUI

// discord's member list down the right of a wide chat: who is online, then who is not, each
// opening their profile beside the row
struct MembersColumn: View {
    static let width: CGFloat = 240

    @Environment(SessionStore.self) private var session

    private var sections: [(title: String, users: [PublicUser])] {
        let sorted = session.members.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let online = sorted.filter { $0.status != .offline }
        let offline = sorted.filter { $0.status == .offline }

        return [("Online", online), ("Offline", offline)].filter { !$0.users.isEmpty }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(sections, id: \.title) { section in
                    Text("\(section.title.uppercased()) · \(section.users.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 10)
                        .padding(.top, 16)
                        .padding(.bottom, 4)

                    ForEach(section.users) { user in
                        MemberColumnRow(user: user)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .frame(width: Self.width)
        .background(Theme.listBackground)
    }
}

private struct MemberColumnRow: View {
    let user: PublicUser

    @Environment(SessionStore.self) private var session
    @Environment(ServerListStore.self) private var servers

    @State private var isProfilePresented = false
    @State private var isHovered = false

    private var isOffline: Bool {
        user.status == .offline
    }

    var body: some View {
        Button(action: showProfile) {
            HStack(spacing: 10) {
                AvatarView(user: user, size: 32, showsStatus: true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(user.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color(hex: session.roleColor(for: user) ?? "#F2F3F5"))
                        .lineLimit(1)

                    if let customStatus = user.customStatus, !customStatus.isEmpty {
                        Text(customStatus)
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }
            // discord dims who is away, the row stays readable
            .opacity(isOffline && !isHovered ? 0.45 : 1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isHovered ? Theme.hover : .clear, in: .rect(cornerRadius: 6))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover(perform: setHovered)
        // handed the stores by hand: on a mac a presentation is worked out before it inherits
        .popover(isPresented: $isProfilePresented, arrowEdge: .leading) {
            MemberProfileSheet(user: user, onMessage: openDirectMessage)
                .frame(idealWidth: 340, idealHeight: 560)
                .environment(session)
                .environment(servers)
        }
    }

    private func setHovered(_ hovered: Bool) {
        isHovered = hovered
    }

    private func showProfile() {
        isProfilePresented = true
    }

    private func openDirectMessage() {
        isProfilePresented = false

        Task {
            guard let channelId = try? await session.openDirectMessage(with: user.id) else {
                return
            }

            servers.open(channelId: channelId, in: session)
        }
    }
}
