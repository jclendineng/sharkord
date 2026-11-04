import SwiftUI

struct ReactionsView: View {
    let message: Message

    @Environment(SessionStore.self) private var session
    @Environment(ServerListStore.self) private var servers

    @State private var isPickerPresented = false
    // a tap shows at once, the server's update catching up. each emoji holds whether it should
    // be yours until the message says so, so someone else reacting meanwhile does not undo it
    @State private var pendingMine: [String: Bool] = [:]

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

        guard let ownUserId = session.ownUserId else {
            return groups
        }

        for (emoji, isMine) in pendingMine {
            if let index = groups.firstIndex(where: { $0.emoji == emoji }) {
                groups[index].userIds.removeAll { $0 == ownUserId }

                if isMine {
                    groups[index].userIds.append(ownUserId)
                }
            } else if isMine {
                groups.append(Group(emoji: emoji, file: nil, userIds: [ownUserId]))
            }
        }

        return groups.filter { !$0.userIds.isEmpty }
    }

    private func isMineOnServer(_ emoji: String) -> Bool {
        message.reactions.contains { $0.emoji == emoji && $0.userId == session.ownUserId }
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
        .animation(.snappy(duration: 0.2), value: groups.map(\.userIds.count))
        .onChange(of: message.reactions, settlePending)
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
        guard !isMine(emoji) else {
            return
        }

        toggle(emoji)
    }

    private func isMine(_ emoji: String) -> Bool {
        pendingMine[emoji] ?? isMineOnServer(emoji)
    }

    private func toggle(_ emoji: String) {
        let wantsMine = !isMine(emoji)

        pendingMine[emoji] = wantsMine
        Haptics.selection()

        Task {
            do {
                try await session.toggleReaction(messageId: message.id, emoji: emoji)
            } catch {
                pendingMine[emoji] = nil
                session.showError(error)
            }
        }
    }

    private func settlePending() {
        pendingMine = pendingMine.filter { emoji, isMine in
            isMineOnServer(emoji) != isMine
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
                    .contentTransition(.numericText(value: Double(count)))
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
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isMine ? .isSelected : [])
    }

    private var accessibilityLabel: String {
        let name = emoji.hasPrefix(":") ? emoji.trimmingCharacters(in: CharacterSet(charactersIn: ":")) : emoji

        return count == 1 ? String(localized: "\(name), 1 reaction") : String(localized: "\(name), \(count) reactions")
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
