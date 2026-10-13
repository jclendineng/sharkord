import SwiftUI

struct ThreadScreen: View {
    let parent: Message

    @Environment(SessionStore.self) private var session

    private var store: ChannelMessagesStore {
        session.thread(for: parent)
    }

    private var canUpload: Bool {
        session.settings?.storageUploadEnabled == true
    }

    var body: some View {
        MessageListView(store: store) {
            VStack(alignment: .leading, spacing: 0) {
                MessageRow(message: parent, showsHeader: true, showsThreadLink: false, onLongPress: {}, onDoubleTap: {})

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
        .navigationTitle("Thread")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.chatBackground, for: .navigationBar)
        .toolbarBackgroundVisibility(.visible, for: .navigationBar)
        .toolbarVisibility(.hidden, for: .tabBar)
        .task {
            store.isVisible = true
            await store.loadIfNeeded()
        }
        .onDisappear {
            store.isVisible = false
        }
    }
}
