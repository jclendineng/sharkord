import SwiftUI

// the web composer's lists above the field: @ offers members and roles, # the server's
// channels, narrowed by what has been typed after it
struct MentionSuggestions: View {
    let trigger: String
    let query: String
    let onPick: (ComposerMention) -> Void

    @Environment(SessionStore.self) private var session

    private enum Item: Identifiable {
        case user(PublicUser)
        case role(Role)
        case channel(Channel)

        var id: String {
            switch self {
            case .user(let user): "user-\(user.id)"
            case .role(let role): "role-\(role.id)"
            case .channel(let channel): "channel-\(channel.id)"
            }
        }

        var name: String {
            switch self {
            case .user(let user): user.name
            case .role(let role): role.name
            case .channel(let channel): channel.name
            }
        }

        var mention: ComposerMention {
            switch self {
            case .user(let user): .user(user)
            case .role(let role): .role(role)
            case .channel(let channel): .channel(channel)
            }
        }
    }

    private var items: [Item] {
        var items: [Item]

        if trigger == "#" {
            items = session.channels
                .filter { !$0.isDm }
                .sorted { $0.position < $1.position }
                .map(Item.channel)
        } else {
            let users = session.usersById.values
                .filter { !$0.isDeleted && $0.id != session.ownUserId }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                .map(Item.user)
            let roles = session.rolesById.values
                .sorted { ($0.position ?? 0) < ($1.position ?? 0) }
                .map(Item.role)

            items = users + roles
        }

        return Self.filtered(items, by: query)
    }

    // filterByQuery in the web client: prefix matches above the rest, a shorter prefix match
    // first, so "gen" puts general above urgent-general
    private static func filtered(_ items: [Item], by query: String) -> [Item] {
        let limit = 10

        guard !query.isEmpty else {
            return Array(items.prefix(limit))
        }

        let query = query.lowercased()
        let matches = items.filter { $0.name.lowercased().contains(query) }
        let prefixed = matches
            .filter { $0.name.lowercased().hasPrefix(query) }
            .sorted { $0.name.count < $1.name.count }
        let rest = matches.filter { !$0.name.lowercased().hasPrefix(query) }

        return Array((prefixed + rest).prefix(limit))
    }

    var body: some View {
        let items = items

        if !items.isEmpty {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        Button {
                            onPick(item.mention)
                        } label: {
                            row(item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: 220)
            .fixedSize(horizontal: false, vertical: true)
            .background(Theme.inputBackground, in: .rect(cornerRadius: 16))
        }
    }

    private func row(_ item: Item) -> some View {
        HStack(spacing: 10) {
            switch item {
            case .user(let user):
                AvatarView(user: user, size: 26)
            case .role(let role):
                Image(systemName: "shield.fill")
                    .foregroundStyle(Color(hex: role.color))
                    .frame(width: 26, height: 26)
            case .channel:
                Image(systemName: "number")
                    .foregroundStyle(Theme.muted)
                    .frame(width: 26, height: 26)
            }

            Text(item.name)
                .font(.body.weight(.medium))
                .foregroundStyle(Theme.text)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .contentShape(.rect)
        .hoverHighlight()
    }
}
