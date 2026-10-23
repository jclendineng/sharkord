import SwiftUI

// sends a copy of a message to another channel or conversation on the same server, marked as
// forwarded. attachments stay behind: the server only takes files from a fresh upload
struct ForwardSheet: View {
    let message: Message

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var sendingTo: Int?
    @State private var errorMessage: String?

    private var conversations: [DirectMessageConversation] {
        session.directMessages.filter { conversation in
            query.isEmpty || session.usersById[conversation.userId]?.name.localizedCaseInsensitiveContains(query) == true
        }
    }

    private var channels: [Channel] {
        session.channelSections
            .flatMap(\.channels)
            .filter { $0.type == .text && $0.id != message.channelId && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) }
    }

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(Theme.red)
                }

                if !message.files.isEmpty {
                    Text("Attachments aren't forwarded, only the text.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }

                if !conversations.isEmpty {
                    Section("Direct Messages") {
                        ForEach(conversations) { conversation in
                            destination(conversation.channelId) {
                                HStack(spacing: 12) {
                                    AvatarView(user: session.usersById[conversation.userId], size: 30, showsStatus: true)

                                    Text(session.usersById[conversation.userId]?.name ?? "Unknown")
                                }
                            }
                        }
                    }
                }

                Section("Channels") {
                    ForEach(channels) { channel in
                        destination(channel.id) {
                            Label(channel.name, systemImage: "number")
                        }
                    }
                }
            }
            .settingsListStyle()
            .searchable(text: $query, prompt: "Search")
            .navigationTitle("Forward To")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: close)
                }
            }
        }
        .presentationBackground(Theme.deepBackground)
    }

    private func destination<Label: View>(_ channelId: Int, @ViewBuilder label: () -> Label) -> some View {
        Button(action: { send(to: channelId) }) {
            HStack {
                label()
                    .foregroundStyle(Theme.header)

                Spacer()

                if sendingTo == channelId {
                    ProgressView()
                } else {
                    Text("Send")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.blurple)
                }
            }
            .contentShape(.rect)
        }
        .disabled(sendingTo != nil)
    }

    private func send(to channelId: Int) {
        guard let client = session.client else {
            return
        }

        struct ForwardInput: Encodable {
            let channelId: Int
            let content: String
            let files: [String]
        }

        let source = session.channel(message.channelId)
        let origin = source.map { $0.isDm ? "a direct message" : "#\($0.name)" } ?? "another channel"
        let content = "<p><em>Forwarded from \(origin)</em></p>" + (message.content ?? "")

        sendingTo = channelId
        errorMessage = nil

        Task {
            do {
                try await client.mutation("messages.send", input: ForwardInput(channelId: channelId, content: content, files: []))
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }

            sendingTo = nil
        }
    }

    private func close() {
        dismiss()
    }
}
