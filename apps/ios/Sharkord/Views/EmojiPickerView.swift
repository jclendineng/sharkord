import SwiftUI

struct EmojiPickerView: View {
    // custom emoji can be reactions, but the composer only inserts unicode characters
    let includesCustom: Bool
    var title = "Emoji"
    var subtitle: String?
    var detents: Set<PresentationDetent> = [.medium, .large]
    let onPick: (String) -> Void

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""

    private let columns = [GridItem(.adaptive(minimum: 44), spacing: 4)]

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespaces).lowercased()
    }

    private var searchResults: [EmojiEntry] {
        EmojiCatalog.all.filter { entry in
            entry.shortcodes.contains { $0.contains(normalizedQuery) }
        }
    }

    private var customEmojis: [CustomEmoji] {
        guard includesCustom else {
            return []
        }

        if normalizedQuery.isEmpty {
            return session.customEmojis
        }

        return session.customEmojis.filter { $0.name.lowercased().contains(normalizedQuery) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if !customEmojis.isEmpty {
                        section(session.serverName) {
                            ForEach(customEmojis) { emoji in
                                cell(value: emoji.name, file: emoji.file)
                            }
                        }
                    }

                    if normalizedQuery.isEmpty {
                        ForEach(EmojiCatalog.groups, id: \.name) { group in
                            section(group.name) {
                                ForEach(group.emoji) { entry in
                                    cell(value: entry.shortcode, file: nil)
                                }
                            }
                        }
                    } else {
                        LazyVGrid(columns: columns, spacing: 4) {
                            ForEach(searchResults) { entry in
                                cell(value: entry.shortcode, file: nil)
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
            .background(Theme.chatBackground)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Find the perfect emoji")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let subtitle {
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 1) {
                            Text(title)
                                .font(.headline)
                                .foregroundStyle(Theme.header)

                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                        }
                    }
                }
            }
        }
        .sheetDetents(detents)
        .presentationBackground(Theme.chatBackground)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.muted)

            LazyVGrid(columns: columns, spacing: 4) {
                content()
            }
        }
    }

    private func cell(value: String, file: SharkordFile?) -> some View {
        Button(action: { pick(value) }) {
            EmojiView(value: value, file: file, size: 32)
                .frame(width: 44, height: 44)
                .hoverHighlight(cornerRadius: 8)
        }
        .buttonStyle(.plain)
    }

    private func pick(_ value: String) {
        onPick(value)
        dismiss()
    }
}
