import SwiftUI

// members are filtered locally, messages and files come from messages.search
struct SearchScreen: View {
    // the server's bounds for a search query
    private static let queryLength = 2...24

    // the channel it was opened from, put in as an in: filter that can be removed
    var channelId: Int?

    @Environment(ServerListStore.self) private var servers
    @Environment(SessionStore.self) private var session

    @State private var query = ""
    @State private var filters = SearchFilters()
    // the filter whose choices are listed under the box, its token sitting in the box
    @State private var token: FilterPicker?
    @State private var datePicker: FilterPicker?
    @State private var results: SearchResults?
    @State private var errorMessage: String?
    @State private var isSearching = false
    // the opening channel goes in once, so removing its chip sticks
    @State private var hasAppliedChannel = false
    @State private var homes = SearchHomeCache()
    @FocusState private var isFieldFocused: Bool

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

        return session.members
            .filter { $0.id != session.ownUserId && $0.name.localizedCaseInsensitiveContains(trimmedQuery) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .prefix(8)
            .map { $0 }
    }

    // discord names the channel being searched, or the server when it is all of it
    private var prompt: String {
        guard token == nil else {
            return ""
        }

        guard let channel = filters.channel else {
            return "Search in \(session.displayName)"
        }

        return "Search in \(FilterChips.place(channel, in: session))"
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
        guard hasAppliedChannel else {
            return channelId.flatMap { session.channel($0) }
        }

        return filters.channel
    }

    private var searchKey: [AnyHashable] {
        [trimmedQuery, filters]
    }

    var body: some View {
        Group {
            if let token {
                FilterSuggestions(
                    picker: token,
                    text: query,
                    onPickUser: pick,
                    onPickChannel: pick,
                    onPickHas: pick
                )
            } else if isBrowsing {
                SearchHome(model: homes.model(for: browsingScope), onOpenChannel: openChannel, onOpenUser: openDirectMessage(with:))
            } else {
                resultsList
            }
        }
        .background(Theme.deepBackground)
        // the search box sits in the navigation bar between its back button and the filters,
        // the bar staying keeps the swipe back
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.deepBackground, for: .navigationBar)
        .toolbarBackgroundVisibility(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                searchBox
            }

            ToolbarItem(placement: .topBarTrailing) {
                FilterMenu(isFiltering: !filters.isEmpty, onChoose: choose)
            }
        }
        .sheet(item: $datePicker) { picker in
            DateFilterSheet(picker: picker) { date in
                apply(date, for: picker)
            }
        }
        .task(id: searchKey) {
            await search()
        }
        .onAppear {
            if !hasAppliedChannel, let channelId, let channel = session.channel(channelId) {
                filters.channel = channel
            }

            hasAppliedChannel = true

            isFieldFocused = true
        }
    }

    // discord's search box, with the filter being picked sitting in it as a token
    private var searchBox: some View {
        HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.muted)

                if let token {
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

                TextField("", text: $query, prompt: Text(prompt).foregroundStyle(Theme.muted))
                    .focused($isFieldFocused)
                    .foregroundStyle(Theme.header)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
            }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .frame(maxWidth: .infinity)
        .background(Theme.listBackground, in: .rect(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isFieldFocused ? Theme.blurple : Theme.divider, lineWidth: 1)
        }
    }

    private var resultsList: some View {
        List {
            if !filters.isEmpty {
                FilterChips(filters: $filters)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(Theme.red)
                    .listRowBackground(Theme.listBackground)
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
                        MessageResultRow(message: message, onOpen: { openChannel(message.channelId) })
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
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
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

        token = picker
        query = ""
        isFieldFocused = true
    }

    private func clearToken() {
        token = nil
        query = ""
    }

    private func pick(_ user: PublicUser) {
        if token == .from {
            filters.from = user
        } else {
            filters.mentions = user
        }

        clearToken()
    }

    private func pick(_ channel: Channel) {
        filters.channel = channel
        clearToken()
    }

    private func pick(_ kind: SearchFilters.Has) {
        filters.has = kind
        clearToken()
    }

    // sent on a day replaces a range, and a range replaces sent on, they would contradict
    private func apply(_ date: Date, for picker: FilterPicker) {
        switch picker {
        case .on:
            filters.on = date
            filters.before = nil
            filters.after = nil
        case .before:
            filters.before = date
            filters.on = nil
        case .after:
            filters.after = date
            filters.on = nil
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
            errorMessage = "Searches can be at most \(Self.queryLength.upperBound) characters."
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

        guard !Task.isCancelled, let client = session.client else {
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
                results = found
            }
        } catch {
            if !Task.isCancelled {
                results = nil
                errorMessage = error.localizedDescription
            }
        }
    }

    private func openChannel(_ channelId: Int) {
        servers.open(channelId: channelId, in: session)
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
        }
        .listRowBackground(Theme.listBackground)
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
            return "#\(message.channelName)"
        }

        return "@\(session.directMessagePartner(for: message.channelId)?.name ?? "Direct Message")"
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 12) {
                AvatarView(user: author, size: 32)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(author?.name ?? "Unknown")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(hex: session.roleColor(for: author) ?? "#F2F3F5"))

                        Text(place)
                            .font(.caption)
                            .foregroundStyle(Theme.muted)

                        Spacer(minLength: 0)

                        Text(MessageDate.timestamp(message.createdDate))
                            .font(.caption2)
                            .foregroundStyle(Theme.muted)
                    }
                    .lineLimit(1)

                    Text(message.plainContent)
                        .font(.subheadline)
                        .foregroundStyle(Theme.text)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
            }
        }
        .listRowBackground(Theme.listBackground)
    }
}

private struct FileResultRow: View {
    let file: SearchFile
    let onOpen: () -> Void

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

                    Text("#\(file.channelName)")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .listRowBackground(Theme.listBackground)
    }
}
