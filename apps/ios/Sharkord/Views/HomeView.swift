import AVFoundation
import GameController
import SwiftUI

// discord's layout: the server rail on the left, the picked server's channels or the direct
// messages next to it, the user bar along the bottom
struct HomeView: View {
    static let coordinateSpace = "home"

    let session: SessionStore

    @Environment(ServerListStore.self) private var servers

    @State private var path = NavigationPath()

    // the ipad's: the list and the chat side by side as two cards, in either orientation. a
    // phone, or a narrow ipad window, pushes the chat over the list
    @State private var isSplit = false
    @State private var hasHardwareKeyboard = GCKeyboard.coalesced != nil
    @State private var bottomSafeArea: CGFloat = 0
    @State private var width: CGFloat = 0
    // the chat opens beside the list, and its handle slides it over the list to the full width
    // and back
    @State private var isPortrait = false
    @State private var isChatExpanded = false
    // the handle's drag in progress, the card following the finger until it is let go
    @State private var chatSlide = ChatSlide()
    @State private var detailChannelId: Int?
    // the conversation beside the list when messages were last picked in the rail
    @State private var lastDirectMessageId: Int?
    // the chat the side pane filled in by itself, which a rotation to portrait does not push,
    // since in portrait only the list was ever on screen
    @State private var placeholderChannelId: Int?
    @State private var searchRoute: SearchRoute?
    // the ipad's search cover following a swipe in from the left edge, as a pushed screen would
    @State private var searchSwipe: CGFloat = 0
    #if os(macOS)
    // where the call zooms out of and back into, see MacCallZoom
    @State private var voiceBarFrame = CGRect.zero
    #endif

    // narrower in portrait, where the chat beside it has less room to read in
    private var panelWidth: CGFloat {
        isPortrait ? 280 : 320
    }

    // the rail's and the panel's, which the user bar under them would otherwise widen
    private var listWidth: CGFloat {
        ServerRail.width + panelWidth
    }
    private static let cardRadius: CGFloat = 22
    private static let cardGap: CGFloat = 8

    // an ipad's alone: a phone in landscape can be wide enough to split, and keeps its own
    private var usesDesktopLayout: Bool {
        Platform.isMac || (isSplit && Platform.isPad)
    }

    private static func isSplit(_ size: CGSize) -> Bool {
        #if DEBUG
        if DebugLaunch.forcesSplit {
            return true
        }
        #endif

        // an ipad mini in portrait leaves the chat about a phone's width beside the list
        return size.width >= 600
    }

    var body: some View {
        Group {
            if isSplit {
                splitLayout
            } else {
                stackedLayout
            }
        }
        .environment(\.usesDesktopLayout, usesDesktopLayout)
        .environment(\.usesDesktopSearch, Platform.isMac || (usesDesktopLayout && (isPortrait || hasHardwareKeyboard)))
        .onReceive(NotificationCenter.default.publisher(for: .GCKeyboardDidConnect)) { _ in
            hasHardwareKeyboard = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .GCKeyboardDidDisconnect)) { _ in
            hasHardwareKeyboard = GCKeyboard.coalesced != nil
        }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureDevice.wasDisconnectedNotification), perform: cameraDisconnected)
        #endif
        .onGeometryChange(for: Bool.self, of: { Self.isSplit($0.size) }, action: setSplit)
        .onGeometryChange(for: Bool.self, of: { $0.size.height > $0.size.width }) { portrait in
            isPortrait = portrait
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.safeAreaInsets.bottom }) { inset in
            bottomSafeArea = inset
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { newWidth in
            width = newWidth
        }
        .environment(session)
        .coordinateSpace(.named(Self.coordinateSpace))
        .overlay {
            if let menu = servers.railMenu {
                ServerRailMenu(menu: menu)
                    .environment(session)
            }
        }
        .animation(.snappy(duration: 0.2), value: servers.railMenu?.server.id)
        .overlay {
            if let dropdown = servers.searchDropdown {
                SearchDropdownCard(dropdown: dropdown)
                    .environment(session)
            }
        }
        .overlay(alignment: .top) {
            if let toastMessage = session.toastMessage {
                ErrorToast(message: toastMessage)
                    .slideTransition(from: .top)
            }
        }
        .animation(.snappy, value: session.toastMessage)
        #if os(macOS)
        .overlay {
            if servers.isCallPresented, let voiceSession = servers.voiceSession {
                MacCallZoom(source: voiceBarFrame, isPresented: isCallPresented) {
                    VoiceRoomScreen()
                        .environment(voiceSession)
                        .environment(servers)
                        .phoneControlStyle()
                        .phoneButtons()
                }
            }
        }
        #endif
        .onChange(of: ObjectIdentifier(session)) {
            path = NavigationPath()
            detailChannelId = nil

            if isSplit {
                showDefaultChannel()
            }
        }
        // handed over by hand: on a mac a sheet's background is worked out before it inherits
        // anything, so a sheet reading a store it was not given crashed on opening
        .sheet(isPresented: needsServerPassword) {
            ServerPasswordView()
                .environment(session)
                .interactiveDismissDisabled()
                .environment(servers)
                .appSheet()
        }
        .sheet(item: pendingApproval) { approval in
            ApproveDeviceSheet(token: approval.token)
                .environment(session)
                .environment(servers)
                .appSheet()
        }
        .sheet(isPresented: isShowingDevices) {
            NavigationStack {
                DevicesScreen()
                    .toolbar {
                        ActionToolbarItem(placement: .confirmationAction) {
                            Button("Done", action: closeDevices)
                        }
                    }
            }
            .environment(session)
            .presentationBackground(Theme.deepBackground)
            .environment(servers)
            .appSheet()
        }
    }

    // another device's code opened here, for the server it came from
    private var pendingApproval: Binding<ServerListStore.LoginApproval?> {
        Binding(
            get: {
                guard let approval = servers.pendingApproval, servers.session(approving: approval) === session else {
                    return nil
                }

                return approval
            },
            set: { approval in
                if approval == nil {
                    servers.pendingApproval = nil
                }
            }
        )
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
            .phoneButtons()
            .background(Theme.railBackground.ignoresSafeArea())
            .navigationBarHidden()
            .chatDestinations()
            .opensRequestedChannel($path)
        }
    }

    private var splitLayout: some View {
        // sized from the space offered rather than from what it holds: measured on the stack
        // itself, a card a little too wide widened the stack, which widened the card, until it
        // ran off the screen and stayed there
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    ServerRail(onSelectServer: selectServer, onSelectDirectMessages: showDirectMessages)

                    styledPanel
                        .frame(width: panelWidth)
                        .frame(maxHeight: .infinity)
                        .padding(.top, Self.cardGap)
                }
                .frame(width: listWidth)
                .phoneButtons()
                .overlay {
                    if servers.isChatDropdownOpen && !Platform.isMac {
                        Color.clear
                            .contentShape(.rect)
                            .onTapGesture(perform: dismissChatDropdown)
                    }
                }
                // a mac click in the list puts the panel away and still picks what it landed on,
                // where the ipad's catcher above would take the click for itself
                .simultaneousGesture(
                    TapGesture().onEnded(dismissChatDropdown),
                    isEnabled: servers.isChatDropdownOpen && Platform.isMac
                )
                .background(Theme.railBackground.ignoresSafeArea())

                // a card of its own beside the list's, rounded all round with the rail showing
                // between them, rather than a hard line down the screen. slid over the list it
                // keeps its rounding and its gap from the screen's edges
                SlidingCard(
                    slide: chatSlide,
                    resting: isChatExpanded ? 0 : listWidth,
                    farthest: listWidth,
                    fullWidth: proxy.size.width
                ) {
                    NavigationStack(path: $path) {
                        detail
                            .chatDestinations()
                    }
                    // the message bar clear of the card's rounded bottom and level with the user
                    // bar beside it, which is lifted the same way. a safe area rather than
                    // padding, so a pushed page's own background still reaches the card's edge
                    .safeAreaPadding(.bottom, 16)
                    .background(Theme.chatBackground)
                    // a swipe in from the card's edge goes back. the system's own loses it to a
                    // screen that pages sideways, channel info's tabs among them
                    .overlay(alignment: .leading) {
                        if !path.isEmpty {
                            Color.clear
                                .frame(width: 22)
                                .contentShape(.rect)
                                .gesture(edgeSwipeBack)
                                // clear of the back button in the top bar, as search's strip is
                                .padding(.top, 64)
                        }
                    }
                    .environment(\.showChannelList, isChatExpanded ? collapseChat : nil)
                    // a mac's keyboard is a real one and wants no room, the list stays beside the chat
                    .environment(\.expandChat, isChatExpanded || Platform.isMac ? nil : expandForTyping)
                    .clipShape(.rect(cornerRadius: Self.cardRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous)
                            .stroke(Theme.panelEdge, lineWidth: 1)
                    }
                    .padding(Self.cardGap)
                    .ignoresSafeArea(.container, edges: .bottom)
                    .overlay(alignment: .leading) {
                        if detailChannelId != nil {
                            ChatHandle(onDrag: dragChat, onRelease: releaseChat, onTap: toggleChat)
                                .offset(x: Self.cardGap - ChatHandle.width / 2)
                        }
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
        }
        .background(Theme.railBackground.ignoresSafeArea())
        .opensRequestedChannel($path, detailChannelId: $detailChannelId)
        .environment(\.presentSearch, showSearch)
        .fullScreen(item: $searchRoute) { route in
            NavigationStack {
                SearchScreen(channelId: route.channelId, directMessages: route.directMessages)
                    .toolbar {
                        ToolbarItem(placement: .barLeading) {
                            Button("Close", systemImage: "chevron.left", action: closeSearch)
                        }
                    }
                    .chatDestinations()
            }
            .environment(session)
            .background(Theme.deepBackground.ignoresSafeArea())
            .offset(x: searchSwipe)
            // below the top bar: over it, the strip took a tap on the back button's left half
            .overlay(alignment: .leading) {
                Color.clear
                    .frame(width: 24)
                    .contentShape(.rect)
                    .gesture(searchEdgeSwipe)
                    .padding(.top, 64)
            }
            // see through, so a swipe back shows the screen behind as the search slides off
            .presentationBackground(.clear)
            .environment(servers)
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
        // picking a channel by hand, even the one already showing, makes it the user's own
        .onChange(of: session.requestedChannelId) { _, requested in
            if requested != nil {
                placeholderChannelId = nil
            }
        }
    }

    // only the slide changes as the finger moves, so only the card is redrawn, not the list
    private func dragChat(_ translation: CGFloat) {
        // a pull the way the card cannot go, right while it is beside the list or left while
        // it covers it, leaves it be rather than widening it for nothing
        let isTowardList = isChatExpanded ? translation > 0 : translation < 0

        guard isTowardList else {
            chatSlide.drag = 0
            return
        }

        chatSlide.drag = translation
    }

    // settles on the side it was let go nearer, a flick counting for where it was headed
    private func releaseChat(_ translation: CGFloat, velocity: CGFloat) {
        let resting: CGFloat = isChatExpanded ? 0 : listWidth
        let landing = resting + translation + velocity * 0.2

        settleChat(expanded: landing < listWidth / 2)
    }

    private func dismissChatDropdown() {
        servers.chatDropdownDismissals += 1
    }

    private func expandForTyping() {
        settleChat(expanded: true)
    }

    private var edgeSwipeBack: some Gesture {
        DragGesture(minimumDistance: 10)
            .onEnded { value in
                let distance = value.translation.width + value.velocity.width * 0.15

                if distance > 60 && !path.isEmpty {
                    path.removeLast()
                }
            }
    }

    private func toggleChat() {
        settleChat(expanded: !isChatExpanded)
    }

    private func settleChat(expanded: Bool) {
        // put back beside the list the chat is no longer being typed in
        if !expanded {
            Platform.dismissKeyboard()
        }

        // let go where it started beside the list, there is nothing to animate
        if !expanded && !isChatExpanded && chatSlide.drag == 0 {
            return
        }

        withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.86)) {
            isChatExpanded = expanded
            chatSlide.drag = 0
        }
    }

    private func collapseChat() {
        guard isChatExpanded else {
            return
        }

        settleChat(expanded: false)
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
            .navigationBarHidden()
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
            // under the panel alone, centred in its lighter grey rather than across the rail
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomBars
            }
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

    // the bars end 28 points above the window's bottom, level with the message box and its plus
    // beside them, whatever of that the home indicator's inset already gives. the ipad's inset
    // once covered all of a smaller lift, and the bar hung below the box
    private var barLift: CGFloat {
        guard isSplit else {
            return 0
        }

        return max(Self.cardGap + 20 - bottomSafeArea, 0)
    }

    private var bottomBars: some View {
        VStack(spacing: 6) {
            // a lowered call sits above the user bar on every device, the way a mac always had it
            if let voiceSession = servers.voiceSession {
                VoiceBar()
                    .environment(voiceSession)
                    #if os(macOS)
                    .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { newFrame in
                        voiceBarFrame = newFrame
                    }
                    #endif
            }

            UserBar(isCompact: isSplit)
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .padding(.bottom, barLift)
    }

    private func showSearch(_ route: SearchRoute) {
        searchRoute = route
    }

    private func closeSearch() {
        searchRoute = nil
    }

    // a full screen cover has no swipe back of its own. this one slides the search off to the
    // right under the finger and, past a third of the way or on a flick, lets it go there
    // rather than dropping it downwards as a cover leaves
    private var searchEdgeSwipe: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                searchSwipe = max(value.translation.width, 0)
            }
            .onEnded { value in
                let landing = value.translation.width + value.velocity.width * 0.2

                guard landing > width / 3 else {
                    withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.86)) {
                        searchSwipe = 0
                    }
                    return
                }

                withAnimation(.smooth(duration: 0.22)) {
                    searchSwipe = width
                } completion: {
                    var transaction = Transaction()

                    transaction.disablesAnimations = true

                    withTransaction(transaction) {
                        searchRoute = nil
                    }

                    searchSwipe = 0
                }
            }
    }

    #if os(macOS)
    private func cameraDisconnected(_ notification: Notification) {
        guard let device = notification.object as? AVCaptureDevice, let voiceSession = servers.voiceSession else {
            return
        }

        let uniqueID = device.uniqueID

        Task {
            await voiceSession.cameraDisconnected(uniqueID)
        }
    }
    #endif

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

            if let detailChannelId, detailChannelId != placeholderChannelId, session.channel(detailChannelId) != nil {
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
            placeholderChannelId = detailChannelId
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
            // the newest conversation when none was opened since launch, as discord reopens one
            let lastId = lastDirectMessageId ?? session.directMessages.first?.channelId

            detailChannelId = lastId.flatMap { session.channel($0) }?.id
        } else {
            detailChannelId = session.defaultChannelId
        }

        placeholderChannelId = detailChannelId
    }

    @ViewBuilder
    private var panel: some View {
        if servers.isShowingDirectMessages {
            DirectMessagesPanel(onOpen: openChannel)
        } else {
            switch session.phase {
            case .signedOut:
                SignedOutPanel()
            // the channels from the last visit stand in until the join comes back
            case .connecting where !session.channels.isEmpty:
                ChannelListPanel()
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

    #if os(macOS)
    private var isCallPresented: Binding<Bool> {
        Binding(
            get: { servers.isCallPresented },
            set: { servers.isCallPresented = $0 }
        )
    }
    #endif

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
        placeholderChannelId = nil

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

// the handle's drag, held apart from the home screen's state so a moving finger redraws the
// sliding card alone
@Observable
private final class ChatSlide {
    var drag: CGFloat = 0
}

// the chat card moved by the drag in progress, between beside the list and over it
private struct SlidingCard<Content: View>: View {
    let slide: ChatSlide
    let resting: CGFloat
    let farthest: CGFloat
    let fullWidth: CGFloat
    @ViewBuilder let content: Content

    private var position: CGFloat {
        min(max(resting + slide.drag, 0), farthest)
    }

    var body: some View {
        content
            .modifier(CardPosition(position: position, fullWidth: fullWidth))
    }
}

// the right edge stays on the screen's edge the whole way, narrowing as it moves right. a card
// kept at full width and only moved ran its top bar's buttons off the screen until it settled.
// worked out on every frame of a tap's animation as a drag's are. the frames themselves carry no
// animation inward: under the slide's spring the top bar animated toward each new width on its
// own and trailed behind, running its buttons off the edge until the slide ended. only frames
// that move the card: stripped from everything, the chat's own animations jumped, the button
// down to the newest message among them
private struct CardPosition: ViewModifier, Animatable {
    var position: CGFloat
    let fullWidth: CGFloat

    var animatableData: CGFloat {
        get { position }
        set { position = newValue }
    }

    func body(content: Content) -> some View {
        content
            .transaction(value: position, disableAnimation)
            .frame(width: max(fullWidth - position, 0))
            .offset(x: position)
    }

    private func disableAnimation(_ transaction: inout Transaction) {
        transaction.animation = nil
    }
}

// a grip on the chat card's left edge, dragged to slide the card over the list and back or
// tapped to do it in one go. the drag lives on the grip alone, so it never competes with the
// messages' scrolling or a tap on a picture or a link
private struct ChatHandle: View {
    static let width: CGFloat = 28

    let onDrag: (CGFloat) -> Void
    let onRelease: (CGFloat, CGFloat) -> Void
    let onTap: () -> Void

    @State private var isHovered = false

    // a mac's divider is invisible until the pointer reaches it, as a split view's is
    private var isShown: Bool {
        !Platform.isMac || isHovered
    }

    var body: some View {
        Capsule()
            .fill(Theme.muted)
            .frame(width: 4, height: 34)
            .frame(width: 22, height: 70)
            .background(Color(hex: "#3D3F46"), in: .capsule)
            .shadow(color: .black.opacity(0.45), radius: 8)
            .opacity(isShown ? 1 : 0)
            .animation(.easeOut(duration: 0.15), value: isShown)
            .frame(width: Self.width, height: 96)
            .contentShape(.rect)
            .onHover(perform: setHovered)
            .resizePointer()
            .gesture(drag)
            .accessibilityElement()
            .accessibilityLabel("Resize chat")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onTap() }
    }

    private func setHovered(_ hovered: Bool) {
        isHovered = hovered
    }

    // measured on the screen, the grip moving under the finger along with the card
    private var drag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                onDrag(value.translation.width)
            }
            .onEnded { value in
                if abs(value.translation.width) < 4 && abs(value.translation.height) < 4 {
                    onTap()
                } else {
                    onRelease(value.translation.width, value.velocity.width)
                }
            }
    }
}
