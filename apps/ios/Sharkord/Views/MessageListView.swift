import SwiftUI

struct MessageListView<Header: View>: View {
    let store: ChannelMessagesStore
    @ViewBuilder let header: Header

    @State private var actionsMessage: Message?
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
                        onLongPress: { actionsMessage = message }
                    )
                }
            }
            .padding(.bottom, 12)
        }
        .defaultScrollAnchor(.bottom)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.chatBackground)
        .overlay {
            if !store.hasLoaded {
                loadingOverlay
            }
        }
        .sheet(item: $actionsMessage) { message in
            MessageActionsSheet(
                message: message,
                canOpenThread: store.scope == .channel,
                onOpenThread: { openThread(message) }
            )
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

        return previous.userId != message.userId
            || previous.pluginId != message.pluginId
            || message.createdAt - previous.createdAt > Self.groupingWindow
    }
}
