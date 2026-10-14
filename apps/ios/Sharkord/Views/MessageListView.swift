import SwiftUI

struct MessageListView<Header: View>: View {
    let store: ChannelMessagesStore
    @ViewBuilder let header: Header

    @Environment(SessionStore.self) private var session

    @State private var actionsMessage: Message?
    @State private var deletingMessage: Message?
    @State private var openedThread: Message?

    // consecutive messages from the same author inside this window share one header
    private static var groupingWindow: Int { 7 * 60 * 1000 }

    var body: some View {
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

                    MessageRow(
                        message: message,
                        showsHeader: showsHeader(at: index),
                        showsThreadLink: store.scope == .channel,
                        onLongPress: { actionsMessage = message },
                        onDoubleTap: { react(to: message) }
                    )
                }
            }
            .padding(.bottom, 12)
        }
        .defaultScrollAnchor(.bottom)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
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
