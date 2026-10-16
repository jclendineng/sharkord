import SwiftUI

// the pin button in a channel's top bar, like the web's pinned messages popover
struct PinnedMessagesSheet: View {
    let channelId: Int

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var pins: [Message]?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
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
            .navigationTitle("Pinned Messages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: close)
                }
            }
        }
        .sheetDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.deepBackground)
        .task {
            await load()
        }
    }

    private func load() async {
        do {
            pins = try await session.request("messages.getPinned", ["channelId": channelId])
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func close() {
        dismiss()
    }

    private func removePin(_ messageId: Int) {
        pins?.removeAll { $0.id == messageId }
    }

    // the chat is right under this sheet, it scrolls to the pin, loading around it if it is old
    private func jump(to message: Message) {
        let store = session.messages(for: channelId)

        dismiss()

        Task {
            await store.jump(to: message.id)
        }
    }
}
