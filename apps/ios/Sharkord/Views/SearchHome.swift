import AVFoundation
import SwiftUI

// discord's search before anything is typed: tabs for what the server, or the channel it was
// opened from, holds. each tab loads the first time it shows and keeps what it got
enum SearchTab: String, Identifiable {
    case recent
    case members
    case channels
    case media
    case pins
    case links
    case files

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }

    // pins belong to one channel, the channel list only makes sense for the whole server
    static func tabs(inChannel: Bool) -> [SearchTab] {
        if inChannel {
            return [.recent, .members, .media, .pins, .links, .files]
        }

        return [.recent, .members, .channels, .media, .links, .files]
    }
}

@MainActor
@Observable
final class SearchHomeModel {
    let scope: Channel?

    var tab: SearchTab = .recent
    // nil until loaded
    private(set) var media: [MediaItem]?
    private(set) var files: [SearchFile]?
    private(set) var links: [SearchMessage]?
    private(set) var pins: [Message]?
    private(set) var memberIds: Set<Int>?
    private(set) var activity: [Int: Date]?
    private(set) var errorMessage: String?

    private var loading: Set<SearchTab> = []

    init(scope: Channel?) {
        self.scope = scope
    }

    func load(_ tab: SearchTab, session: SessionStore) async {
        guard !loading.contains(tab), let client = session.client else {
            return
        }

        loading.insert(tab)

        defer {
            loading.remove(tab)
        }

        do {
            switch tab {
            case .recent:
                // only the "active" times hang on it, a server without the route still shows the rest
                if scope == nil, activity == nil {
                    activity = (try? await Self.fetchActivity(client)) ?? [:]
                }

                if media == nil {
                    media = try await mediaItems(client)
                }
            case .members:
                if let scope, memberIds == nil {
                    let ids: [Int] = try await client.query("channels.getMembers", input: ["channelId": scope.id])

                    memberIds = Set(ids)
                }
            case .channels:
                if activity == nil {
                    activity = try await Self.fetchActivity(client)
                }
            case .media:
                if media == nil {
                    media = try await mediaItems(client)
                }
            case .pins:
                if let scope, pins == nil {
                    pins = try await client.query("messages.getPinned", input: ["channelId": scope.id])
                }
            case .links:
                if links == nil {
                    links = try await search(client, has: .link).messages
                }
            case .files:
                if files == nil {
                    // pictures and videos have their own tab
                    files = try await search(client, has: .file).files.filter { !$0.file.isImage && !$0.file.isVideo }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func fetchActivity(_ client: TRPCClient) async throws -> [Int: Date] {
        let rows: [ChannelActivity] = try await client.query("channels.getActivity")

        return Dictionary(
            rows.map { ($0.channelId, Date(timeIntervalSince1970: TimeInterval($0.lastMessageAt) / 1000)) },
            uniquingKeysWith: max
        )
    }

    private func search(_ client: TRPCClient, has: SearchFilters.Has) async throws -> SearchResults {
        var filters = SearchFilters()

        filters.channel = scope
        filters.has = has

        return try await client.query("messages.search", input: SearchInput(query: nil, filters: filters))
    }

    // pictures and videos together, newest first
    // pictures, videos and the gifs shown from links, newest first
    private func mediaItems(_ client: TRPCClient) async throws -> [MediaItem] {
        async let images = search(client, has: .image)
        async let videos = search(client, has: .video)

        let (imageResults, videoResults) = try await (images, videos)
        let files = (imageResults.files + videoResults.files).map(MediaItem.file)
        let links = imageResults.messages.flatMap { message in
            (message.metadata ?? [])
                .filter(\.isImage)
                .compactMap { media in
                    URL(string: media.url).map { MediaItem.link(url: $0, messageId: message.id, channelId: message.channelId, createdAt: message.createdAt) }
                }
        }

        return (files + links).sorted { $0.createdAt > $1.createdAt }
    }
}

// the models outlive the landing page, so typing a search and clearing it does not load again
final class SearchHomeCache {
    private var models: [Int: SearchHomeModel] = [:]

    @MainActor
    func model(for scope: Channel?) -> SearchHomeModel {
        let key = scope?.id ?? 0

        if let model = models[key] {
            return model
        }

        let model = SearchHomeModel(scope: scope)

        models[key] = model

        return model
    }
}

struct SearchHome: View {
    let model: SearchHomeModel
    let onOpenChannel: (Int) -> Void
    // a channel opened at one of its messages
    let onOpenMessage: (_ channelId: Int, _ messageId: Int) -> Void
    let onOpenUser: (PublicUser) -> Void
    // the channel screen shows its own set, without recent
    var only: [SearchTab]?
    // the channel screen's members tab starts with an invite row
    var onInvite: (() -> Void)?

    private var tabs: [SearchTab] {
        only ?? SearchTab.tabs(inChannel: model.scope != nil)
    }

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            SearchTabBar(tabs: tabs, selection: $model.tab)

            TabView(selection: $model.tab) {
                ForEach(tabs) { tab in
                    SearchTabPage(model: model, tab: tab, onOpenChannel: onOpenChannel, onOpenMessage: onOpenMessage, onOpenUser: onOpenUser, onInvite: onInvite)
                        .tag(tab)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
    }
}

private struct SearchTabBar: View {
    let tabs: [SearchTab]
    @Binding var selection: SearchTab

    @Namespace private var underline

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 28) {
                    ForEach(tabs) { tab in
                        Button {
                            select(tab)
                        } label: {
                            VStack(spacing: 10) {
                                Text(tab.title)
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundStyle(selection == tab ? Theme.blurple : Theme.muted)

                                ZStack {
                                    Capsule()
                                        .fill(.clear)

                                    if selection == tab {
                                        Capsule()
                                            .fill(Theme.blurple)
                                            .matchedGeometryEffect(id: "underline", in: underline)
                                    }
                                }
                                .frame(height: 3)
                            }
                            .fixedSize()
                        }
                        .buttonStyle(.plain)
                        .id(tab)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
            }
            .scrollIndicators(.hidden)
            .onChange(of: selection) { _, tab in
                withAnimation(.smooth(duration: 0.3)) {
                    proxy.scrollTo(tab, anchor: .center)
                }
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.divider)
                .frame(height: 1)
        }
    }

    private func select(_ tab: SearchTab) {
        withAnimation(.smooth(duration: 0.3)) {
            selection = tab
        }
    }
}

private struct SearchTabPage: View {
    let model: SearchHomeModel
    let tab: SearchTab
    let onOpenChannel: (Int) -> Void
    let onOpenMessage: (_ channelId: Int, _ messageId: Int) -> Void
    let onOpenUser: (PublicUser) -> Void
    let onInvite: (() -> Void)?

    @Environment(SessionStore.self) private var session

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                content
            }
            // full width, or the rows hug the middle when every one is narrow
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
        }
        .scrollDismissesKeyboard(.interactively)
        .task {
            await model.load(tab, session: session)
        }
    }

    private func jump(to item: MediaItem) {
        onOpenMessage(item.channelId, item.messageId)
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .recent:
            RecentPage(model: model, onOpenChannel: onOpenChannel, onJump: jump)
        case .members:
            MembersPage(model: model, onOpenUser: onOpenUser, onInvite: onInvite)
        case .channels:
            ChannelsPage(model: model, onOpenChannel: onOpenChannel)
        case .media:
            if let media = model.media {
                if media.isEmpty {
                    EmptyTab(title: "No media yet", systemImage: "photo.on.rectangle")
                } else {
                    MediaGrid(items: media, onJump: jump)
                }
            } else {
                LoadingTab(errorMessage: model.errorMessage)
            }
        case .pins:
            if let pins = model.pins {
                if pins.isEmpty {
                    EmptyTab(title: "No pinned messages", systemImage: "pin")
                } else {
                    ForEach(pins) { message in
                        PinnedMessageRow(message: message, onOpen: { onOpenMessage(message.channelId, message.id) })
                    }
                }
            } else {
                LoadingTab(errorMessage: model.errorMessage)
            }
        case .links:
            if let links = model.links {
                LinksPage(messages: links, onOpenMessage: onOpenMessage)
            } else {
                LoadingTab(errorMessage: model.errorMessage)
            }
        case .files:
            if let files = model.files {
                if files.isEmpty {
                    EmptyTab(title: "No files yet", systemImage: "doc")
                } else {
                    ForEach(files) { file in
                        FileRow(file: file, onJump: { onOpenMessage(file.channelId, file.messageId) })
                    }
                }
            } else {
                LoadingTab(errorMessage: model.errorMessage)
            }
        }
    }
}

// discord's "active 58m ago"
enum ChannelActivityText {
    static func text(_ date: Date) -> String {
        let seconds = max(0, Date.now.timeIntervalSince(date))
        let minutes = Int(seconds / 60)
        let hours = minutes / 60
        let days = hours / 24

        if minutes < 1 {
            return "Active just now"
        }

        if hours < 1 {
            return "Active \(minutes)m ago"
        }

        if days < 1 {
            return "Active \(hours)h ago"
        }

        if days < 30 {
            return "Active \(days)d ago"
        }

        return "Active \(date.formatted(.dateTime.month(.abbreviated).day()))"
    }
}

private struct SectionTitle: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.muted)

            Spacer()

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.link)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }
}

private struct RecentPage: View {
    let model: SearchHomeModel
    let onOpenChannel: (Int) -> Void
    let onJump: (MediaItem) -> Void

    @Environment(SessionStore.self) private var session

    // the three server channels with the latest messages
    private var suggested: [(Channel, Date)] {
        guard model.scope == nil, let activity = model.activity else {
            return []
        }

        return session.channelSections
            .flatMap(\.channels)
            .filter { $0.type == .text }
            .compactMap { channel in activity[channel.id].map { (channel, $0) } }
            .sorted { $0.1 > $1.1 }
            .prefix(3)
            .map { $0 }
    }

    var body: some View {
        if !suggested.isEmpty {
            SectionTitle(title: "Suggested")

            ForEach(suggested, id: \.0.id) { channel, date in
                ChannelRow(channel: channel, activity: date, onOpen: { onOpenChannel(channel.id) })
            }
        }

        if let media = model.media {
            if !media.isEmpty {
                SectionTitle(title: "Photos & Media", actionTitle: "View all", action: showMedia)

                MediaGrid(items: media, limit: 6, onJump: onJump)
            } else if suggested.isEmpty {
                EmptyTab(title: "Nothing here yet", systemImage: "magnifyingglass")
            }
        } else {
            LoadingTab(errorMessage: model.errorMessage)
        }
    }

    private func showMedia() {
        withAnimation(.smooth(duration: 0.3)) {
            model.tab = .media
        }
    }
}

private struct ChannelRow: View {
    let channel: Channel
    let activity: Date?
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 18) {
                Image(systemName: "number")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 3) {
                    Text(channel.name)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Theme.header)
                        .lineLimit(1)

                    if let activity {
                        Text(ChannelActivityText.text(activity))
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.muted)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

private struct ChannelsPage: View {
    let model: SearchHomeModel
    let onOpenChannel: (Int) -> Void

    @Environment(SessionStore.self) private var session

    var body: some View {
        let channels = session.channelSections
            .flatMap(\.channels)
            .filter { $0.type == .text }

        if channels.isEmpty {
            EmptyTab(title: "No channels", systemImage: "number")
        } else {
            ForEach(channels) { channel in
                ChannelRow(channel: channel, activity: model.activity?[channel.id], onOpen: { onOpenChannel(channel.id) })
            }
        }
    }
}

private struct MembersPage: View {
    let model: SearchHomeModel
    let onOpenUser: (PublicUser) -> Void
    let onInvite: (() -> Void)?

    @Environment(SessionStore.self) private var session

    // in a channel only the people who can see it, online first like the member list
    private var members: [PublicUser]? {
        var members = session.members

        if model.scope != nil {
            guard let memberIds = model.memberIds else {
                return nil
            }

            members = members.filter { memberIds.contains($0.id) }
        }

        return members.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        if let onInvite {
            ActionGroup {
                ActionRow(title: "Invite Members", systemImage: "person.badge.plus", action: onInvite)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }

        if let members {
            let online = members.filter { $0.status != nil && $0.status != .offline }
            let offline = members.filter { $0.status == nil || $0.status == .offline }

            if !online.isEmpty {
                SectionTitle(title: "Online · \(online.count)")

                ForEach(online) { user in
                    MemberRow(user: user, onOpen: { onOpenUser(user) })
                }
            }

            if !offline.isEmpty {
                SectionTitle(title: "Offline · \(offline.count)")

                ForEach(offline) { user in
                    MemberRow(user: user, onOpen: { onOpenUser(user) })
                }
            }
        } else {
            LoadingTab(errorMessage: model.errorMessage)
        }
    }
}

private struct MemberRow: View {
    let user: PublicUser
    let onOpen: () -> Void

    @Environment(SessionStore.self) private var session

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 14) {
                AvatarView(user: user, size: 40, showsStatus: true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(user.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color(hex: session.roleColor(for: user) ?? "#F2F3F5"))
                        .lineLimit(1)

                    if let customStatus = user.customStatus, !customStatus.isEmpty {
                        Text(customStatus)
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 7)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

// three across, each opening the media viewer over all of them
private struct MediaGrid: View {
    let items: [MediaItem]
    // how many of them show, the recent page shows a few
    var limit: Int?
    let onJump: (MediaItem) -> Void

    @State private var viewing: MediaItem?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)

    private var shown: [MediaItem] {
        limit.map { Array(items.prefix($0)) } ?? items
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(shown) { item in
                Button {
                    open(item)
                } label: {
                    MediaTile(item: item)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .fullScreenCover(item: $viewing) { item in
            MediaViewer(items: items, startingAt: item, onJump: onJump)
        }
    }

    private func open(_ item: MediaItem) {
        viewing = item
    }
}

private struct MediaTile: View {
    let item: MediaItem

    @Environment(SessionStore.self) private var session

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                switch item {
                case .file(let file):
                    if let address = session.address {
                        if file.file.isVideo {
                            VideoThumbnail(url: address.fileURL(file.file))
                        } else {
                            CachedFileImage(file: file.file, url: address.fileURL(file.file)) {
                                Theme.listBackground
                            }
                        }
                    }
                case .link(let url, _, _, _):
                    AnimatedImage(url: url, maxPointSize: 160)
                }
            }
            .background(Theme.listBackground)
            .clipShape(.rect(cornerRadius: 6))
            .contentShape(.rect)
    }
}

// a still from the start of a video, with a play mark over it
private struct VideoThumbnail: View {
    let url: URL

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Theme.listBackground

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }

            Image(systemName: "play.fill")
                .font(.title2)
                .foregroundStyle(.white)
                .shadow(radius: 4)
        }
        .task(id: url) {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))

            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 400, height: 400)

            if let (still, _) = try? await generator.image(at: .zero) {
                image = UIImage(cgImage: still)
            }
        }
    }
}

struct PinnedMessageRow: View {
    let message: Message
    let onOpen: () -> Void

    @Environment(SessionStore.self) private var session

    private var author: PublicUser? {
        message.userId.flatMap { session.usersById[$0] }
    }

    private var text: String {
        HTMLText.plainText(from: message.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 12) {
                AvatarView(user: author, size: 40)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(author?.name ?? "Unknown")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color(hex: session.roleColor(for: author) ?? "#F2F3F5"))

                        Text(MessageDate.timestamp(message.createdDate))
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    }
                    .lineLimit(1)

                    if !text.isEmpty && !message.isMediaLinkOnly {
                        Text(text)
                            .font(.subheadline)
                            .foregroundStyle(Theme.text)
                            .lineLimit(4)
                            .multilineTextAlignment(.leading)
                    }

                    if let sticker = message.sticker {
                        AnimatedImage(url: session.address?.fileURL(sticker.file), maxPointSize: 120, contentMode: .scaleAspectFit)
                            .frame(width: 120, height: 120)
                            .accessibilityLabel(sticker.name)
                    }

                    ForEach(message.mediaImages, id: \.url) { media in
                        AnimatedImage(url: URL(string: media.url), maxPointSize: 240, contentMode: .scaleAspectFit, sizesToImage: true)
                            .frame(maxWidth: 220, maxHeight: 240, alignment: .leading)
                            .clipShape(.rect(cornerRadius: 8))
                    }

                    ForEach(message.files) { file in
                        AttachmentView(file: file)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

private struct LinksPage: View {
    let messages: [SearchMessage]
    let onOpenMessage: (_ channelId: Int, _ messageId: Int) -> Void

    private struct Entry: Identifiable {
        let message: SearchMessage
        let url: URL
        let preview: MessageMetadata?

        var id: String { "\(message.id)-\(url.absoluteString)" }
    }

    // the message's links, and a bare domain the server only found and previewed
    private var entries: [Entry] {
        messages.flatMap { message in
            let previews = (message.metadata ?? []).filter { $0.kind == "open_graph" }
            var urls = message.links
            let linked = Set(urls.map(\.absoluteString))

            for preview in previews where !linked.contains(preview.url) {
                if let url = URL(string: preview.url) {
                    urls.append(url)
                }
            }

            return urls.map { url in
                Entry(message: message, url: url, preview: previews.first { $0.url == url.absoluteString })
            }
        }
    }

    var body: some View {
        let entries = entries

        if entries.isEmpty {
            EmptyTab(title: "No links yet", systemImage: "link")
        } else {
            ForEach(entries) { entry in
                LinkRow(url: entry.url, preview: entry.preview, onJump: { onOpenMessage(entry.message.channelId, entry.message.id) })
            }
        }
    }
}

private struct LinkRow: View {
    let url: URL
    let preview: MessageMetadata?
    let onJump: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        Button(action: open) {
            HStack(spacing: 14) {
                thumbnail
                    .frame(width: 48, height: 48)
                    .background(Theme.listBackground)
                    .clipShape(.rect(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text(preview?.title ?? url.host() ?? url.absoluteString)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.header)
                        .lineLimit(1)

                    Text(url.absoluteString)
                        .font(.subheadline)
                        .foregroundStyle(Theme.link)
                        .lineLimit(1)
                }

                Spacer(minLength: 44)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            RowMenu(onJump: onJump, link: url)
        }
    }

    // the page's picture once the server has fetched its preview
    @ViewBuilder
    private var thumbnail: some View {
        if let image = preview?.previewImageURL {
            AsyncImage(url: image) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Color.clear
            }
        } else {
            Image(systemName: "link")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.muted)
        }
    }

    private func open() {
        openURL(url)
    }
}

private struct FileRow: View {
    let file: SearchFile
    let onJump: () -> Void

    @Environment(SessionStore.self) private var session

    @State private var thumbnail: UIImage?

    var body: some View {
        OpenFileButton(file: file.file) { isLoading in
            HStack(spacing: 14) {
                icon
                    .frame(width: 48, height: 48)
                    .background(Theme.listBackground)
                    .clipShape(.rect(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text(file.file.originalName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.header)
                        .lineLimit(1)

                    Text("\(file.file.size.formatted(.byteCount(style: .file))) · #\(file.channelName)")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if isLoading {
                    ProgressView()
                }

                Color.clear
                    .frame(width: 30)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .contentShape(.rect)
        }
        .overlay(alignment: .trailing) {
            RowMenu(onJump: onJump, link: nil)
        }
        .task(id: file.id) {
            if let address = session.address {
                thumbnail = await FileThumbnails.thumbnail(for: file.file, from: address.fileURL(file.file))
            }
        }
    }

    // the first page, as in the chat, once quick look has drawn it
    @ViewBuilder
    private var icon: some View {
        if let thumbnail {
            Image(uiImage: thumbnail)
                .resizable()
                .scaledToFill()
        } else {
            Image(systemName: file.file.symbol)
                .font(.system(size: 22))
                .foregroundStyle(Theme.blurple)
        }
    }
}

// a row's own options, over its trailing edge so the row itself still opens what it shows
private struct RowMenu: View {
    let onJump: () -> Void
    let link: URL?

    var body: some View {
        Menu {
            Button("Jump to Message", systemImage: "arrow.uturn.left.circle", action: onJump)

            if let link {
                Button("Copy Link", systemImage: "doc.on.doc") {
                    UIPasteboard.general.url = link
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.muted)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .padding(.trailing, 8)
    }
}

private struct EmptyTab: View {
    let title: String
    let systemImage: String

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage)
            .padding(.top, 60)
            .frame(maxWidth: .infinity)
    }
}

private struct LoadingTab: View {
    let errorMessage: String?

    var body: some View {
        Group {
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(Theme.red)
                    .padding(.horizontal, 18)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}
