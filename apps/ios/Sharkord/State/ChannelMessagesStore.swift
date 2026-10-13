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
    // the composer's mode, set from a message's long press sheet
    var replyingTo: Message?
    var editing: Message?
    // text the composer adds where the cursor is, a mention for instance
    var pendingInsert: String?
    // the composer's attachment panel, which the message list can drag away too
    let attachPanel = AttachPanelModel()

    // where typing here is signalled and shown
    var typingPlace: TypingTracker.Place {
        switch scope {
        case .channel:
            TypingTracker.Place(channelId: channelId, parentMessageId: nil)
        case .thread(let parentMessageId):
            TypingTracker.Place(channelId: channelId, parentMessageId: parentMessageId)
        }
    }

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
        let replyToMessageId: Int?
        var stickerId: Int?
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
                content: trimmed.isEmpty ? "" : customEmojiSpans(in: HTMLText.paragraphs(from: trimmed)),
                files: files.map(\.id),
                parentMessageId: parentMessageId,
                replyToMessageId: replyingTo?.id
            )
        )

        replyingTo = nil
    }

    // the server's own emoji are picked as :name:, the web client stores them as spans it can
    // draw, so a name that matches one becomes that span. other colons stay text
    private func customEmojiSpans(in html: String) -> String {
        guard
            !session.customEmojis.isEmpty,
            let pattern = try? NSRegularExpression(pattern: ":([A-Za-z0-9_]+):")
        else {
            return html
        }

        let names = Set(session.customEmojis.map(\.name))
        var result = html

        for match in pattern.matches(in: html, range: NSRange(html.startIndex..., in: html)).reversed() {
            guard
                let whole = Range(match.range, in: html),
                let nameRange = Range(match.range(at: 1), in: html),
                names.contains(String(html[nameRange]))
            else {
                continue
            }

            // the name stays inside as text, a message of one emoji is then not an empty one
            result.replaceSubrange(whole, with: "<span data-type=\"emoji\" data-name=\"\(html[nameRange])\">\(html[whole])</span>")
        }

        return result
    }

    // a gif goes as its link, which shows as the gif alone, a sticker as a message of its own.
    // neither touches what is being typed or replied to
    func sendExpression(content: String, stickerId: Int?) async throws {
        guard let client = session.client else {
            throw TRPCError(message: "Not connected to the server.", code: nil)
        }

        var parentMessageId: Int?

        if case .thread(let id) = scope {
            parentMessageId = id
        }

        try await client.mutation(
            "messages.send",
            input: SendInput(
                channelId: channelId,
                content: content,
                files: [],
                parentMessageId: parentMessageId,
                replyToMessageId: nil,
                stickerId: stickerId
            )
        )
    }

    func edit(_ message: Message, to text: String) async throws {
        guard let client = session.client else {
            throw TRPCError(message: "Not connected to the server.", code: nil)
        }

        struct EditInput: Encodable {
            let messageId: Int
            let content: String
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        try await client.mutation("messages.edit", input: EditInput(messageId: message.id, content: HTMLText.paragraphs(from: trimmed)))
        editing = nil
    }

    func delete(_ message: Message) async throws {
        guard let client = session.client else {
            throw TRPCError(message: "Not connected to the server.", code: nil)
        }

        try await client.mutation("messages.delete", input: ["messageId": message.id])
    }

    func markUnread(from message: Message) async throws {
        guard let client = session.client else {
            throw TRPCError(message: "Not connected to the server.", code: nil)
        }

        try await client.mutation("channels.markAsUnread", input: ["messageId": message.id])
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
