import SwiftUI

struct MessageListView<Header: View>: View {
    let store: ChannelMessagesStore
    // the day of what the header shows, a thread's starter, so the first reply is only dated
    // when it came on another day
    var headerDate: Date? = nil
    @ViewBuilder let header: Header

    @Environment(SessionStore.self) private var session
    @Environment(ServerListStore.self) private var servers
    // the root's, which asks before leaving the app, see LinkGuard
    @Environment(\.openURL) private var openURL

    @State private var actionsMessage: Message?
    // where a right click asks the mac's menu to open, and the list's own place in the window
    // that it is worked out against
    @State private var menuAnchor = UnitPoint.center
    @State private var listFrame = CGRect.zero
    @State private var deletingMessage: Message?
    @State private var menuSheet: MessageMenuSheet?
    @State private var openedThread: Message?
    @Environment(\.openThreadPanel) private var openThreadPanel
    // opened once the actions sheet has finished going, pushed under it the two moved at once
    @State private var threadAfterActions: Message?
    // asked about once the actions sheet has gone, another presentation cannot start before
    @State private var deleteAfterActions: Message?

    // consecutive messages from the same author inside this window share one header
    private static var groupingWindow: Int { 7 * 60 * 1000 }

    // runs of a blocked person's messages opened on asking, by their first message
    @State private var revealedBlockedStretches: Set<Int> = []

    // the message a jump landed on, ringed by a soft glow that pulses twice and fades
    @State private var highlightedMessageId: Int?
    @State private var highlightStrength = 0.0
    // far enough up the conversation for discord's round button back down
    @State private var isAwayFromBottom = false
    // the jump button's way down. a scrollTo through the reader's proxy was dropped when tapped
    // while the list still coasted or settled from a bounce, and stopped short of the padding
    @State private var scrollPosition = ScrollPosition()
    @State private var isPinnedToBottom = true
    // a tap's putting the keyboard away, held back long enough to see whether it is the first
    // half of a double tap
    @State private var keyboardDismissal: Task<Void, Never>?

    // a chat's first frame lays out only its newest messages, the rest once it has slid in.
    // all fifty inside the push made opening a channel hang for over a third of a second. the
    // list holds to the bottom, so the rows coming in above move nothing on screen
    @State private var showsAllMessages = false
    private static var firstFrameMessages: Int { 20 }

    private var firstUnreadId: Int? {
        store.firstUnreadMessage?.id
    }

    // a jump to a message needs its row there from the start
    private var firstShownIndex: Int {
        guard !showsAllMessages, store.focusedMessageId == nil else {
            return 0
        }

        return max(store.messages.count - Self.firstFrameMessages, 0)
    }

    var body: some View {
        ScrollViewReader { proxy in
            messageList
                // a thread asked for opens as soon as the jump lands, rather than after the
                // highlight its first message gets in the chat under it
                .task(id: store.focusedMessageId) {
                    openPendingThread()
                    await scrollToFocused(proxy)
                }
                // the conversation fades into the bar above it and the message box below, both
                // its own color, where it used to be cut off along their edge
                .overlay(alignment: .top) {
                    EdgeFade(edge: .top)
                }
                .overlay(alignment: .bottom) {
                    EdgeFade(edge: .bottom)
                }
                .overlay(alignment: .bottomTrailing) {
                    if isAwayFromBottom, !store.isDetached {
                        JumpToBottomButton(action: scrollToBottom)
                        .padding(12)
                        .popTransition()
                    }
                }
                .animation(Motion.quick, value: isAwayFromBottom)
        }
        .task {
            try? await Task.sleep(for: .milliseconds(450))
            showsAllMessages = true
        }
        .overlay(alignment: .top) {
            if let unreadMarker = store.unreadMarker {
                NewMessagesBar(
                    count: unreadMarker.count,
                    since: store.firstUnreadMessage?.createdDate,
                    onJump: jumpToFirstUnread,
                    onClose: dismissUnreadMarker
                )
                .slideTransition(from: .top)
            }
        }
        .animation(Motion.quick, value: store.unreadMarker)
        // the list is a window around an older message, a way back to the newest
        .overlay(alignment: .bottom) {
            if store.isDetached {
                JumpToPresentBar(action: returnToPresent)
                    .padding(.bottom, 8)
                    .slideTransition(from: .bottom)
            }
        }
        .animation(Motion.quick, value: store.isDetached)
    }

    private var messageList: some View {
        // read once, not once per row: the lookup is a scan of every loaded message, and the
        // list asked for it twice in each of fifty rows
        let unreadId = store.firstUnreadMessage?.id
        let blockedStretches = blockedStretches()

        return ScrollView {
            // every loaded message is laid out, not only the ones on screen: a lazy stack guessed the
            // height of the rest, and with pictures and previews its guesses were hundreds of points
            // out, the list jumping as it corrected them mid scroll. a page is fifty messages
            VStack(alignment: .leading, spacing: 0) {
                if firstShownIndex == 0 {
                    if store.hasOlder {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else if store.hasLoaded {
                        header
                    }
                }

                ForEach(Array(store.messages.enumerated()).dropFirst(firstShownIndex), id: \.element.id) { index, message in
                    if startsNewDay(at: index) {
                        DaySeparator(date: message.createdDate)
                    }

                    if message.id == unreadId {
                        NewMessagesDivider()
                    }

                    let showsHeader = showsHeader(at: index) || message.id == unreadId
                    let blockedStretch = blockedStretches[message.id]

                    let isRevealed = blockedStretch.map { revealedBlockedStretches.contains($0.startId) } ?? false

                    if let blockedStretch, blockedStretch.startId == message.id {
                        BlockedMessagesRow(count: blockedStretch.count, isShown: isRevealed) {
                            toggleBlockedStretch(blockedStretch.startId)
                        }
                    }

                    if blockedStretch == nil || isRevealed {
                        MessageRow(
                            message: message,
                            showsHeader: showsHeader,
                            isFollowedClosely: isFollowedClosely(at: index),
                            showsThreadLink: store.scope == .channel,
                            isShowingActions: actionsMessage?.id == message.id,
                            onLongPress: { showActions(for: message) },
                            onDoubleTap: { react(to: message) },
                            onSecondaryClick: { click in showActions(for: message, at: click) },
                            hoverActions: MessageHoverActions(
                                onReact: { emoji in quickReact(emoji, to: message) },
                                onReply: { reply(to: message) },
                                onMore: { click in showActions(for: message, at: click) }
                            ),
                            isPending: store.isPending(message)
                        )
                        .background {
                            if highlightedMessageId == message.id {
                                JumpHighlight(
                                    strength: highlightStrength,
                                    hasHeader: showsHeader,
                                    isFollowedClosely: isFollowedClosely(at: index)
                                )
                            }
                        }
                    }
                }
            }
            // the full width even with nothing but the welcome in it: an empty channel's list was
            // only as wide as that text, and the chat shrank to it with black down both sides
            .frame(maxWidth: .infinity, alignment: .leading)
            // room for the typing indicator, which sits over the bottom of the list so it coming
            // and going moves nothing, below the newest message rather than over it
            .padding(.bottom, 28)
        }
        .scrollPosition($scrollPosition)
        // the bar starts on the card's straight edge, below its rounded corner, which cut the
        // top of it off
        .contentMargins(.top, 20, for: .scrollIndicators)
        .defaultScrollAnchor(.bottom)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        // a chat opened with its messages already loaded lays them out at the bottom before the
        // screen has its final size. the message bar then takes its room and the scroll view kept
        // the old top, landing 266 points short of the newest message. so the list holds to the
        // bottom until the first touch or a jump to a message
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            guard geometry.contentSize.height > geometry.containerSize.height else {
                return 0
            }

            return geometry.contentSize.height + geometry.contentInsets.bottom - geometry.contentOffset.y - geometry.containerSize.height
        } action: { _, distance in
            if isPinnedToBottom, distance > 1, store.focusedMessageId == nil, !store.isDetached {
                scrollPosition.scrollTo(edge: .bottom)
            }
        }
        .onScrollPhaseChange { _, phase in
            if phase == .interacting {
                isPinnedToBottom = false
            }
        }
        // what you send shows at the bottom, so the list goes there to show it
        .onChange(of: store.pendingIds.last, scrollToSentMessage)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            let distance = geometry.contentSize.height - geometry.contentOffset.y - geometry.containerSize.height

            return distance > 600
        } action: { _, isAway in
            isAwayFromBottom = isAway
        }
        // the next page up, a screen before the top comes into view. with every row laid out the
        // spinner up there appears at once and could not be what asks for it
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top < geometry.containerSize.height
        } action: { _, isNearTop in
            if isNearTop {
                loadOlder()
            }
        }
        .scrollDismissesKeyboard(.interactively)
        // like the keyboard: a swipe down on the conversation drags the attachment panel with
        // it while the conversation scrolls, a tap puts it away. the drag is on only while the
        // panel is open: always on, it took every sideways swipe over the messages, and the
        // system's swipe back never started there
        .simultaneousGesture(attachPanelDrag, isEnabled: store.attachPanel.isOpen)
        .simultaneousGesture(TapGesture().onEnded(closeAttachPanel))
        .background(Theme.chatBackground)
        .overlay {
            if !store.hasLoaded {
                loadingOverlay
            }
        }
        // a long press opens the menu with the finger still down, and lifting it would otherwise
        // also count as a tap on the file or image under it
        .environment(\.isShowingMessageActions, actionsMessage != nil)
        .environment(\.showMessageActions, showActionsFromRow)
        .environment(\.reactToMessage, react)
        // the same for a link in the message, which opens on the finger lifting
        .environment(\.openURL, OpenURLAction(handler: openUnlessShowingActions))
        // handed over by hand: on a mac a sheet's background is worked out before it inherits
        // anything, so a sheet reading a store it was not given crashed on opening
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { frame in
            listFrame = frame
        }
        .actionsPresentation(item: $actionsMessage, anchor: menuAnchor, onDismiss: continueAfterActions) { message in
            MessageActionsSheet(
                message: message,
                store: store,
                canOpenThread: store.scope == .channel,
                onOpenThread: { openThread(message) },
                onDelete: confirmDelete,
                onShowSheet: showMenuSheet
            )
                .environment(session)
                .environment(servers)
        }
        .sheet(item: $menuSheet) { sheet in
            Group {
                switch sheet {
                case .forward(let message):
                    ForwardSheet(message: message)
                case .rulesSetup(let messageId):
                    RulesSetupSheet(messageId: messageId)
                }
            }
            .environment(session)
            .environment(servers)
            .appSheet()
        }
        .fullScreen(item: $deletingMessage) { message in
            DeleteMessageConfirmation(message: message, onConfirm: { delete(message) })
                .presentationBackground(.clear)
                .environment(session)
                .environment(servers)
        }
        .transaction(value: deletingMessage) { transaction in
            // the card fades in over the chat on its own, without the cover sliding up
            transaction.disablesAnimations = true
        }
        .navigationDestination(item: $openedThread) { parent in
            ThreadScreen(parent: parent)
        }
    }

    @ViewBuilder
    private var loadingOverlay: some View {
        if let errorMessage = store.errorMessage {
            ContentUnavailableView("Couldn't load messages", systemImage: "exclamationmark.bubble", description: Text(errorMessage))
        } else {
            ProgressView()
        }
    }

    // discord's double tap, the first quick reaction
    // a tap on the conversation puts away whatever is in the keyboard's place, the keyboard
    // too, as discord does, so there is a way out even when there is nothing to scroll
    // the keyboard goes first and stays down, as in discord: left up, the menu knocks it down
    // and its closing brings it back, the conversation jumping both times
    private func showActions(for message: Message) {
        Platform.dismissKeyboard()
        actionsMessage = message
    }

    private func showActionsFromRow(_ message: Message, at click: SecondaryClick?) {
        if let click {
            showActions(for: message, at: click)
        } else {
            showActions(for: message)
        }
    }

    private func showActions(for message: Message, at click: SecondaryClick) {
        guard listFrame.width > 0, listFrame.height > 0 else {
            return
        }

        menuAnchor = UnitPoint(
            x: (click.windowPoint.x - listFrame.minX) / listFrame.width,
            y: (click.windowPoint.y - listFrame.minY) / listFrame.height
        )
        showActions(for: message)
    }

    private func openUnlessShowingActions(_ url: URL) -> OpenURLAction.Result {
        guard actionsMessage == nil else {
            return .discarded
        }

        openURL(url)

        return .handled
    }

    // with only the newest rows laid out the top is in view, which isn't a scroll to it
    private func loadOlder() {
        guard firstShownIndex == 0 else {
            return
        }

        Task {
            await store.loadOlder()
        }
    }

    // after the window has been laid out, then the highlight fades
    private func scrollToFocused(_ proxy: ScrollViewProxy) async {
        guard let messageId = store.focusedMessageId else {
            return
        }

        // a quarter of the way down rather than centred: a tall message (a preview, an image)
        // stays whole on screen, and anything still loading grows down into view. the second
        // pass catches what finished laying out after the first and is a no op otherwise
        let anchor = UnitPoint(x: 0.5, y: 0.25)

        guard await pause(.milliseconds(120)) else {
            return
        }

        withAnimation(Motion.standard) {
            proxy.scrollTo(messageId, anchor: anchor)
        }

        highlightedMessageId = messageId

        guard await pause(.milliseconds(350)) else {
            return endHighlight()
        }

        withAnimation(Motion.standard) {
            proxy.scrollTo(messageId, anchor: anchor)
        }

        for strength in [1, 0.45, 1] {
            withAnimation(Motion.standard) {
                highlightStrength = strength
            }

            guard await pause(.milliseconds(320)) else {
                return endHighlight()
            }
        }

        guard await pause(.seconds(0.9)) else {
            return endHighlight()
        }

        withAnimation(.easeOut(duration: 0.6)) {
            highlightStrength = 0
        }

        guard await pause(.milliseconds(600)) else {
            return endHighlight()
        }

        endHighlight()
        store.focusedMessageId = nil
    }

    // false once the jump has been cancelled. a jump opened from search or pins is set while
    // that screen still covers the chat, and the chat showing again starts it over. a sleep
    // that is cancelled returns at once, so the cancelled run used to race through to the end
    // and clear the jump, taking the new run's glow with it
    private func pause(_ duration: Duration) async -> Bool {
        do {
            try await Task.sleep(for: duration)

            return true
        } catch {
            return false
        }
    }

    private func endHighlight() {
        highlightStrength = 0
        highlightedMessageId = nil
    }

    private func scrollToBottom() {
        withAnimation(Motion.standard) {
            scrollPosition.scrollTo(edge: .bottom)
        }
    }

    private func scrollToSentMessage(_: Int?, _ pendingId: Int?) {
        guard pendingId != nil else {
            return
        }

        scrollToBottom()
    }

    private func jumpToFirstUnread() {
        Task {
            await store.jumpToFirstUnread()
            store.unreadMarker = nil
        }
    }

    private func dismissUnreadMarker() {
        store.unreadMarker = nil
    }

    private func returnToPresent() {
        Task {
            await store.reload()
        }
    }

    // the keyboard going at once moves the messages, and the second tap of a double tap then
    // lands on whatever slid under the finger, a link it opens. so it waits out a double tap
    private func closeAttachPanel() {
        store.attachPanel.close()

        keyboardDismissal?.cancel()
        keyboardDismissal = Task {
            try? await Task.sleep(for: .milliseconds(320))

            guard !Task.isCancelled else {
                return
            }

            Platform.dismissKeyboard()
        }
    }

    private var attachPanelDrag: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { value in
                if value.translation.height > 0 {
                    store.attachPanel.drag(value.translation.height)
                }
            }
            .onEnded { value in
                if store.attachPanel.isDragging {
                    store.attachPanel.release(predicted: value.predictedEndTranslation.height, velocity: value.velocity.height)
                }
            }
    }

    private func react(to message: Message) {
        keyboardDismissal?.cancel()

        Haptics.light()

        Task {
            do {
                try await session.toggleReaction(messageId: message.id, emoji: AppSettings.shared.doubleTapReaction)
            } catch {
                session.showError(error)
            }
        }
    }

    private func quickReact(_ emoji: String, to message: Message) {
        Task {
            do {
                try await session.toggleReaction(messageId: message.id, emoji: emoji)
            } catch {
                session.showError(error)
            }
        }
    }

    private func reply(to message: Message) {
        store.composerMode = .replying(message)
    }

    private func showMenuSheet(_ sheet: MessageMenuSheet) {
        menuSheet = sheet
    }

    // the actions sheet has to finish closing before another presentation can start. told
    // by the sheet itself that it has: a wait guessed at its length was wrong whenever the
    // sheet took longer to go
    private func confirmDelete(_ message: Message) {
        deleteAfterActions = message
        actionsMessage = nil
    }

    private func delete(_ message: Message) {
        Task {
            do {
                try await store.delete(message)
            } catch {
                session.showError(error)
            }
        }
    }

    private func openThread(_ message: Message) {
        threadAfterActions = message
        actionsMessage = nil
    }

    private func openPendingThread() {
        guard
            let parentId = store.pendingThreadParentId,
            let parent = store.messages.first(where: { $0.id == parentId })
        else {
            return
        }

        store.pendingThreadParentId = nil

        if let openThreadPanel {
            openThreadPanel(parent)
        } else {
            openedThread = parent
        }
    }

    private func continueAfterActions() {
        if let message = deleteAfterActions {
            deleteAfterActions = nil
            deletingMessage = message

            return
        }

        guard let message = threadAfterActions else {
            return
        }

        threadAfterActions = nil

        if let openThreadPanel {
            openThreadPanel(message)
        } else {
            openedThread = message
        }
    }

    private func startsNewDay(at index: Int) -> Bool {
        let calendar = Calendar.current

        guard index > 0 else {
            guard !store.hasOlder else {
                return false
            }

            guard let headerDate else {
                return true
            }

            return !calendar.isDate(store.messages[index].createdDate, inSameDayAs: headerDate)
        }

        return !calendar.isDate(store.messages[index].createdDate, inSameDayAs: store.messages[index - 1].createdDate)
    }

    // the next message continues this block, its first line only 2pt below this one's last
    private func isFollowedClosely(at index: Int) -> Bool {
        let next = index + 1

        guard next < store.messages.count else {
            return false
        }

        return !showsHeader(at: next) && store.messages[next].id != firstUnreadId
    }

    // each message by someone you blocked, keyed to the run of their messages it is part of:
    // the run folds into one row until it is asked to show
    private func blockedStretches() -> [Int: BlockedStretch] {
        let blocked = Set(session.friendLists.blocked)

        guard !blocked.isEmpty else {
            return [:]
        }

        var stretches: [Int: BlockedStretch] = [:]
        var current: BlockedStretch?
        var currentIds: [Int] = []

        func close() {
            if let current {
                for id in currentIds {
                    stretches[id] = BlockedStretch(startId: current.startId, count: currentIds.count)
                }
            }

            current = nil
            currentIds = []
        }

        var previousUserId: Int?

        for message in store.messages {
            guard let userId = message.userId, blocked.contains(userId) else {
                close()
                previousUserId = nil
                continue
            }

            if userId != previousUserId {
                close()
                current = BlockedStretch(startId: message.id, count: 0)
            }

            currentIds.append(message.id)
            previousUserId = userId
        }

        close()

        return stretches
    }

    private func toggleBlockedStretch(_ startId: Int) {
        if revealedBlockedStretches.contains(startId) {
            revealedBlockedStretches.remove(startId)
        } else {
            revealedBlockedStretches.insert(startId)
        }
    }

    private func showsHeader(at index: Int) -> Bool {
        guard index > 0, !startsNewDay(at: index) else {
            return true
        }

        let message = store.messages[index]
        let previous = store.messages[index - 1]

        // a reply always starts its own block, the reply line sits above the name
        return message.replyToMessageId != nil
            || previous.userId != message.userId
            || previous.pluginId != message.pluginId
            || previous.webhookName != message.webhookName
            || message.createdAt - previous.createdAt > Self.groupingWindow
    }
}

// discord's bar over the bottom of an older stretch of the conversation
// a rounded, inset glow rather than a hard edged band across the whole row
private struct JumpHighlight: View {
    let strength: Double
    let hasHeader: Bool
    let isFollowedClosely: Bool

    // the press's card, under the room the row keeps above its text
    var body: some View {
        MessageCard(hasHeader: hasHeader, isFollowedClosely: isFollowedClosely)
            .opacity(strength)
            .padding(.top, hasHeader ? MessageRowBand.headerGap : MessageRowBand.lineGap)
    }
}

private struct JumpToPresentBar: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text("You're viewing older messages")
                    .foregroundStyle(Theme.text)

                Spacer(minLength: 8)

                Text("Jump to Present")
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)

                Image(systemName: "arrow.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
            }
            .font(.subheadline)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.blurple, in: .capsule)
            .padding(.horizontal, 12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

// discord's blue bar across the top of a conversation opened with unread messages: how many
// and since when, a tap goes to the first of them
private struct NewMessagesBar: View {
    let count: Int
    let since: Date?
    let onJump: () -> Void
    let onClose: () -> Void

    private var title: String {
        let amount = count >= 25 ? "25+" : "\(count)"

        guard let since else {
            if count == 1 {
                return String(localized: "1 new message")
            }

            return String(localized: "\(amount) new messages")
        }

        // short enough to fit beside Jump: the time today, the weekday and time this week, the
        // date alone before that. a full date with its year ran off the end
        let time: String
        let calendar = Calendar.current
        let elapsed = calendar.dateComponents([.day], from: calendar.startOfDay(for: since), to: calendar.startOfDay(for: .now))
        let daysAgo = elapsed.day ?? 0

        if daysAgo == 0 {
            time = since.formatted(date: .omitted, time: .shortened)
        } else if daysAgo < 7 {
            time = since.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        } else {
            time = since.formatted(.dateTime.month(.abbreviated).day())
        }

        if count == 1 {
            return String(localized: "1 new message since \(time)")
        }

        return String(localized: "\(amount) new messages since \(time)")
    }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onJump) {
                HStack(spacing: 8) {
                    Text(title)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text("Jump")
                        .fontWeight(.semibold)

                    Image(systemName: "arrow.up")
                        .font(.caption.weight(.bold))
                }
                .padding(.leading, 16)
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            Button(action: onClose) {
                Label("Dismiss", systemImage: "xmark")
                    .labelStyle(.iconOnly)
                    .font(.body.weight(.semibold))
                    .frame(width: 48)
                    .frame(maxHeight: .infinity)
                    .contentShape(.rect)
            }
                .buttonStyle(.plain)
        }
        .font(.subheadline)
        .foregroundStyle(.white)
        .frame(height: 40)
        .background(Theme.blurple)
    }
}

// the red line above the first unread message
private struct NewMessagesDivider: View {
    var body: some View {
        HStack(spacing: 8) {
            Theme.red.frame(height: 1)

            Text("NEW MESSAGES")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.redText)
                .fixedSize()

            Theme.red.frame(height: 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 2)
    }
}

// the conversation's last few points fading into what it scrolls under, in the chat's color
private struct EdgeFade: View {
    let edge: VerticalEdge

    var body: some View {
        LinearGradient(
            colors: [Theme.chatBackground, Theme.chatBackground.opacity(0)],
            startPoint: edge == .top ? .top : .bottom,
            endPoint: edge == .top ? .bottom : .top
        )
        .frame(height: 12)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// the round button over the bottom right corner once the conversation is scrolled well up.
// glass like the system's own floating buttons, the messages showing through as they pass
private struct JumpToBottomButton: View {
    let action: () -> Void

    // the whole circle inside the button, not just the arrow: a tap beside the arrow went
    // through to the message under it
    var body: some View {
        Button(action: action) {
            Label("Jump to Bottom", systemImage: "arrow.down")
                .labelStyle(.iconOnly)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.text)
                .frame(width: 44, height: 44)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .floatingGlassCircle()
    }
}

private struct BlockedStretch {
    let startId: Int
    let count: Int
}

// a blocked person's run of messages folded into one line, as discord does, opened on asking
private struct BlockedMessagesRow: View {
    let count: Int
    // opened, the row stays above the messages to fold them away again
    let isShown: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "nosign")
                .foregroundStyle(Theme.muted)

            label
                .foregroundStyle(Theme.muted)

            Button(toggleTitle, action: onToggle)
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accentText)
                .fontWeight(.semibold)
        }
        .font(.subheadline)
        .padding(.horizontal, 16)
        .padding(.top, MessageRowBand.headerGap)
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: Text(toggleTitle), onToggle)
    }

    private var toggleTitle: LocalizedStringKey {
        isShown ? "Hide" : "Show"
    }

    private var label: Text {
        if count == 1 {
            return Text("1 blocked message")
        }

        return Text("\(count) blocked messages")
    }
}
