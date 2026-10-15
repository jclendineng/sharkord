import SwiftUI

struct MessageListView<Header: View>: View {
    let store: ChannelMessagesStore
    @ViewBuilder let header: Header

    @Environment(SessionStore.self) private var session
    // the root's, which asks before leaving the app, see LinkGuard
    @Environment(\.openURL) private var openURL

    @State private var actionsMessage: Message?
    @State private var deletingMessage: Message?
    @State private var openedThread: Message?

    // consecutive messages from the same author inside this window share one header
    private static var groupingWindow: Int { 7 * 60 * 1000 }

    // the message a jump landed on, lit up for a moment like discord's
    @State private var highlightedMessageId: Int?
    // far enough up the conversation for discord's round button back down
    @State private var isAwayFromBottom = false

    private var firstUnreadId: Int? {
        store.firstUnreadMessage?.id
    }

    var body: some View {
        ScrollViewReader { proxy in
            messageList
                .task(id: store.focusedMessageId) {
                    await scrollToFocused(proxy)
                }
                .overlay(alignment: .bottomTrailing) {
                    if isAwayFromBottom, !store.hasNewer {
                        JumpToBottomButton {
                            scrollToBottom(proxy)
                        }
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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if store.hasOlder {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                        .task {
                            await store.loadOlder()
                        }
                } else if store.hasLoaded {
                    header
                }

                ForEach(Array(store.messages.enumerated()), id: \.element.id) { index, message in
                    if startsNewDay(at: index) {
                        DaySeparator(date: message.createdDate)
                    }

                    if message.id == firstUnreadId {
                        NewMessagesDivider()
                    }

                    MessageRow(
                        message: message,
                        showsHeader: showsHeader(at: index) || message.id == firstUnreadId,
                        showsThreadLink: store.scope == .channel,
                        onLongPress: { showActions(for: message) },
                        onDoubleTap: { react(to: message) }
                    )
                    .background(Theme.blurple.opacity(highlightedMessageId == message.id ? 0.18 : 0))
                }
            }
            .padding(.bottom, 12)
        }
        .defaultScrollAnchor(.bottom)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            let distance = geometry.contentSize.height - geometry.contentOffset.y - geometry.containerSize.height

            return distance > 600
        } action: { _, isAway in
            isAwayFromBottom = isAway
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
        // the same for a link in the message, which opens on the finger lifting
        .environment(\.openURL, OpenURLAction(handler: openUnlessShowingActions))
        .sheet(item: $actionsMessage) { message in
            MessageActionsSheet(
                message: message,
                store: store,
                canOpenThread: store.scope == .channel,
                onOpenThread: { openThread(message) },
                onDelete: confirmDelete
            )
        }
        .fullScreenCover(item: $deletingMessage) { message in
            DeleteMessageConfirmation(message: message, onConfirm: { delete(message) })
                .presentationBackground(.clear)
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
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        actionsMessage = message
    }

    private func openUnlessShowingActions(_ url: URL) -> OpenURLAction.Result {
        guard actionsMessage == nil else {
            return .discarded
        }

        openURL(url)

        return .handled
    }

    // after the window has been laid out, then the highlight fades
    private func scrollToFocused(_ proxy: ScrollViewProxy) async {
        guard let messageId = store.focusedMessageId else {
            return
        }

        try? await Task.sleep(for: .milliseconds(120))

        withAnimation(.smooth(duration: 0.3)) {
            proxy.scrollTo(messageId, anchor: .center)
        }

        highlightedMessageId = messageId

        try? await Task.sleep(for: .seconds(1.6))

        withAnimation(.easeOut(duration: 0.6)) {
            highlightedMessageId = nil
        }

        store.focusedMessageId = nil
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let last = store.messages.last else {
            return
        }

        withAnimation(.smooth(duration: 0.35)) {
            proxy.scrollTo(last.id, anchor: .bottom)
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

    private func closeAttachPanel() {
        store.attachPanel.close()
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
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
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        Task {
            do {
                try await session.toggleReaction(messageId: message.id, emoji: AppSettings.shared.doubleTapReaction)
            } catch {
                session.showError(error)
            }
        }
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
        actionsMessage = nil
        openedThread = message
    }

    private func startsNewDay(at index: Int) -> Bool {
        guard index > 0 else {
            return !store.hasOlder
        }

        let calendar = Calendar.current

        return !calendar.isDate(store.messages[index].createdDate, inSameDayAs: store.messages[index - 1].createdDate)
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
            || message.createdAt - previous.createdAt > Self.groupingWindow
    }
}

// discord's bar over the bottom of an older stretch of the conversation
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

            Button("Dismiss", systemImage: "xmark", action: onClose)
                .labelStyle(.iconOnly)
                .font(.body.weight(.semibold))
                .frame(width: 48)
                .frame(maxHeight: .infinity)
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

    var body: some View {
        Button("Jump to Bottom", systemImage: "arrow.down", action: action)
            .labelStyle(.iconOnly)
            .font(.body.weight(.semibold))
            .foregroundStyle(Theme.text)
            .frame(width: 44, height: 44)
            .background(Theme.listBackground, in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Theme.divider, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
            .buttonStyle(.plain)
    }
}
