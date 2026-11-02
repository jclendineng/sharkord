import SwiftUI

// where something shared from another app goes: any channel or conversation on any server the
// app is signed in to, several at once, with a message of its own
struct ShareToSheet: View {
    let share: PendingShare

    @Environment(ServerListStore.self) private var servers
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var message: String
    @State private var selected: Set<Destination> = []
    // the places a send that failed partway already reached, so trying again skips them
    @State private var sent: Set<Destination> = []
    @State private var isSending = false
    @State private var errorMessage: String?

    init(share: PendingShare) {
        self.share = share
        _message = State(initialValue: share.text)
    }

    struct Destination: Hashable {
        let sessionId: ObjectIdentifier
        let channelId: Int
    }

    fileprivate struct Place: Identifiable {
        let session: SessionStore
        let channelId: Int
        let name: String
        let isDirectMessage: Bool
        let refusal: String?

        var destination: Destination {
            Destination(sessionId: ObjectIdentifier(session), channelId: channelId)
        }

        var id: Destination {
            destination
        }
    }

    // the server on screen first, its conversations most recent first, then its channels
    private var places: [Place] {
        let selectedSession = servers.selectedSession
        let ordered = servers.sessions.filter { $0 === selectedSession } + servers.sessions.filter { $0 !== selectedSession }

        return ordered
            .filter { $0.client != nil }
            .flatMap(places(in:))
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.session.serverName.localizedCaseInsensitiveContains(query) }
    }

    private func places(in session: SessionStore) -> [Place] {
        let conversations = session.directMessages
            .sorted { $0.lastMessageAt > $1.lastMessageAt }
            .map { conversation in
                place(in: session, channelId: conversation.channelId, name: session.conversationTitle(for: conversation.channelId), isDirectMessage: true)
            }
        let channels = session.channelSections
            .flatMap(\.channels)
            .filter { $0.type == .text && session.can("SEND_MESSAGES", inChannel: $0.id) }
            .map { channel in
                place(in: session, channelId: channel.id, name: channel.name, isDirectMessage: false)
            }

        return conversations + channels
    }

    private func place(in session: SessionStore, channelId: Int, name: String, isDirectMessage: Bool) -> Place {
        Place(
            session: session,
            channelId: channelId,
            name: name,
            isDirectMessage: isDirectMessage,
            refusal: refusal(in: session, isDirectMessage: isDirectMessage)
        )
    }

    // the same rules the chat's own attach button follows
    private func refusal(in session: SessionStore, isDirectMessage: Bool) -> String? {
        guard !share.files.isEmpty else {
            return nil
        }

        guard let settings = session.settings, settings.storageUploadEnabled, !isDirectMessage || settings.storageFileSharingInDirectMessages else {
            return String(localized: "Attachments are turned off here.")
        }

        guard share.files.count <= settings.storageMaxFilesPerMessage else {
            return String(localized: "Takes up to \(settings.storageMaxFilesPerMessage) files in a message.")
        }

        return nil
    }

    private var trimmedMessage: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool {
        !isSending && !selected.isEmpty && (!share.files.isEmpty || !trimmedMessage.isEmpty)
    }

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(Theme.redText)
                }

                ForEach(places) { place in
                    ShareDestinationRow(place: place, isSelected: selected.contains(place.destination), toggle: toggle)
                }
            }
            .settingsListStyle()
            // a server's conversations arrive a moment after its channels when it has just connected
            .animation(.default, value: places.map(\.id))
            .pageSearchable(text: $query, prompt: "Search")
            .navigationTitle("Share To")
            .inlineNavigationTitle()
            .toolbar {
                ActionToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: cancel)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                composer
            }
        }
        .presentationBackground(Theme.deepBackground)
        .interactiveDismissDisabled(isSending)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !share.files.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(share.files, id: \.self) { file in
                            SharedFileTile(url: file)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            HStack(spacing: 10) {
                TextField("Add an optional message", text: $message, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Theme.inputBackground, in: .rect(cornerRadius: 20))

                Button(action: send) {
                    if isSending {
                        ProgressView()
                    } else {
                        Text("Send")
                            .fontWeight(.semibold)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSend)
            }
        }
        .padding(16)
        .background(Theme.deepBackground)
    }

    private func toggle(_ place: Place) {
        if selected.contains(place.destination) {
            selected.remove(place.destination)
        } else {
            selected.insert(place.destination)
        }
    }

    private func send() {
        let targets = places.filter { selected.contains($0.destination) && !sent.contains($0.destination) }
        let content = trimmedMessage.isEmpty ? "" : HTMLText.messageHTML(fromMarkdown: trimmedMessage)

        isSending = true
        errorMessage = nil

        Task {
            do {
                for target in targets {
                    try await send(content: content, to: target)
                    sent.insert(target.destination)
                }

                share.discard()
                servers.pendingShare = nil
                dismiss()

                // where it went opens, the first in the list when it went to several
                if let first = targets.first {
                    servers.open(channelId: first.channelId, in: first.session)
                }
            } catch {
                errorMessage = error.localizedDescription
            }

            isSending = false
        }
    }

    // each server takes its own upload, so the files go up once for every server sent to
    private func send(content: String, to place: Place) async throws {
        struct ShareInput: Encodable {
            let channelId: Int
            let content: String
            let files: [String]
        }

        let session = place.session

        guard let client = session.client, let address = session.address, let token = session.token else {
            throw AuthAPI.RequestError(message: String(localized: "Not connected to \(session.serverName)."))
        }

        var fileIds: [String] = []

        for file in share.files {
            let uploaded = try await UploadAPI.upload(fileAt: file, name: file.lastPathComponent, to: address, token: token)

            fileIds.append(uploaded.id)
        }

        try await client.mutation("messages.send", input: ShareInput(channelId: place.channelId, content: content, files: fileIds))
    }

    private func cancel() {
        share.discard()
        servers.pendingShare = nil
        dismiss()
    }
}

private struct ShareDestinationRow: View {
    let place: ShareToSheet.Place
    let isSelected: Bool
    let toggle: (ShareToSheet.Place) -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 12) {
                icon

                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name)
                        .foregroundStyle(Theme.header)
                        .lineLimit(1)

                    Text(place.refusal ?? subtitle)
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }

                Spacer()

                if place.refusal == nil {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Theme.blurple : Theme.muted)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(place.refusal != nil)
        .opacity(place.refusal == nil ? 1 : 0.5)
    }

    // a conversation shows the person, a channel its server, so the two read apart at a glance
    @ViewBuilder
    private var icon: some View {
        if place.isDirectMessage && place.session.group(for: place.channelId) == nil {
            AvatarView(user: place.session.directMessagePartner(for: place.channelId), size: 36)
                .environment(place.session)
        } else if place.isDirectMessage {
            Image(systemName: "person.2.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Theme.blurple, in: .circle)
        } else {
            ServerIcon(server: place.session)
                .frame(width: 36, height: 36)
                .clipShape(.rect(cornerRadius: 12))
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "number")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.header)
                        .frame(width: 18, height: 18)
                        .background(Theme.panelControl, in: .circle)
                        .offset(x: 5, y: 5)
                }
        }
    }

    private var subtitle: String {
        if place.isDirectMessage {
            return String(localized: "Direct Message · \(place.session.serverName)")
        }

        return String(localized: "Channel · \(place.session.serverName)")
    }

    private func select() {
        toggle(place)
    }
}

private struct SharedFileTile: View {
    let url: URL

    @State private var thumbnail: PlatformImage?

    var body: some View {
        Group {
            if let thumbnail {
                Image(platformImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "doc")
                        .font(.title2)

                    Text(url.lastPathComponent)
                        .font(.caption2)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(Theme.muted)
                .padding(6)
            }
        }
        .frame(width: 72, height: 72)
        .background(Theme.inputBackground)
        .clipShape(.rect(cornerRadius: 12))
        .task {
            thumbnail = await ImageThumbnail.make(ofAnyFile: url)
        }
    }
}
