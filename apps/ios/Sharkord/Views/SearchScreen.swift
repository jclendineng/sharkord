import SwiftUI

// members are filtered locally, messages and files come from messages.search
struct SearchScreen: View {
    // the server's bounds for a search query
    private static let queryLength = 2...24

    @Environment(ServerListStore.self) private var servers
    @Environment(SessionStore.self) private var session

    @State private var query = ""
    @State private var results: SearchResults?
    @State private var errorMessage: String?
    @State private var isSearching = false

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
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

    var body: some View {
        List {
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
        .background(Theme.deepBackground)
        .overlay {
            if isSearching {
                ProgressView()
            } else if hasNoResults {
                ContentUnavailableView.search(text: trimmedQuery)
            }
        }
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search \(session.displayName)"
        )
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.deepBackground, for: .navigationBar)
        .toolbarBackgroundVisibility(.visible, for: .navigationBar)
        .task(id: trimmedQuery) {
            await search()
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

        guard Self.queryLength.contains(text.count) else {
            results = nil

            if text.count > Self.queryLength.upperBound {
                errorMessage = "Searches can be at most \(Self.queryLength.upperBound) characters."
            }

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
            let found: SearchResults = try await client.query("messages.search", input: ["query": text])

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
