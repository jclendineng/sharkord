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

    // a direct message search has people where the server's has members, as discord's
    func title(inDirectMessages: Bool) -> String {
        inDirectMessages && self == .members ? "People" : title
    }

    // the messages panel's search: your conversations, the people in them, and what was shared
    static let directMessageTabs: [SearchTab] = [.recent, .members, .media, .pins, .links, .files]

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
    // every direct message rather than one channel or the server
    let inDirectMessages: Bool

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

    init(scope: Channel?, inDirectMessages: Bool = false) {
        self.scope = scope
        self.inDirectMessages = inDirectMessages
    }

    func load(_ tab: SearchTab, session: SessionStore) async {
        guard !loading.contains(tab), let client = try? await session.readyClient() else {
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
                if scope == nil, !inDirectMessages, activity == nil {
                    activity = (try? await Self.fetchActivity(client)) ?? [:]
                }

                if media == nil {
                    media = try await mediaItems(client, session: session)
                }
            case .members:
                // the people you have conversations with
                if scope == nil, inDirectMessages, memberIds == nil {
                    memberIds = Set(session.directMessages.flatMap { [$0.userId] + ($0.group?.memberIds ?? []) })
                } else if let scope, scope.isDm, memberIds == nil {
                    // the two people, or everyone in a group
                    let others = session.group(for: scope.id)?.memberIds
                        ?? [session.directMessagePartner(for: scope.id)?.id].compactMap { $0 }

                    memberIds = Set(others + [session.ownUserId].compactMap { $0 })
                } else if let scope, memberIds == nil {
                    let ids: [Int] = try await client.query("channels.getMembers", input: ["channelId": scope.id])

                    memberIds = Set(ids)
                }
            case .channels:
                if activity == nil {
                    activity = try await Self.fetchActivity(client)
                }
            case .media:
                if media == nil {
                    media = try await mediaItems(client, session: session)
                }
            case .pins:
                if let scope, pins == nil {
                    pins = try await client.query("messages.getPinned", input: ["channelId": scope.id])
                } else if inDirectMessages, pins == nil {
                    pins = try await directMessagePins(client, channelIds: session.directMessages.map(\.channelId))
                }
            case .links:
                if links == nil {
                    links = try await search(client, session: session, has: .link).messages
                }
            case .files:
                if files == nil {
                    // every file, pictures and videos too, as discord's files tab lists them
                    files = try await search(client, session: session, has: .file).files
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removePin(_ messageId: Int) {
        pins?.removeAll { $0.id == messageId }
    }

    private static func fetchActivity(_ client: TRPCClient) async throws -> [Int: Date] {
        let rows: [ChannelActivity] = try await client.query("channels.getActivity")

        return Dictionary(
            rows.map { ($0.channelId, Date(timeIntervalSince1970: TimeInterval($0.lastMessageAt) / 1000)) },
            uniquingKeysWith: max
        )
    }

    // every conversation's pins, newest first. there are as many as conversations, a few
    private func directMessagePins(_ client: TRPCClient, channelIds: [Int]) async throws -> [Message] {
        var pins: [Message] = []

        for channelId in channelIds {
            let channelPins: [Message] = try await client.query("messages.getPinned", input: ["channelId": channelId])

            pins += channelPins
        }

        return pins.sorted { $0.createdAt > $1.createdAt }
    }

    private func search(_ client: TRPCClient, session: SessionStore, has: SearchFilters.Has) async throws -> SearchResults {
        var filters = SearchFilters()

        filters.channel = scope
        filters.directMessagesOnly = inDirectMessages
        filters.has = has

        let found: SearchResults = try await client.query("messages.search", input: SearchInput(query: nil, filters: filters))

        guard !inDirectMessages, scope?.isDm != true else {
            return found
        }

        // a closed conversation is not in the list at all, so only a channel known to be the
        // server's counts as one
        return found.withoutDirectMessages { session.channel($0)?.isDm == false }
    }

    // pictures and videos together, newest first
    // pictures, videos and the gifs shown from links, newest first
    private func mediaItems(_ client: TRPCClient, session: SessionStore) async throws -> [MediaItem] {
        async let images = search(client, session: session, has: .image)
        async let videos = search(client, session: session, has: .video)

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
    func model(for scope: Channel?, directMessages: Bool = false) -> SearchHomeModel {
        // the whole of the direct messages is its own landing page
        let key = scope?.id ?? (directMessages ? -1 : 0)

        if let model = models[key] {
            return model
        }

        let model = SearchHomeModel(scope: scope, inDirectMessages: directMessages && scope == nil)

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
        if model.inDirectMessages {
            return SearchTab.directMessageTabs
        }

        return only ?? SearchTab.tabs(inChannel: model.scope != nil)
    }

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            SearchTabBar(tabs: tabs, inDirectMessages: model.inDirectMessages, selection: $model.tab)

            TabView(selection: $model.tab) {
                ForEach(tabs) { tab in
                    SearchTabPage(model: model, tab: tab, onOpenChannel: onOpenChannel, onOpenMessage: onOpenMessage, onOpenUser: onOpenUser, onInvite: onInvite)
                        .tag(tab)
                }
            }
            .pagedTabs()
        }
    }
}

private struct SearchTabBar: View {
    let tabs: [SearchTab]
    let inDirectMessages: Bool
    @Binding var selection: SearchTab

    @Namespace private var underline

    // a mac draws its own scroll bar under a horizontal scroll view whatever it is told, so the
    // tabs sit flat when they fit and only scroll when they do not
    private var spacing: CGFloat {
        Platform.isMac ? 22 : 28
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            strip

            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    strip
                }
                .scrollIndicators(.hidden)
                .onChange(of: selection) { _, tab in
                    withAnimation(.smooth(duration: 0.3)) {
                        proxy.scrollTo(tab, anchor: .center)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.divider)
                .frame(height: 1)
        }
    }

    private var strip: some View {
        HStack(spacing: spacing) {
            ForEach(tabs) { tab in
                Button {
                    select(tab)
                } label: {
                    VStack(spacing: 10) {
                        // the fill reaches past the title without moving it, the strip still fits
                        Text(tab.title(inDirectMessages: inDirectMessages))
                            .font(.body.weight(.medium))
                            .foregroundStyle(selection == tab ? Theme.blurple : Theme.muted)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .hoverHighlight()
                            .padding(.horizontal, -8)
                            .padding(.vertical, -4)

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
        .fixedSize()
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
                    SearchCardGrid {
                        ForEach(pins) { message in
                            PinCardTile(
                                message: message,
                                onOpen: { onOpenMessage(message.channelId, message.id) },
                                onUnpinned: { model.removePin(message.id) }
                            )
                        }
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
                    SearchCardGrid {
                        ForEach(files) { file in
                            FileCardTile(file: file, onJump: { onOpenMessage(file.channelId, file.messageId) })
                        }
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
                .font(.body.weight(.medium))
                .foregroundStyle(Theme.muted)

            Spacer()

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.link)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .contentShape(.rect)
                }
                .hoverHighlight()
                    .padding(.horizontal, -6)
                    .padding(.vertical, -2)
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
        guard model.scope == nil, !model.inDirectMessages, let activity = model.activity else {
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
                    .font(.title2.weight(.medium))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 3) {
                    Text(channel.name)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(Theme.header)
                        .lineLimit(1)

                    if let activity {
                        Text(ChannelActivityText.text(activity))
                            .font(.callout)
                            .foregroundStyle(Theme.muted)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .padding(.horizontal, 6)
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
                    MemberRow(user: user, channelId: model.scope?.id, onOpen: { onOpenUser(user) })
                }
            }

            if !offline.isEmpty {
                SectionTitle(title: "Offline · \(offline.count)")

                ForEach(offline) { user in
                    MemberRow(user: user, channelId: model.scope?.id, onOpen: { onOpenUser(user) })
                }
            }
        } else {
            LoadingTab(errorMessage: model.errorMessage)
        }
    }
}

private struct MemberRow: View {
    // what the menu asked for, done once its sheet has gone so the two do not collide
    private enum MenuAction {
        case profile
        case message
    }

    let user: PublicUser
    // the chat a mention from the menu goes into
    let channelId: Int?
    let onOpen: () -> Void

    @Environment(SessionStore.self) private var session
    @Environment(ServerListStore.self) private var servers

    @State private var isMenuPresented = false
    @State private var menuAnchor = UnitPoint.center
    @State private var pendingAction: MenuAction?
    @State private var isProfilePresented = false
    @State private var isHovered = false

    var body: some View {
        content
            .background(isHovered || isMenuPresented ? Theme.hover : .clear, in: .rect(cornerRadius: 6))
            .padding(.horizontal, 6)
            .onHover(perform: setHovered)
            // discord's menu on a member: a long press on a touch screen, a right click on a mac
            .onLongPressGesture(minimumDuration: 0.3, perform: showMenu)
            .onSecondaryClick(perform: showMenuAtPointer)
            .accessibilityAction(named: "More Options", showMenu)
            .actionsPresentation(isPresented: $isMenuPresented, anchor: menuAnchor, onDismiss: runPendingAction) {
                MemberActionsSheet(user: user, channelId: channelId, onShowProfile: requestProfile, onMessage: requestMessage)
                    .environment(session)
                    .environment(servers)
            }
            .sheet(isPresented: $isProfilePresented) {
                MemberProfileSheet(user: user, onMessage: openDirectMessage)
                    .environment(session)
                    .environment(servers)
                    .appSheet(addsClose: true)
            }
    }

    private func setHovered(_ hovered: Bool) {
        isHovered = hovered
    }

    private func showMenu() {
        menuAnchor = .center
        isMenuPresented = true
    }

    private func showMenuAtPointer(_ click: SecondaryClick) {
        menuAnchor = click.anchor
        isMenuPresented = true
    }

    private func requestProfile() {
        pendingAction = .profile
        isMenuPresented = false
    }

    private func requestMessage() {
        pendingAction = .message
        isMenuPresented = false
    }

    private func runPendingAction() {
        let action = pendingAction

        pendingAction = nil

        switch action {
        case .profile:
            isProfilePresented = true
        case .message:
            openDirectMessage()
        case nil:
            break
        }
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

    // plain gestures rather than a button: a recognised long press cancels the tap, where a
    // button still fires when the finger lifts after one
    private var content: some View {
        Group {
            HStack(spacing: 14) {
                AvatarView(user: user, size: 40, showsStatus: true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(user.name)
                        .font(.body.weight(.semibold))
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
        .onTapGesture(perform: onOpen)
        .accessibilityAddTraits(.isButton)
    }
}

// three across, each opening the media viewer over all of them
private struct MediaGrid: View {
    let items: [MediaItem]
    // how many of them show, the recent page shows a few
    var limit: Int?
    let onJump: (MediaItem) -> Void

    @Environment(SessionStore.self) private var session
    @Environment(ServerListStore.self) private var servers
    @Environment(\.openURL) private var openURL

    @State private var viewing: MediaItem?
    // the viewer grows out of the tile and shrinks back into it, as in photos
    @Namespace private var zoom

    @Environment(\.horizontalSizeClass) private var sizeClass

    private var spacing: CGFloat {
        sizeClass == .regular ? 8 : 4
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: spacing), count: 3)
    }

    private var shown: [MediaItem] {
        limit.map { Array(items.prefix($0)) } ?? items
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(shown) { item in
                Button {
                    open(item)
                } label: {
                    MediaTile(item: item)
                        .hoverBrighten(cornerRadius: 6)
                        .matchedTransitionSource(id: item.id, in: zoom)
                }
                .buttonStyle(.plain)
                // the viewer's menu, without opening it first
                .contextMenu {
                    actions(for: item)
                }
            }
        }
        .padding(.horizontal, 14)
        // handed over by hand: on a mac a sheet's background is worked out before it inherits
        // anything, so a sheet reading a store it was not given crashed on opening
        .fullScreen(item: $viewing) { item in
            MediaViewer(items: items, startingAt: item, onJump: onJump)
                #if os(iOS)
                .navigationTransition(.zoom(sourceID: item.id, in: zoom))
                #endif
                .environment(session)
                .environment(servers)
        }
    }

    private func open(_ item: MediaItem) {
        viewing = item
    }

    @ViewBuilder
    private func actions(for item: MediaItem) -> some View {
        if let url = url(for: item) {
            if !item.isVideo {
                Button("Save", systemImage: "square.and.arrow.down") {
                    save(from: url)
                }
            }

            ShareLink(item: url) {
                Label("Share", systemImage: "square.and.arrow.up")
            }

            Button("Open in Browser", systemImage: "arrow.up.forward.square") {
                openURL(url)
            }
        }

        Button("Jump to Message", systemImage: "arrow.uturn.left.circle") {
            onJump(item)
        }
    }

    private func url(for item: MediaItem) -> URL? {
        switch item {
        case .file(let file):
            return session.address?.fileURL(file.file)
        case .link(let url, _, _, _):
            return url
        }
    }

    private func save(from url: URL) {
        Task {
            if await PhotoSaver.save(from: url) {
                Haptics.success()
            } else {
                session.showError(AuthAPI.RequestError(message: "This picture could not be saved to Photos."))
            }
        }
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
struct VideoThumbnail: View {
    let url: URL

    @State private var image: PlatformImage?

    var body: some View {
        ZStack {
            Theme.listBackground

            if let image {
                Image(platformImage: image)
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
                image = PlatformImage(cgImage: still)
            }
        }
    }
}

struct PinnedMessageRow: View {
    let message: Message
    let onOpen: () -> Void
    // the list it is in drops it once it is unpinned
    var onUnpinned: (() -> Void)?

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
                            .font(.callout.weight(.semibold))
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
                        AnimatedImage(url: session.address?.fileURL(sticker.file), maxPointSize: 120, contentMode: .fit)
                            .frame(width: 120, height: 120)
                            .accessibilityLabel(sticker.name)
                    }

                    ForEach(message.mediaImages, id: \.url) { media in
                        AnimatedImage(url: URL(string: media.url), maxPointSize: 240, contentMode: .fit, sizesToImage: true)
                            .frame(maxWidth: 220, maxHeight: 240, alignment: .leading)
                            .clipShape(.rect(cornerRadius: 8))
                    }

                    ForEach(message.linkPreviews, id: \.url) { preview in
                        LinkPreviewCard(preview: preview)
                    }

                    ForEach(message.files) { file in
                        AttachmentView(file: file)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .padding(.horizontal, 6)
        // a long press, as on the files and links cards, a tap still jumps to it
        .contextMenu {
            Button("Jump to Message", systemImage: "arrow.uturn.left.circle", action: onOpen)

            if !text.isEmpty {
                Button("Copy Text", systemImage: "doc.on.doc", action: copyText)
            }

            if session.canPin(in: message.channelId) {
                Button("Unpin Message", systemImage: "pin.slash", role: .destructive, action: unpin)
            }
        }
    }

    private func copyText() {
        Platform.copy(text)
    }

    private func unpin() {
        Task {
            do {
                try await session.perform("messages.togglePin", ["messageId": message.id])
                onUnpinned?()
            } catch {
                session.showError(error)
            }
        }
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
            SearchCardGrid {
                ForEach(entries) { entry in
                    LinkCardTile(
                        url: entry.url,
                        preview: entry.preview,
                        userId: entry.message.userId,
                        channelId: entry.message.channelId,
                        channelName: entry.message.channelName,
                        onJump: { onOpenMessage(entry.message.channelId, entry.message.id) }
                    )
                }
            }
        }
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
