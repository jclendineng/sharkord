import SwiftUI

// members are filtered locally, messages and files come from messages.search
struct SearchScreen: View {
    // the server's bounds for a search query
    private static let queryLength = 2...24

    // the channel it was opened from, put in as an in: filter that can be removed
    var channelId: Int?
    // opened from the messages panel, everything stays within direct messages
    var directMessages = false

    @Environment(ServerListStore.self) private var servers
    @Environment(SessionStore.self) private var session

    // shared with a search box outside the screen, the mac's chat top bar, or its own
    var model: SearchQueryModel?
    // false when that outside box is the one shown, so the screen has none of its own
    var showsSearchBox = true

    @State private var ownModel = SearchQueryModel()
    @State private var datePicker: FilterPicker?
    @State private var results: SearchResults?
    @State private var errorMessage: String?
    @State private var isSearching = false
    @State private var homes = SearchHomeCache()
    @FocusState private var isFieldFocused: Bool

    private var state: SearchQueryModel {
        model ?? ownModel
    }

    private var query: String {
        state.query
    }

    private var filters: SearchFilters {
        state.filters
    }

    private var token: FilterPicker? {
        state.token
    }

    // while a token is up, what is typed narrows its choices rather than searching
    private var trimmedQuery: String {
        guard token == nil else {
            return ""
        }

        return query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var members: [PublicUser] {
        guard !trimmedQuery.isEmpty else {
            return []
        }

        let partners = Set(session.directMessages.flatMap { [$0.userId] + ($0.group?.memberIds ?? []) })

        return session.members
            .filter { $0.id != session.ownUserId && $0.name.localizedCaseInsensitiveContains(trimmedQuery) }
            .filter { !directMessages || partners.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .prefix(8)
            .map { $0 }
    }

    private var prompt: String {
        state.prompt(in: session, directMessages: directMessages)
    }

    // nothing typed and no filter beyond the channel it was opened from shows discord's tabs
    private var isBrowsing: Bool {
        var rest = filters

        if rest.channel?.id == channelId {
            rest.channel = nil
        }

        return token == nil && trimmedQuery.isEmpty && rest.isEmpty
    }

    // the opening channel before onAppear has put it in the filters, so the first frame does
    // not load the whole server's tabs
    private var browsingScope: Channel? {
        guard state.hasAppliedChannel else {
            return channelId.flatMap { session.channel($0) }
        }

        return filters.channel
    }

    private var searchKey: [AnyHashable] {
        [trimmedQuery, filters]
    }

    var body: some View {
        if showsSearchBox {
            screen
                // the search box sits in the navigation bar between its back button and the
                // filters, the bar staying keeps the swipe back
                .inlineNavigationTitle()
                .navigationBarBackground(Theme.deepBackground)
                .navigationBarBackgroundVisible()
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        SearchBox(model: state, prompt: prompt, isFocused: $isFieldFocused)
                    }

                    ToolbarItem(placement: .barTrailing) {
                        FilterMenu(isFiltering: !filters.isEmpty, onChoose: choose)
                    }
                }
                // the field sits in the navigation bar, where focus state alone does not bring up
                // the keyboard, so once the screen has slid in the field is made first responder
                // directly. the mac's dropdown does not slide, so typing works there almost at once
                .task {
                    try? await Task.sleep(for: .milliseconds(Platform.isMac ? 50 : 450))
                    isFieldFocused = true
                    focusNavigationBarField()
                }
        } else {
            // the mac chat's panel types into the top bar's box and sits inside the chat's own
            // navigation, so it leaves the bar alone: hiding a bar of its own hid the chat's
            screen
        }
    }

    // a stack rather than a group: a group hands its modifiers to each branch, so the first
    // letter typed swapped the tabs for the results and rebuilt the bar's field, dropping focus
    private var screen: some View {
        VStack(spacing: 0) {
            if let token {
                FilterSuggestions(
                    picker: token,
                    text: query,
                    onPickUser: pick,
                    onPickChannel: pick,
                    onPickHas: pick
                )
            } else if isBrowsing {
                SearchHome(model: homes.model(for: browsingScope, directMessages: directMessages), onOpenChannel: openChannel, onOpenMessage: openMessage, onOpenUser: openDirectMessage(with:))
            } else {
                resultsList
            }
        }
        // a scroll puts the keyboard away. not a tap as well: a tap gesture over the results ate
        // the taps on them, so a result, a suggestion or a recent search never opened
        .scrollDismissesKeyboard(.immediately)
        // under the keyboard too, or its rounded top corners show the window's black behind them
        .background(Theme.deepBackground.ignoresSafeArea())
        // handed over by hand: on a mac a sheet's background is worked out before it inherits
        // anything, so a sheet reading a store it was not given crashed on opening
        .sheet(item: $datePicker) { picker in
            DateFilterSheet(picker: picker) { date in
                apply(date, for: picker)
            }
                .environment(session)
                .environment(servers)
                .appSheet()
        }
        .task(id: searchKey) {
            await search()
        }
        .onChange(of: state.pendingDatePicker, initial: true) { _, picker in
            if let picker {
                datePicker = picker
                state.pendingDatePicker = nil
            }
        }
        .onAppear {
            state.applyOpening(channel: channelId.flatMap { session.channel($0) }, directMessages: directMessages)
        }
    }

    private var resultsList: some View {
        List {
            if !filters.isEmpty {
                FilterChips(filters: Bindable(state).filters)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(Theme.redText)
                    .listRowBackground(Theme.groupedRowBackground)
            }

            if !members.isEmpty {
                Section("Members") {
                    ForEach(members) { user in
                        MemberResultRow(user: user, onOpen: { openDirectMessage(with: user) })
                    }
                }
            }

            if let results, !results.messages.isEmpty {
                Section("Messages") {
                    ForEach(results.messages) { message in
                        MessageResultRow(message: message, onOpen: { openMessage(channelId: message.channelId, messageId: message.id) })
                    }
                }
            }

            if let results, !results.files.isEmpty {
                Section("Files") {
                    ForEach(results.files) { file in
                        FileResultRow(file: file, onOpen: { openChannel(file.channelId) })
                    }
                }
            }

            if let results, results.truncated {
                Text("Showing the most recent matches. Try a more specific search.")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                    .listRowBackground(Color.clear)
            }
        }
        #if os(macOS)
        .listStyle(.inset)
        #else
        .listStyle(.insetGrouped)
        #endif
        .scrollContentBackground(.hidden)
        .listHoverHighlight()
        .scrollDismissesKeyboard(.interactively)
        .overlay {
            if isSearching {
                ProgressView()
            } else if hasNoResults {
                ContentUnavailableView.search(text: trimmedQuery)
            }
        }
    }

    // a picker filter puts its token in the box and lists its choices, a date opens the wheel
    private func choose(_ picker: FilterPicker) {
        if picker.isDate {
            datePicker = picker
            return
        }

        state.token = picker
        state.query = ""
        focusField()
    }

    // the box may be the mac's in the top bar, which watches for the request
    private func focusField() {
        if showsSearchBox {
            isFieldFocused = true
        } else {
            state.focusRequest += 1
        }
    }

    private func focusNavigationBarField() {
        #if os(iOS)
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)

        guard let window = windows.first(where: \.isKeyWindow) else {
            return
        }

        // the topmost one, a full screen cover's bar over the screen it covers
        let field = navigationBarFields(in: window).last

        field?.becomeFirstResponder()
        #endif
    }

    #if os(iOS)
    private func navigationBarFields(in view: UIView, isInBar: Bool = false) -> [UITextField] {
        let isBar = isInBar || view is UINavigationBar

        if isBar, let field = view as? UITextField {
            return [field]
        }

        return view.subviews.flatMap { navigationBarFields(in: $0, isInBar: isBar) }
    }
    #endif

    private func clearToken() {
        state.clearToken()
    }

    private func pick(_ user: PublicUser) {
        if token == .from {
            state.filters.from = user
        } else {
            state.filters.mentions = user
        }

        clearToken()
    }

    private func pick(_ channel: Channel) {
        state.filters.channel = channel
        clearToken()
    }

    private func pick(_ kind: SearchFilters.Has) {
        state.filters.has = kind
        clearToken()
    }

    // sent on a day replaces a range, and a range replaces sent on, they would contradict
    private func apply(_ date: Date, for picker: FilterPicker) {
        switch picker {
        case .on:
            state.filters.on = date
            state.filters.before = nil
            state.filters.after = nil
        case .before:
            state.filters.before = date
            state.filters.on = nil
        case .after:
            state.filters.after = date
            state.filters.on = nil
        case .from, .channel, .mentions, .has:
            break
        }
    }

    private var hasNoResults: Bool {
        guard let results, errorMessage == nil else {
            return false
        }

        return members.isEmpty && results.messages.isEmpty && results.files.isEmpty
    }

    // debounced through task(id:), which cancels the previous run on every keystroke
    private func search() async {
        let text = trimmedQuery

        errorMessage = nil

        if text.count > Self.queryLength.upperBound {
            results = nil
            errorMessage = String(localized: "Searches can be at most \(Self.queryLength.upperBound) characters.")
            return
        }

        guard !isBrowsing else {
            results = nil
            return
        }

        // a filter alone is enough, words need two characters at least
        guard Self.queryLength.contains(text.count) || (text.isEmpty && !filters.isEmpty) else {
            results = nil
            return
        }

        try? await Task.sleep(for: .milliseconds(400))

        guard !Task.isCancelled, let client = try? await session.readyClient() else {
            return
        }

        isSearching = true

        defer {
            isSearching = false
        }

        do {
            let input = SearchInput(query: text.isEmpty ? nil : text, filters: filters)
            let found: SearchResults = try await client.query("messages.search", input: input)

            if !Task.isCancelled {
                results = keepsDirectMessages ? found : found.withoutDirectMessages(isServerChannel: isServerChannel)
            }
        } catch {
            if !Task.isCancelled {
                results = nil
                errorMessage = error.localizedDescription
            }
        }
    }

    // the messages panel's search, or one narrowed to a conversation
    private var keepsDirectMessages: Bool {
        directMessages || filters.channel?.isDm == true
    }

    // a closed conversation is not in the list at all, so only a channel known to be the server's
    // counts as one
    private func isServerChannel(_ channelId: Int) -> Bool {
        session.channel(channelId)?.isDm == false
    }

    private func openChannel(_ channelId: Int) {
        servers.open(channelId: channelId, in: session)
    }

    private func openMessage(channelId: Int, messageId: Int) {
        servers.open(channelId: channelId, messageId: messageId, in: session)
    }

    private func openDirectMessage(with user: PublicUser) {
        guard user.id != session.ownUserId else {
            return
        }

        Task {
            do {
                let channelId = try await session.openDirectMessage(with: user.id)

                servers.open(channelId: channelId, in: session)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}


// what is being searched, kept apart from the screen so a search box elsewhere, the mac's in
// the chat's top bar, can type into the same search the dropdown under it shows
@Observable
final class SearchQueryModel {
    var query = ""
    var filters = SearchFilters()
    // the filter whose choices are listed under the box, its token sitting in the box
    var token: FilterPicker?
    // the opening channel goes in once, so removing its chip sticks
    var hasAppliedChannel = false
    // bumped to put the cursor in a box the screen does not own
    var focusRequest = 0
    // a date filter chosen from a menu outside the screen, which opens the screen's date wheel
    var pendingDatePicker: FilterPicker?

    func applyOpening(channel: Channel?, directMessages: Bool) {
        if !hasAppliedChannel, let channel {
            filters.channel = channel
        }

        hasAppliedChannel = true
        filters.directMessagesOnly = directMessages
    }

    func clearToken() {
        token = nil
        query = ""
    }

    // discord names the channel being searched, or the server when it is all of it
    func prompt(in session: SessionStore, directMessages: Bool) -> String {
        guard token == nil else {
            return ""
        }

        guard let channel = filters.channel else {
            return directMessages ? String(localized: "Search in DMs") : String(localized: "Search in \(session.displayName)")
        }

        return String(localized: "Search in \(FilterChips.place(channel, in: session))")
    }
}

// discord's search box, with the filter being picked sitting in it as a token. the same box in
// a search screen's bar and in the mac's chat top bar
struct SearchBox: View {
    let model: SearchQueryModel
    let prompt: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        @Bindable var model = model

        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.muted)

            if let token = model.token {
                Button(action: clearToken) {
                    Text(token.token)
                        .font(.subheadline)
                        .foregroundStyle(Theme.header)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Theme.inputBackground, in: .rect(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(token.token) filter")
            }

            TextField("", text: $model.query, prompt: Text(prompt).foregroundStyle(Theme.muted))
                .focused(isFocused)
                .foregroundStyle(Theme.header)
                .noAutocapitalization()
                .autocorrectionDisabled()
                .submitLabel(.search)
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .frame(maxWidth: .infinity)
        .background(Theme.listBackground, in: .rect(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isFocused.wrappedValue ? Theme.blurple : Theme.divider, lineWidth: 1)
        }
    }

    private func clearToken() {
        model.clearToken()
    }
}

private struct MemberResultRow: View {
    let user: PublicUser
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                AvatarView(user: user, size: 32, showsStatus: true)

                Text(user.name)
                    .foregroundStyle(Theme.header)

                Spacer()

                Image(systemName: "bubble.left.fill")
                    .foregroundStyle(Theme.muted)
            }
            .contentShape(.rect)
        }
        .listRowBackground(Color.searchResultRow)
    }
}

private struct MessageResultRow: View {
    let message: SearchMessage
    let onOpen: () -> Void

    @Environment(SessionStore.self) private var session

    private var author: PublicUser? {
        message.userId.flatMap { session.usersById[$0] }
    }

    // a direct message is named after the other person, not its channel
    private var place: String {
        guard message.channelIsDm else {
            return String(localized: "#\(message.channelName)")
        }

        return String(localized: "@\(session.conversationTitle(for: message.channelId))")
    }

    // the gifs and pictures shown from its links, as the chat shows them
    private var images: [URL] {
        (message.metadata ?? [])
            .filter(\.isImage)
            .compactMap { URL(string: $0.url) }
    }

    // a message that is only a picture's link shows the picture, not the address
    private var text: String? {
        let content = message.plainContent.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !content.isEmpty, !images.contains(where: { $0.absoluteString == content }) else {
            return nil
        }

        return content
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 12) {
                AvatarView(user: author, size: 32)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(author?.name ?? "Unknown")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(session.nameColor(for: author))

                        Text(place)
                            .font(.caption)
                            .foregroundStyle(Theme.muted)

                        Spacer(minLength: 0)

                        Text(MessageDate.timestamp(message.createdDate))
                            .font(.caption2)
                            .foregroundStyle(Theme.muted)
                    }
                    .lineLimit(1)

                    if let text {
                        if let content = message.content {
                            // drawn as the chat and the inbox draw it, a mention as a tinted name
                            // rather than the raw @ the plain text has
                            MessageContentView(html: content)
                                .lineLimit(3)
                                .allowsHitTesting(false)
                        } else {
                            Text(text)
                                .font(.subheadline)
                                .foregroundStyle(Theme.text)
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)
                        }
                    }

                    ForEach(images, id: \.self) { url in
                        AnimatedImage(url: url, maxPointSize: 220)
                            .frame(maxWidth: 220, maxHeight: 220, alignment: .leading)
                            .clipShape(.rect(cornerRadius: 6))
                    }
                }
            }
            .contentShape(.rect)
        }
        .listRowBackground(Color.searchResultRow)
    }
}

private struct FileResultRow: View {
    let file: SearchFile
    let onOpen: () -> Void

    @Environment(SessionStore.self) private var session

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                Image(systemName: file.file.isImage ? "photo" : "doc")
                    .font(.title3)
                    .foregroundStyle(Theme.muted)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(file.file.originalName)
                        .foregroundStyle(Theme.link)
                        .lineLimit(1)

                    Text(session.isDirectMessage(file.channelId) ? "@\(session.conversationTitle(for: file.channelId))" : "#\(file.channelName)")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .listRowBackground(Color.searchResultRow)
    }
}

private extension Color {
    // a phone's results are grouped cards. a mac's list cannot round a group, so its rows sit on
    // the card around them, as pinned messages do, rather than on a band to its edges
    static var searchResultRow: Color {
        #if os(macOS)
        .clear
        #else
        Theme.listBackground
        #endif
    }
}
