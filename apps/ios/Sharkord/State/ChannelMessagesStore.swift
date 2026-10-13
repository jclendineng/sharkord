import Foundation
import Observation

// one list of messages: either a channel's top level messages or the replies of one thread
@Observable
final class ChannelMessagesStore {
    enum Scope: Hashable {
        case channel
        case thread(parentMessageId: Int)
    }

    let channelId: Int
    let scope: Scope

    // oldest first, the way the list renders them
    private(set) var messages: [Message] = []
    private(set) var hasOlder = false
    private(set) var hasLoaded = false
    private(set) var isLoading = false
    var errorMessage: String?
    var isVisible = false

    private var nextCursor: MessagesCursor?
    private unowned let session: SessionStore

    init(channelId: Int, scope: Scope, session: SessionStore) {
        self.channelId = channelId
        self.scope = scope
        self.session = session
    }

    private struct ChannelPageInput: Encodable {
        let channelId: Int
        let cursor: MessagesCursor?
    }

    private struct ThreadPageInput: Encodable {
        let parentMessageId: Int
        let cursor: MessagesCursor?
    }

    private struct SendInput: Encodable {
        let channelId: Int
        let content: String
        let files: [String]
        let parentMessageId: Int?
    }

    func loadIfNeeded() async {
        guard !hasLoaded else {
            return
        }

        await reload()
    }

    func reload() async {
        guard let page = await fetchPage(cursor: nil) else {
            return
        }

        messages = Self.sorted(page.messages)
        nextCursor = page.nextCursor
        hasOlder = page.nextCursor != nil
        hasLoaded = true
    }

    func loadOlder() async {
        guard hasOlder, let nextCursor, let page = await fetchPage(cursor: nextCursor) else {
            return
        }

        let knownIds = Set(messages.map(\.id))

        messages = Self.sorted(page.messages.filter { !knownIds.contains($0.id) } + messages)
        self.nextCursor = page.nextCursor
        hasOlder = page.nextCursor != nil
    }

    func send(_ text: String, files: [TemporaryFile]) async throws {
        guard let client = session.client else {
            throw TRPCError(message: "Not connected to the server.", code: nil)
        }

        var parentMessageId: Int?

        if case .thread(let id) = scope {
            parentMessageId = id
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        try await client.mutation(
            "messages.send",
            input: SendInput(
                channelId: channelId,
                content: trimmed.isEmpty ? "" : HTMLText.paragraphs(from: trimmed),
                files: files.map(\.id),
                parentMessageId: parentMessageId
            )
        )
    }

    func belongs(_ message: Message) -> Bool {
        guard message.channelId == channelId else {
            return false
        }

        switch scope {
        case .channel:
            return message.parentMessageId == nil
        case .thread(let parentMessageId):
            return message.parentMessageId == parentMessageId
        }
    }

    func insert(_ message: Message) {
        guard hasLoaded, belongs(message), !messages.contains(where: { $0.id == message.id }) else {
            return
        }

        messages = Self.sorted(messages + [message])
    }

    func update(_ message: Message) {
        guard let index = messages.firstIndex(where: { $0.id == message.id }) else {
            return
        }

        messages[index] = message
    }

    func updateReplyCount(messageId: Int, replyCount: Int) {
        guard let index = messages.firstIndex(where: { $0.id == messageId }) else {
            return
        }

        messages[index].replyCount = replyCount
    }

    func remove(_ messageId: Int) {
        messages.removeAll { $0.id == messageId }
    }

    private func fetchPage(cursor: MessagesCursor?) async -> MessagesPage? {
        guard let client = session.client, !isLoading else {
            return nil
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let page: MessagesPage

            switch scope {
            case .channel:
                page = try await client.query(
                    "messages.get",
                    input: ChannelPageInput(channelId: channelId, cursor: cursor)
                )
            case .thread(let parentMessageId):
                page = try await client.query(
                    "messages.getThread",
                    input: ThreadPageInput(parentMessageId: parentMessageId, cursor: cursor)
                )
            }

            errorMessage = nil

            return page
        } catch {
            errorMessage = error.localizedDescription

            return nil
        }
    }

    private static func sorted(_ messages: [Message]) -> [Message] {
        messages.sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
    }
}
