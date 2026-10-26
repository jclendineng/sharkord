import SwiftUI

struct MessageListView<Header: View>: View {
    let store: ChannelMessagesStore
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

    // consecutive messages from the same author inside this window share one header
    private static var groupingWindow: Int { 7 * 60 * 1000 }

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

    private var firstUnreadId: Int? {
        store.firstUnreadMessage?.id
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
                .overlay(alignment: .bottomTrailing) {
                    if isAwayFromBottom, !store.hasNewer {
                        JumpToBottomButton(action: scrollToBottom)
                        .padding(12)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                }
                .animation(.snappy(duration: 0.2), value: isAwayFromBottom)
        }
        .overlay(alignment: .top) {
            if let unreadMarker = store.unreadMarker {
                NewMessagesBar(
                    count: unreadMarker.count,
                    since: store.firstUnreadMessage?.createdDate,
                    onJump: jumpToFirstUnread,
                    onClose: dismissUnreadMarker
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.25), value: store.unreadMarker)
        // the list is a window around an older message, a way back to the newest
        .overlay(alignment: .bottom) {
            if store.hasNewer {
                JumpToPresentBar(action: returnToPresent)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.25), value: store.hasNewer)
    }

    private var messageList: some View {
        // read once, not once per row: the lookup is a scan of every loaded message, and the
        // list asked for it twice in each of fifty rows
        let unreadId = store.firstUnreadMessage?.id

        return ScrollView {
            // every loaded message is laid out, not only the ones on screen: a lazy stack guessed the
            // height of the rest, and with pictures and previews its guesses were hundreds of points
            // out, the list jumping as it corrected them mid scroll. a page is fifty messages
            VStack(alignment: .leading, spacing: 0) {
                if store.hasOlder {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                } else if store.hasLoaded {
                    header
                }

                ForEach(Array(store.messages.enumerated()), id: \.element.id) { index, message in
                    if startsNewDay(at: index) {
                        DaySeparator(date: message.createdDate)
                    }

                    if message.id == unreadId {
                        NewMessagesDivider()
                    }

                    let showsHeader = showsHeader(at: index) || message.id == unreadId

                    MessageRow(
                        message: message,
                        showsHeader: showsHeader,
                        isFollowedClosely: isFollowedClosely(at: index),
                        showsThreadLink: store.scope == .channel,
                        onLongPress: { showActions(for: message) },
                        onDoubleTap: { react(to: message) },
                        onSecondaryClick: { click in showActions(for: message, at: click) },
                        hoverActions: MessageHoverActions(
                            onReact: { emoji in quickReact(emoji, to: message) },
                            onReply: { reply(to: message) },
                            onMore: { click in showActions(for: message, at: click) }
                        )
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
            // the full width even with nothing but the welcome in it: an empty channel's list was
            // only as wide as that text, and the chat shrank to it with black down both sides
            .frame(maxWidth: .infinity, alignment: .leading)
            // room for the typing indicator, which sits over the bottom of the list so it coming
            // and going moves nothing, below the newest message rather than over it
            .padding(.bottom, 28)
        }
        .scrollPosition($scrollPosition)
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
            if isPinnedToBottom, distance > 1, store.focusedMessageId == nil, !store.hasNewer {
                scrollPosition.scrollTo(edge: .bottom)
            }
        }
        .onScrollPhaseChange { _, phase in
            if phase == .interacting {
                isPinnedToBottom = false
            }
        }
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
        // it while the conversation scrolls, a tap puts it away
        .simultaneousGesture(attachPanelDrag)
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
        .actionsPresentation(item: $actionsMessage, anchor: menuAnchor, onDismiss: openThreadAfterActions) { message in
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

    private func loadOlder() {
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

        withAnimation(.smooth(duration: 0.3)) {
            proxy.scrollTo(messageId, anchor: anchor)
        }

        highlightedMessageId = messageId

        guard await pause(.milliseconds(350)) else {
            return endHighlight()
        }

        withAnimation(.smooth(duration: 0.3)) {
            proxy.scrollTo(messageId, anchor: anchor)
        }

        for strength in [1, 0.45, 1] {
            withAnimation(.easeInOut(duration: 0.3)) {
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
        withAnimation(.smooth(duration: 0.35)) {
            scrollPosition.scrollTo(edge: .bottom)
        }
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
                    store.attachPanel.release(predicted: value.predictedEndTranslation.height)
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
        store.editing = nil
        store.replyingTo = message
    }

    private func showMenuSheet(_ sheet: MessageMenuSheet) {
        menuSheet = sheet
    }

    private func confirmDelete(_ message: Message) {
        // the actions sheet has to finish closing before another presentation can start
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            deletingMessage = message
        }
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

    private func openThreadAfterActions() {
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
        guard index > 0 else {
            return !store.hasOlder
        }

        let calendar = Calendar.current

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

    // a row carries its gap above it and none below, so the glow trims the top and reaches
    // past the bottom, but only into free space, never over the next message's first line
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

        shape
            .fill(Theme.blurple.opacity(0.16 * strength))
            .overlay {
                shape.stroke(Theme.blurple.opacity(0.55 * strength), lineWidth: 1.5)
            }
            .shadow(color: Theme.blurple.opacity(0.4 * strength), radius: 12)
            .padding(.horizontal, 6)
            .padding(.top, hasHeader ? 10 : -2)
            .padding(.bottom, isFollowedClosely ? -2 : -6)
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
        let noun = count == 1 ? "new message" : "new messages"

        guard let since else {
            return "\(amount) \(noun)"
        }

        let time = Calendar.current.isDateInToday(since)
            ? since.formatted(date: .omitted, time: .shortened)
            : since.formatted(date: .abbreviated, time: .shortened)

        return "\(amount) \(noun) since \(time)"
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
                .foregroundStyle(Theme.red)
                .fixedSize()

            Theme.red.frame(height: 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 2)
    }
}

// the round button over the bottom right corner once the conversation is scrolled well up
private struct JumpToBottomButton: View {
    let action: () -> Void

    // the whole tile inside the button, not just the arrow: a tap beside the arrow went through
    // to the message under it
    var body: some View {
        Button(action: action) {
            Label("Jump to Bottom", systemImage: "arrow.down")
                .labelStyle(.iconOnly)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.text)
                .frame(width: 44, height: 44)
                .background(Theme.listBackground, in: .rect(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Theme.divider, lineWidth: 1)
                }
                .contentShape(.rect(cornerRadius: 12))
        }
        .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
        .buttonStyle(.plain)
    }
}
