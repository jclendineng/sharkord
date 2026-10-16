import SwiftUI

// discord's expression panel, in the keyboard's place like the attachment panel: emoji go into
// the message, a gif or a sticker is sent on its own. it rides the same model as the attachment
// panel, so it drags, dims and trades places with the keyboard the same way
struct ExpressionPanel: View {
    enum Tab: String, CaseIterable, Identifiable {
        case emoji = "Emoji"
        case gifs = "GIFs"
        case stickers = "Stickers"

        var id: Self { self }

        // the order the tabs run in, the mac's matching its buttons in the message box
        static var shown: [Tab] {
            ProcessInfo.processInfo.isiOSAppOnMac ? [.gifs, .stickers, .emoji] : allCases
        }
    }

    let model: AttachPanelModel
    let onEmoji: (String) -> Void
    let onBackspace: () -> Void
    let onGif: (Gif) -> Void
    let onSticker: (Sticker) -> Void

    var body: some View {
        @Bindable var model = model

        ComposerPanel(model: model) {
            VStack(spacing: 0) {
                TabPicker(selection: $model.expressionTab)
                    .padding(.horizontal, 10)
                    .padding(.top, 30)
                    .padding(.bottom, 8)

                switch model.expressionTab {
                case .emoji:
                    EmojiTab(onPick: onEmoji, onBackspace: onBackspace)
                case .gifs:
                    GifTab(onPick: onGif)
                case .stickers:
                    StickerTab(onPick: onSticker)
                }
            }
        } bar: {
            EmptyView()
        }
        .environment(model)
    }
}

// the mac's picker: discord's card over the chat, above the message box at its right, its tabs in
// the order of the buttons that open it
struct ExpressionPicker: View {
    static let height: CGFloat = 520

    let model: AttachPanelModel
    let onEmoji: (String) -> Void
    let onBackspace: () -> Void
    let onGif: (Gif) -> Void
    let onSticker: (Sticker) -> Void

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            TabPicker(selection: $model.expressionTab)
                .padding(10)

            switch model.expressionTab {
            case .emoji:
                EmojiTab(onPick: onEmoji, onBackspace: onBackspace)
            case .gifs:
                GifTab(onPick: onGif)
            case .stickers:
                StickerTab(onPick: onSticker)
            }
        }
        .frame(width: 480, height: Self.height)
        .background(Theme.deepBackground)
        .clipShape(.rect(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.panelEdge, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.45), radius: 20, y: 8)
        .compositingGroup()
        .environment(model)
    }
}

// discord's segmented control, a raised pill on the picked tab
private struct TabPicker: View {
    @Binding var selection: ExpressionPanel.Tab

    @Namespace private var pill

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ExpressionPanel.Tab.shown) { tab in
                TabButton(tab: tab, isSelected: tab == selection, pill: pill) {
                    withAnimation(.snappy(duration: 0.2)) {
                        selection = tab
                    }
                }
            }
        }
        .padding(4)
        .background(Color(hex: "#2B2C31"), in: .rect(cornerRadius: 14, style: .continuous))
    }
}

private struct TabButton: View {
    let tab: ExpressionPanel.Tab
    let isSelected: Bool
    let pill: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(tab.rawValue)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? Theme.header : Theme.muted)
                .frame(maxWidth: .infinity, minHeight: 34)
                .hoverHighlight(cornerRadius: 10)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Theme.inputBackground)
                            .matchedGeometryEffect(id: "pill", in: pill)
                    }
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

private struct SearchField: View {
    let prompt: String
    @Binding var text: String

    @Environment(AttachPanelModel.self) private var panel

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.muted)

            TextField("", text: $text, prompt: Text(prompt).foregroundStyle(Theme.muted))
                .foregroundStyle(Theme.header)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isFocused)
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isFocused ? Theme.blurple : Theme.divider, lineWidth: 1)
        }
        .padding(.horizontal, 10)
        // like discord, searching takes the panel to full height with the keyboard over its
        // bottom, so the results scroll in the room between the two
        .onChange(of: isFocused) { _, focused in
            if focused {
                panel.beginSearch()
            }
        }
        .onChange(of: panel.searchDismissals) {
            isFocused = false
        }
    }
}

// what was picked most recently first, kept on the phone, as discord's frequently used
enum FrequentExpressions {
    private static let emojiKey = "frequentEmoji"
    private static let stickerKey = "frequentStickers"
    private static let limit = 27

    static var emoji: [String] {
        UserDefaults.standard.stringArray(forKey: emojiKey) ?? ["heart", "joy", "+1", "fire", "100", "sob", "pray", "tada", "eyes"]
    }

    static var stickers: [Int] {
        (UserDefaults.standard.array(forKey: stickerKey) as? [Int]) ?? []
    }

    static func use(emoji value: String) {
        UserDefaults.standard.set(Array(([value] + emoji.filter { $0 != value }).prefix(limit)), forKey: emojiKey)
    }

    static func use(sticker id: Int) {
        UserDefaults.standard.set(Array(([id] + stickers.filter { $0 != id }).prefix(limit)), forKey: stickerKey)
    }
}


private struct EmojiTab: View {
    let onPick: (String) -> Void
    let onBackspace: () -> Void

    @Environment(SessionStore.self) private var session

    @State private var query = ""
    @State private var frequent = FrequentExpressions.emoji

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 8)

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespaces).lowercased()
    }

    // the section ids the bottom bar jumps to
    private var sections: [(id: String, symbol: String)] {
        var list: [(String, String)] = [("frequent", "clock.fill")]

        if !session.customEmojis.isEmpty {
            list.append(("server", "server.rack"))
        }

        return list + EmojiCatalog.groups.map { ($0.name, Self.symbol(for: $0.name)) }
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                SearchField(prompt: "Find the perfect emoji", text: $query)
                    .padding(.bottom, 8)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14, pinnedViews: []) {
                        if normalizedQuery.isEmpty {
                            section("Frequently Used", id: "frequent") {
                                ForEach(frequent, id: \.self) { value in
                                    cell(value: value, file: session.customEmoji(named: value)?.file)
                                }
                            }

                            if !session.customEmojis.isEmpty {
                                section(session.serverName, id: "server") {
                                    ForEach(session.customEmojis) { emoji in
                                        cell(value: emoji.name, file: emoji.file)
                                    }
                                }
                            }

                            ForEach(EmojiCatalog.groups, id: \.name) { group in
                                section(Self.title(for: group.name), id: group.name) {
                                    ForEach(group.emoji) { entry in
                                        cell(value: entry.shortcode, file: nil)
                                    }
                                }
                            }
                        } else {
                            LazyVGrid(columns: columns, spacing: 2) {
                                ForEach(searchResults, id: \.self) { value in
                                    cell(value: value, file: session.customEmoji(named: value)?.file)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 80)
                }
                .scrollDismissesKeyboard(.immediately)
            }
            .overlay(alignment: .bottom) {
                categoryBar(proxy)
            }
        }
    }

    private var searchResults: [String] {
        let custom = session.customEmojis.map(\.name).filter { $0.lowercased().contains(normalizedQuery) }
        let unicode = EmojiCatalog.all.filter { entry in
            entry.shortcodes.contains { $0.contains(normalizedQuery) }
        }

        return custom + unicode.map(\.shortcode)
    }

    private func section<Content: View>(_ title: String, id: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.text)

            LazyVGrid(columns: columns, spacing: 2) {
                content()
            }
        }
        .id(id)
    }

    private func cell(value: String, file: SharkordFile?) -> some View {
        Button {
            pick(value)
        } label: {
            EmojiView(value: value, file: file, size: 30)
                .frame(maxWidth: .infinity, minHeight: 44)
                .hoverHighlight(cornerRadius: 8)
        }
        .buttonStyle(.plain)
    }

    // discord's bar of section icons along the bottom, with a backspace at its end
    private func categoryBar(_ proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(sections, id: \.id) { section in
                        Button {
                            withAnimation(.snappy) {
                                proxy.scrollTo(section.id, anchor: .top)
                            }
                        } label: {
                            Image(systemName: section.symbol)
                                .font(.system(size: 17))
                                .foregroundStyle(Theme.muted)
                                .frame(width: 40, height: 40)
                                .hoverHighlight(cornerRadius: 8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
            }
            .scrollIndicators(.hidden)

            Button("Delete", systemImage: "delete.left.fill", action: onBackspace)
                .labelStyle(.iconOnly)
                .font(.system(size: 18))
                .foregroundStyle(Theme.muted)
                .frame(width: 52, height: 40)
        }
        .padding(.vertical, 6)
        .background(ComposerPanel<EmptyView, EmptyView>.background)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.divider.opacity(0.6)).frame(height: 1)
        }
    }

    private func pick(_ value: String) {
        onPick(value)
        FrequentExpressions.use(emoji: value)
    }

    // the github emoji groups by their names in emoji.json, as discord labels its sections
    private static let groupNames: [String: (title: String, symbol: String)] = [
        "other": ("Smileys", "face.smiling"),
        "people & body": ("People", "hand.wave"),
        "animals & nature": ("Nature", "leaf"),
        "food & drink": ("Food & Drink", "fork.knife"),
        "travel & places": ("Travel & Places", "car"),
        "activities": ("Activities", "soccerball"),
        "objects": ("Objects", "lightbulb"),
        "symbols": ("Symbols", "heart"),
        "flags": ("Flags", "flag"),
        "GitHub": ("GitHub", "chevron.left.forwardslash.chevron.right")
    ]

    private static func title(for group: String) -> String {
        groupNames[group]?.title ?? group.capitalized
    }

    private static func symbol(for group: String) -> String {
        groupNames[group]?.symbol ?? "circle.grid.2x2"
    }
}


private struct GifTab: View {
    // what the tab shows: the tiles it opens with, or a list of gifs
    private enum Mode: Equatable {
        case categories
        case trending
        case search(String)
    }

    let onPick: (Gif) -> Void

    @Environment(SessionStore.self) private var session

    @State private var query = ""
    @State private var mode = Mode.categories
    @State private var categories: [GifCategory] = []
    @State private var gifs: [Gif] = []
    @State private var page = 1
    @State private var hasMore = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var isEnabled: Bool {
        session.settings?.gifsEnabled == true
    }

    var body: some View {
        VStack(spacing: 0) {
            if isEnabled {
                SearchField(prompt: "Search Klipy", text: $query)
                    .padding(.bottom, 8)

                ScrollView {
                    VStack(spacing: 6) {
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.subheadline)
                                .foregroundStyle(Theme.muted)
                                .padding(.vertical, 20)
                        }

                        if mode == .categories {
                            categoryGrid
                        } else {
                            gifColumns
                        }

                        if isLoading {
                            ProgressView()
                                .padding(.vertical, 16)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 30)
                }
                .scrollDismissesKeyboard(.immediately)
            } else {
                Text("GIFs aren't set up on this server. An admin can add a Klipy API key in Server Settings, under Overview.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .padding(30)
                    .frame(maxHeight: .infinity)
            }
        }
        .task {
            await loadCategories()
        }
        // a pause in typing searches, clearing the box goes back to the tiles
        .task(id: query) {
            let trimmed = query.trimmingCharacters(in: .whitespaces)

            try? await Task.sleep(for: .milliseconds(350))

            guard !Task.isCancelled else {
                return
            }

            if trimmed.isEmpty {
                if case .search = mode {
                    mode = .categories
                }
            } else {
                mode = .search(trimmed)
            }
        }
        .onChange(of: mode) { _, newMode in
            gifs = []

            Task {
                await load(newMode, page: 1)
            }
        }
    }

    private var categoryGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
            CategoryTile(title: "Trending GIFs", systemImage: "chart.line.uptrend.xyaxis", previewUrl: categories.first?.previewUrl) {
                mode = .trending
            }

            ForEach(categories) { category in
                CategoryTile(title: category.term, systemImage: nil, previewUrl: category.previewUrl) {
                    query = category.term
                }
            }
        }
    }

    // two columns, each gif in the shorter one, so the heights stay even like discord's
    private var gifColumns: some View {
        let columns = Self.split(gifs)

        return HStack(alignment: .top, spacing: 6) {
            ForEach(0..<2, id: \.self) { index in
                LazyVStack(spacing: 6) {
                    ForEach(columns[index]) { gif in
                        Button {
                            onPick(gif)
                        } label: {
                            AnimatedImage(url: URL(string: gif.previewUrl), maxPointSize: 200)
                                .aspectRatio(gif.width / max(gif.height, 1), contentMode: .fit)
                                .background(Theme.inputBackground)
                                .clipShape(.rect(cornerRadius: 8, style: .continuous))
                                .hoverBrighten(cornerRadius: 8)
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            loadMoreIfNeeded(after: gif)
                        }
                    }
                }
            }
        }
    }

    private static func split(_ gifs: [Gif]) -> [[Gif]] {
        var columns: [[Gif]] = [[], []]
        var heights: [Double] = [0, 0]

        for gif in gifs {
            let index = heights[0] <= heights[1] ? 0 : 1

            columns[index].append(gif)
            heights[index] += gif.height / max(gif.width, 1)
        }

        return columns
    }

    private func loadMoreIfNeeded(after gif: Gif) {
        guard hasMore, !isLoading, gifs.suffix(6).contains(gif) else {
            return
        }

        Task {
            await load(mode, page: page + 1)
        }
    }

    private func loadCategories() async {
        guard isEnabled, categories.isEmpty else {
            return
        }

        do {
            categories = try await session.request("gifs.categories")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func load(_ target: Mode, page: Int) async {
        struct TrendingInput: Encodable {
            let page: Int
        }

        struct SearchInput: Encodable {
            let query: String
            let page: Int
        }

        if target == .categories {
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let result: GifPage

            switch target {
            case .search(let text):
                result = try await session.request("gifs.search", SearchInput(query: text, page: page))
            default:
                result = try await session.request("gifs.trending", TrendingInput(page: page))
            }

            // a newer mode may have taken over while this one loaded
            if target == mode {
                gifs = page == 1 ? result.gifs : gifs + result.gifs
                hasMore = result.hasMore
                self.page = page
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

private struct CategoryTile: View {
    let title: String
    let systemImage: String?
    let previewUrl: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                AnimatedImage(url: previewUrl.flatMap(URL.init(string:)), maxPointSize: 200)

                Color.black.opacity(0.45)

                HStack(spacing: 6) {
                    if let systemImage {
                        Image(systemName: systemImage)
                    }

                    Text(title)
                }
                .font(.headline)
                .foregroundStyle(.white)
            }
            .frame(height: 92)
            .background(Theme.inputBackground)
            .clipShape(.rect(cornerRadius: 8, style: .continuous))
            .hoverBrighten(cornerRadius: 8)
        }
        .buttonStyle(.plain)
    }
}


private struct StickerTab: View {
    let onPick: (Sticker) -> Void

    @Environment(SessionStore.self) private var session

    @State private var query = ""
    @State private var frequentIds = FrequentExpressions.stickers

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    private var shown: [Sticker] {
        let text = query.trimmingCharacters(in: .whitespaces).lowercased()

        guard !text.isEmpty else {
            return session.stickers
        }

        return session.stickers.filter {
            $0.name.lowercased().contains(text) || ($0.description ?? "").lowercased().contains(text)
        }
    }

    private var frequent: [Sticker] {
        frequentIds.compactMap { id in session.stickers.first { $0.id == id } }
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchField(prompt: "Find the perfect sticker", text: $query)
                .padding(.bottom, 8)

            if session.stickers.isEmpty {
                Text("This server has no stickers yet. Admins can add some in Server Settings.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .padding(30)
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if query.isEmpty && !frequent.isEmpty {
                            stickerSection("Frequently Used", stickers: frequent)
                        }

                        stickerSection(session.serverName, stickers: shown)
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 30)
                }
                .scrollDismissesKeyboard(.immediately)
            }
        }
    }

    private func stickerSection(_ title: String, stickers: [Sticker]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.text)

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(stickers) { sticker in
                    StickerCell(sticker: sticker) {
                        FrequentExpressions.use(sticker: sticker.id)
                        onPick(sticker)
                    }
                }
            }
        }
    }
}

private struct StickerCell: View {
    let sticker: Sticker
    let action: () -> Void

    @Environment(SessionStore.self) private var session

    var body: some View {
        Button(action: action) {
            AnimatedImage(url: session.address?.fileURL(sticker.file), maxPointSize: 100, contentMode: .scaleAspectFit)
                .aspectRatio(1, contentMode: .fit)
                .hoverHighlight(cornerRadius: 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(sticker.name)
    }
}
