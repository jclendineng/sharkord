import SwiftUI

// discord's layout: the server rail on the left, the picked server's channels or the direct
// messages next to it, the user bar along the bottom
struct HomeView: View {
    static let coordinateSpace = "home"

    let session: SessionStore

    @Environment(ServerListStore.self) private var servers

    @State private var path = NavigationPath()

    // discord's ipad in landscape: the list and the chat side by side. in portrait, or a narrow
    // window, it is the phone's, the chat pushed over the list
    @State private var isSplit = false
    @State private var detailChannelId: Int?
    // the conversation beside the list when messages were last picked in the rail
    @State private var lastDirectMessageId: Int?
    @State private var searchRoute: SearchRoute?

    private static let panelWidth: CGFloat = 320
    private static let cardRadius: CGFloat = 22
    private static let cardGap: CGFloat = 8

    private static func isSplit(_ size: CGSize) -> Bool {
        #if DEBUG
        if DebugLaunch.forcesSplit {
            return true
        }
        #endif

        return size.width >= 1000 && size.width > size.height
    }

    var body: some View {
        Group {
            if isSplit {
                splitLayout
            } else {
                stackedLayout
            }
        }
        .onGeometryChange(for: Bool.self, of: { Self.isSplit($0.size) }, action: setSplit)
        .environment(session)
        .coordinateSpace(.named(Self.coordinateSpace))
        .overlay {
            if let menu = servers.railMenu {
                ServerRailMenu(menu: menu)
                    .environment(session)
            }
        }
        .animation(.snappy(duration: 0.2), value: servers.railMenu?.server.id)
        .overlay(alignment: .top) {
            if let toastMessage = session.toastMessage {
                ErrorToast(message: toastMessage)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: session.toastMessage)
        .onChange(of: ObjectIdentifier(session)) {
            path = NavigationPath()
            detailChannelId = nil

            if isSplit {
                showDefaultChannel()
            }
        }
        .sheet(isPresented: needsServerPassword) {
            ServerPasswordView()
                .environment(session)
                .interactiveDismissDisabled()
        }
        .sheet(isPresented: isShowingDevices) {
            NavigationStack {
                DevicesScreen()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done", action: closeDevices)
                        }
                    }
            }
            .environment(session)
            .presentationBackground(Theme.deepBackground)
        }
    }

    private var isShowingDevices: Binding<Bool> {
        Binding(
            get: { servers.devicesRequest == ObjectIdentifier(session) },
            set: { isShowing in
                if !isShowing {
                    servers.devicesRequest = nil
                }
            }
        )
    }

    private func closeDevices() {
        servers.devicesRequest = nil
    }

    private var stackedLayout: some View {
        NavigationStack(path: $path) {
            HStack(spacing: 0) {
                ServerRail(onSelectServer: selectServer, onSelectDirectMessages: showDirectMessages)

                styledPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Theme.railBackground.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomBars
            }
            .toolbarVisibility(.hidden, for: .navigationBar)
            .chatDestinations()
            .opensRequestedChannel($path)
        }
    }

    private var splitLayout: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                ServerRail(onSelectServer: selectServer, onSelectDirectMessages: showDirectMessages)

                styledPanel
                    .frame(width: Self.panelWidth)
                    .frame(maxHeight: .infinity)
                    .padding(.top, Self.cardGap)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomBars
            }
            .background(Theme.railBackground.ignoresSafeArea())

            // a card of its own beside the list's, rounded all round with the rail showing
            // between them, rather than a hard line down the screen
            NavigationStack(path: $path) {
                detail
                    .chatDestinations()
            }
            .clipShape(.rect(cornerRadius: Self.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous)
                    .stroke(Theme.panelEdge, lineWidth: 1)
            }
            .padding(Self.cardGap)
            .ignoresSafeArea(.container, edges: .bottom)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.railBackground.ignoresSafeArea())
        .opensRequestedChannel($path, detailChannelId: $detailChannelId)
        .environment(\.presentSearch, showSearch)
        .fullScreenCover(item: $searchRoute) { route in
            NavigationStack {
                SearchScreen(channelId: route.channelId, directMessages: route.directMessages)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Close", systemImage: "chevron.left", action: closeSearch)
                        }
                    }
                    .chatDestinations()
            }
            .environment(session)
        }
        // a result opened from search shows in the chat beside the list, search steps aside
        .onChange(of: session.requestedChannelId) { _, requested in
            if requested != nil {
                searchRoute = nil
            }
        }
        .onAppear(perform: showDefaultChannel)
        // the channels arrive after the screen does, the first of them is opened then
        .onChange(of: session.defaultChannelId) {
            showDefaultChannel()
        }
        .onChange(of: servers.isShowingDirectMessages) {
            matchDetailToPanel()
        }
        .onChange(of: detailChannelId) { _, channelId in
            if let channelId, session.channel(channelId)?.isDm == true {
                lastDirectMessageId = channelId
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let detailChannelId, session.channel(detailChannelId) != nil {
            ChatScreen(channelId: detailChannelId)
                .id(detailChannelId)
        } else {
            ContentUnavailableView(
                "Nothing open",
                systemImage: "bubble.left.and.bubble.right",
                description: Text("Pick a channel or a conversation on the left.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.chatBackground)
            .toolbarVisibility(.hidden, for: .navigationBar)
        }
    }

    // the phone's panel runs off the right and bottom edges. beside the ipad's chat it is a
    // card, rounded all round and stopping short of the bottom like the chat's
    private var styledPanel: some View {
        let radius: CGFloat = isSplit ? Self.cardRadius : 20
        let trailingRadius: CGFloat = isSplit ? radius : 0
        let bottomGap: CGFloat = isSplit ? Self.cardGap : 0

        return panel
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: radius, topTrailingRadius: trailingRadius, style: .continuous))
            .background {
                // runs on under the user bar, so the bottom has no strip of the rail's color
                UnevenRoundedRectangle(
                    topLeadingRadius: radius,
                    bottomLeadingRadius: trailingRadius,
                    bottomTrailingRadius: trailingRadius,
                    topTrailingRadius: trailingRadius,
                    style: .continuous
                )
                .fill(Theme.panelBackground)
                .stroke(Theme.panelEdge, lineWidth: 1)
                .padding(.bottom, bottomGap)
                .ignoresSafeArea(edges: .bottom)
            }
            .id(ObjectIdentifier(session))
    }

    private var bottomBars: some View {
        VStack(spacing: 6) {
            if let voiceSession = servers.voiceSession {
                VoiceBar()
                    .environment(voiceSession)
            }

            UserBar()
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
    }

    private func showSearch(_ route: SearchRoute) {
        searchRoute = route
    }

    private func closeSearch() {
        searchRoute = nil
    }

    private func setSplit(_ split: Bool) {
        guard split != isSplit else {
            return
        }

        // the chat open before the rotation stays open after it, beside the list or pushed
        // over it. with nothing pushed the phone layout was showing only the list
        if split {
            if !path.isEmpty, let shownChannelId = session.shownChannelId {
                detailChannelId = shownChannelId
            }

            path = NavigationPath()
            isSplit = true
            matchDetailToPanel()
        } else {
            path = NavigationPath()

            if let detailChannelId, session.channel(detailChannelId) != nil {
                path.append(ChatRoute(channelId: detailChannelId))
            }

            isSplit = false
        }
    }

    // the chat beside the list starts on the channel last open, as discord's does
    private func showDefaultChannel() {
        guard !servers.isShowingDirectMessages else {
            return
        }

        if detailChannelId == nil || session.channel(detailChannelId ?? -1) == nil {
            detailChannelId = session.defaultChannelId
        }
    }

    // the chat beside the list belongs to what the list shows: a conversation beside the
    // direct messages, a channel beside a server's channels
    private func matchDetailToPanel() {
        guard isSplit else {
            return
        }

        let isShowingDirectMessages = servers.isShowingDirectMessages
        let detailIsDirectMessage = detailChannelId.flatMap { session.channel($0) }?.isDm

        if detailIsDirectMessage == isShowingDirectMessages {
            return
        }

        if isShowingDirectMessages {
            detailChannelId = lastDirectMessageId.flatMap { session.channel($0) }?.id
        } else {
            detailChannelId = session.defaultChannelId
        }
    }

    @ViewBuilder
    private var panel: some View {
        if servers.isShowingDirectMessages {
            DirectMessagesPanel(onOpen: openChannel)
        } else {
            switch session.phase {
            case .signedOut:
                SignedOutPanel()
            case .connecting, .needsServerPassword:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .connected, .reconnecting:
                ChannelListPanel()
            }
        }
    }

    private var needsServerPassword: Binding<Bool> {
        Binding(
            get: { session.phase == .needsServerPassword },
            set: { _ in }
        )
    }

    // a different server opens its default channel straight away, like discord does
    private func selectServer(_ selected: SessionStore) {
        let isSameServer = selected === session

        servers.select(selected)

        if !isSameServer, let channelId = selected.defaultChannelId {
            selected.requestedChannelId = channelId
        }
    }

    private func showDirectMessages() {
        servers.isShowingDirectMessages = true
    }

    private func openChannel(_ channelId: Int) {
        if isSplit {
            detailChannelId = channelId
            path = NavigationPath()
        } else {
            path.append(ChatRoute(channelId: channelId))
        }
    }
}

private struct SignedOutPanel: View {
    @Environment(ServerListStore.self) private var servers
    @Environment(SessionStore.self) private var session

    var body: some View {
        ContentUnavailableView {
            Label("Signed out of \(session.displayName)", systemImage: "person.crop.circle.badge.exclamationmark")
        } description: {
            if let errorMessage = session.errorMessage {
                Text(errorMessage)
            }
        } actions: {
            Button("Log In", action: signIn)
                .buttonStyle(.borderedProminent)
        }
        // a revoked or expired sign in goes straight back to the login screen. cancelling it
        // leaves this panel, with the button to try again
        .onAppear(perform: promptOnce)
    }

    private func promptOnce() {
        guard session.wantsSignInPrompt else {
            return
        }

        session.wantsSignInPrompt = false
        signIn()
    }

    private func signIn() {
        servers.signInAgain(session)
    }
}

struct PanelHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(Theme.header)
                .lineLimit(1)

            trailing

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }
}
