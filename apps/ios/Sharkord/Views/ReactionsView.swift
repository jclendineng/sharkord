import SwiftUI

struct ReactionsView: View {
    let message: Message

    @Environment(SessionStore.self) private var session
    @Environment(ServerListStore.self) private var servers

    @State private var isPickerPresented = false

    private struct Group: Identifiable {
        let emoji: String
        let file: SharkordFile?
        var userIds: [Int]

        var id: String { emoji }
    }

    // reactions arrive one row per user, discord shows one pill per emoji in first-seen order
    private var groups: [Group] {
        var groups: [Group] = []

        for reaction in message.reactions {
            if let index = groups.firstIndex(where: { $0.emoji == reaction.emoji }) {
                groups[index].userIds.append(reaction.userId ?? -1)
            } else {
                groups.append(Group(emoji: reaction.emoji, file: reaction.file, userIds: [reaction.userId ?? -1]))
            }
        }

        return groups
    }

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(groups) { group in
                ReactionPill(
                    emoji: group.emoji,
                    file: group.file,
                    count: group.userIds.count,
                    isMine: session.ownUserId.map(group.userIds.contains) ?? false,
                    onTap: { toggle(group.emoji) }
                )
            }

            // discord's smiley at the end of the row, another reaction without the long press
            if session.can(.reactToMessages) {
                Button(action: openPicker) {
                    Label("Add Reaction", systemImage: "face.smiling")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.listBackground, in: .rect(cornerRadius: 8))
                        .contentShape(.rect(cornerRadius: 8))
                }
                    .hoverBrighten(cornerRadius: 8)
                    .buttonStyle(.plain)
            }
        }
        .padding(.top, 2)
        // handed over by hand: on a mac a sheet's background is worked out before it inherits
        // anything, so a sheet reading a store it was not given crashed on opening
        .sheet(isPresented: $isPickerPresented) {
            EmojiPickerView(includesCustom: true, onPick: add)
                .environment(session)
                .environment(servers)
                .appSheet(addsClose: true)
        }
    }

    private func openPicker() {
        isPickerPresented = true
    }

    // one already on it from you stays, the picker only adds
    private func add(_ emoji: String) {
        let isMine = message.reactions.contains { $0.emoji == emoji && $0.userId == session.ownUserId }

        guard !isMine else {
            return
        }

        toggle(emoji)
    }

    private func toggle(_ emoji: String) {
        Task {
            do {
                try await session.toggleReaction(messageId: message.id, emoji: emoji)
            } catch {
                session.showError(error)
            }
        }
    }
}

private struct ReactionPill: View {
    let emoji: String
    let file: SharkordFile?
    let count: Int
    let isMine: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                EmojiView(value: emoji, file: file, size: 18)

                Text("\(count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isMine ? Theme.mentionText : Theme.muted)
                    .monospacedDigit()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isMine ? Theme.blurple.opacity(0.15) : Theme.listBackground, in: .rect(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isMine ? Theme.blurple : .clear)
            }
            .hoverBrighten(cornerRadius: 8)
        }
        .buttonStyle(.plain)
    }
}

// renders a reaction or picker emoji: a custom emoji file, a unicode character, or a github image
struct EmojiView: View {
    let value: String
    var file: SharkordFile?
    let size: CGFloat

    @Environment(SessionStore.self) private var session

    var body: some View {
        if let customFile, let address = session.address {
            CachedFileImage(file: customFile, url: address.fileURL(customFile), contentMode: .fit) {
                Color.clear
            }
            .frame(width: size, height: size)
        } else if let url = imageURL {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Color.clear
            }
            .frame(width: size, height: size)
        } else {
            Text(EmojiCatalog.find(value)?.emoji ?? ":\(value):")
                .font(.system(size: size * 0.9))
        }
    }

    private var customFile: SharkordFile? {
        file ?? session.customEmoji(named: value)?.file
    }

    // a built in emoji drawn from github's picture of it
    private var imageURL: URL? {
        if let entry = EmojiCatalog.find(value), entry.emoji == nil {
            return entry.image.flatMap(URL.init(string:))
        }

        return nil
    }
}
