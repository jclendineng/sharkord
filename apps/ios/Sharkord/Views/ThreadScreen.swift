import SwiftUI

struct ThreadScreen: View {
    let parent: Message
    // set when it is the mac's panel beside the chat rather than a page of its own
    var onClose: (() -> Void)?

    @Environment(SessionStore.self) private var session

    private var store: ChannelMessagesStore {
        session.thread(for: parent)
    }

    private var canUpload: Bool {
        session.settings?.storageUploadEnabled == true
    }

    var body: some View {
        if let onClose {
            thread
                .safeAreaInset(edge: .top, spacing: 0) {
                    ThreadPanelHeader(onClose: onClose)
                }
                // escape closes it, as it does discord's
                .background {
                    Button("Close Thread", action: onClose)
                        .keyboardShortcut(.cancelAction)
                        .hidden()
                }
        } else {
            thread
                .navigationTitle("Thread")
                .inlineNavigationTitle()
                .navigationBarBackground(Theme.chatBackground)
                .navigationBarBackgroundVisible()
                .tabBarHidden()
                .escapeGoesBack()
        }
    }

    private var thread: some View {
        MessageListView(store: store) {
            VStack(alignment: .leading, spacing: 0) {
                ThreadStarterRow(parent: parent)

                Theme.divider
                    .frame(height: 1)
                    .padding(.top, 12)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ComposerView(placeholder: "Reply in thread", canUpload: canUpload, store: store)
        }
        // while the keyboard and the attachment panel trade places, see AttachPanelModel
        .ignoresSafeArea(store.attachPanel.isHandingOff ? .keyboard : [], edges: .bottom)
        .task {
            store.isVisible = true
            await store.loadIfNeeded()
        }
        .onDisappear {
            store.isVisible = false
        }
    }
}

// the panel's own top, as the chat's bar belongs to the chat beside it
private struct ThreadPanelHeader: View {
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .foregroundStyle(Theme.muted)

            Text("Thread")
                .font(.headline)
                .foregroundStyle(Theme.header)

            Spacer()

            Button(action: onClose) {
                Label("Close Thread", systemImage: "xmark")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 32, height: 32)
                    .contentShape(.rect)
            }
                .hoverHighlight(cornerRadius: 8)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(Theme.chatBackground)
        .overlay(alignment: .bottom) {
            Theme.divider
                .frame(height: 1)
        }
    }
}

extension EnvironmentValues {
    // the mac's chat shows a thread in a panel beside it rather than as a page over it
    @Entry var openThreadPanel: (@MainActor (Message) -> Void)?
}

// the message the thread hangs off, with the same menu as any other: edit, reply, react, pin.
// read from its channel, so an edit made here shows here, not the copy the thread was opened with
private struct ThreadStarterRow: View {
    let parent: Message

    @Environment(SessionStore.self) private var session
    @Environment(\.showMessageActions) private var showMessageActions
    @Environment(\.reactToMessage) private var reactToMessage

    private var message: Message {
        let channel = session.messages(for: parent.channelId)

        return channel.messages.first { $0.id == parent.id } ?? parent
    }

    var body: some View {
        MessageRow(
            message: message,
            showsHeader: true,
            showsThreadLink: false,
            onLongPress: showActions,
            onDoubleTap: react,
            onSecondaryClick: showActionsAtPointer
        )
    }

    private func showActions() {
        showMessageActions?(message, nil)
    }

    private func react() {
        reactToMessage?(message)
    }

    private func showActionsAtPointer(_ click: SecondaryClick) {
        showMessageActions?(message, click)
    }
}
