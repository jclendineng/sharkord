import SwiftUI

// the pin button in a channel's top bar, like the web's pinned messages popover
struct PinnedMessagesSheet: View {
    let channelId: Int
    // set when it is the dropdown under the top bar rather than a presentation, which dismiss would not close
    var onClose: (() -> Void)?

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var pins: [Message]?
    @State private var errorMessage: String?

    var body: some View {
        content
            .sheetDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Theme.deepBackground)
            .task {
                await load()
            }
    }

    @ViewBuilder
    private var content: some View {
        if onClose != nil {
            // the dropdown names itself: a navigation title there goes up into the top bar
            VStack(spacing: 0) {
                Text("Pinned Messages")
                    .font(.headline)
                    .foregroundStyle(Theme.header)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                Theme.divider
                    .frame(height: 1)

                list
            }
        } else {
            NavigationStack {
                list
                    .navigationTitle("Pinned Messages")
                    .inlineNavigationTitle()
                    .toolbar {
                        if !Platform.isMac {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done", action: close)
                            }
                        }
                    }
            }
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let pins {
                    if pins.isEmpty {
                        ContentUnavailableView(
                            "No Pinned Messages",
                            systemImage: "pin",
                            description: Text("Long press a message and choose Pin Message to keep it here.")
                        )
                        .padding(.top, 60)
                    } else {
                        ForEach(pins) { message in
                            PinnedMessageRow(
                                message: message,
                                onOpen: { jump(to: message) },
                                onUnpinned: { removePin(message.id) }
                            )
                        }
                    }
                } else if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(Theme.red)
                        .padding(18)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        }

        .background(Theme.deepBackground)
    }

    private func load() async {
        do {
            pins = try await session.request("messages.getPinned", ["channelId": channelId])
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func close() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    private func removePin(_ messageId: Int) {
        pins?.removeAll { $0.id == messageId }
    }

    // the chat is right under this sheet, it scrolls to the pin, loading around it if it is old
    private func jump(to message: Message) {
        let store = session.messages(for: channelId)

        close()

        Task {
            await store.jump(to: message.id)
        }
    }
}
