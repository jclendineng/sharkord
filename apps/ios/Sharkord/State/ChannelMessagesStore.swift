import Foundation
import Observation

// one list of messages: either a channel's top level messages or the replies of one thread
@Observable
final class ChannelMessagesStore {
    enum PendingJump: Equatable {
        case message(Int)
        case firstUnread
    }

    enum ComposerMode: Equatable {
        case composing
        case replying(Message)
        case editing(Message)
    }

    enum Scope: Hashable {
        case channel
        case thread(parentMessageId: Int)
    }

    let channelId: Int
    let scope: Scope

    // oldest first, the way the list renders them
    private(set) var messages: [Message] = []
    private(set) var hasOlder = false
    // showing a window around an older message, not the present: live messages wait until the
    // list goes back to the newest page
    private(set) var isDetached = false
    // the message a jump landed on, which the list scrolls to and lights up
    var focusedMessageId: Int?
    // a jump asked for from another screen, made when the chat next appears
    var pendingJumpMessageId: Int? {
        get {
            if case .message(let messageId) = pendingJump {
                return messageId
            }

            return nil
        }
        set {
            pendingJump = newValue.map { .message($0) }
        }
    }
    // a thread to open once the jump has brought its first message into the list, for a tapped
    // notification about a reply in it
    var pendingThreadParentId: Int?
    // the inbox's unreads open the chat at its first unread message, lit up
    var pendingJumpToFirstUnread: Bool {
        get {
            pendingJump == .firstUnread
        }
        set {
            pendingJump = newValue ? .firstUnread : nil
        }
    }
    private(set) var hasLoaded = false
    private(set) var isLoading = false
    var errorMessage: String?
    var isVisible = false
    // the composer's mode, set from a message's long press sheet
    private var pendingJump: PendingJump?
    var composerMode = ComposerMode.composing
    var replyingTo: Message? {
        if case .replying(let message) = composerMode {
            return message
        }

        return nil
    }
    var editing: Message? {
        if case .editing(let message) = composerMode {
            return message
        }

        return nil
    }
    // a mention the composer adds, from a member's or a message's menu
    var pendingMention: ComposerMention?
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

    // messages sent from here that show before the server has them, oldest first. a live
    // message of your own takes the place of the oldest one
    private(set) var pendingIds: [Int] = []
    private var nextPendingId = -1
    private var pendingNonces: [Int: String] = [:]

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
        var targetMessageId: Int?
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
        var clientNonce: String?
    }

    func loadIfNeeded() async {
        if let messageId = pendingJumpMessageId {
            pendingJumpMessageId = nil
            await jump(to: messageId)

            return
        }

        guard !hasLoaded else {
            return
        }

        await reload()
    }

    func reload() async {
        guard let page = await fetchPage(cursor: nil) else {
            return
        }

        pendingIds = []
        pendingNonces = [:]

        messages = Self.sorted(page.messages)
        nextCursor = page.nextCursor
        hasOlder = page.nextCursor != nil
        isDetached = false
        hasLoaded = true
    }

    // the window around a message, from media, files, pins or links. one already in the list
    // is only scrolled to
    func jump(to messageId: Int) async {
        guard case .channel = scope else {
            return
        }

        if !messages.contains(where: { $0.id == messageId }) {
            guard let page = await fetchPage(cursor: nil, targetMessageId: messageId) else {
                return
            }

            messages = Self.sorted(page.messages)
            nextCursor = page.nextCursor
            hasOlder = page.nextCursor != nil
            isDetached = page.hasNewer ?? false
            hasLoaded = true
        }

        focusedMessageId = messageId
    }

    // discord's "new messages since" bar: how many were unread when the chat opened, counted back
    // from the newest message there was then, so messages arriving after do not shift it
    struct UnreadMarker: Equatable {
        let count: Int
        let anchorMessageId: Int
    }

    var unreadMarker: UnreadMarker?

    func setUnreadMarker(count: Int) {
        guard count > 0, hasLoaded, !isDetached, let newest = messages.last else {
            unreadMarker = nil
            return
        }

        unreadMarker = UnreadMarker(count: count, anchorMessageId: newest.id)
    }

    // the first unread message, when it is loaded. the server's count leaves out the user's own
    // messages, so counting back steps over them: counted as well, one sent after the unread
    // ones put the divider and the jump that many messages too late
    var firstUnreadMessage: Message? {
        guard let unreadMarker, let anchor = messages.firstIndex(where: { $0.id == unreadMarker.anchorMessageId }) else {
            return nil
        }

        let ownUserId = session.ownUserId
        var remaining = unreadMarker.count

        for index in stride(from: anchor, through: 0, by: -1) where messages[index].userId != ownUserId {
            remaining -= 1

            if remaining == 0 {
                return messages[index]
            }
        }

        return nil
    }

    // older pages until the first unread one is in, then the list goes to it
    func jumpToFirstUnread() async {
        while firstUnreadMessage == nil, hasOlder, unreadMarker != nil {
            let before = messages.count

            await loadOlder()

            if messages.count == before {
                break
            }
        }

        focusedMessageId = firstUnreadMessage?.id ?? messages.first?.id
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

    func send(_ text: String, files: [TemporaryFile], mentions: [ComposerMention] = []) async throws {
        guard let client = session.client else {
            throw TRPCError(message: "Not connected to the server.", code: nil)
        }

        var parentMessageId: Int?

        if case .thread(let id) = scope {
            parentMessageId = id
        }

        // writing in the conversation means it has been caught up on, the bar has done its job
        unreadMarker = nil

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = trimmed.isEmpty ? "" : customEmojiSpans(in: HTMLText.messageHTML(fromMarkdown: trimmed, mentions: mentions))
        let replyTo = replyingTo
        // text alone shows at once. files have nothing to draw until the server has saved them,
        // and a slash command comes back as something else
        let clientNonce = UUID().uuidString
        let pendingId = files.isEmpty && !trimmed.hasPrefix("/") ? addPending(content: content, clientNonce: clientNonce, parentMessageId: parentMessageId, replyTo: replyTo) : nil

        composerMode = .composing

        let messageId: Int?

        do {
            messageId = try await client.mutation(
                "messages.send",
                input: SendInput(
                    channelId: channelId,
                    content: content,
                    files: files.map(\.id),
                    parentMessageId: parentMessageId,
                    replyToMessageId: replyTo?.id,
                    clientNonce: clientNonce
                )
            )
        } catch {
            if let pendingId {
                removePending(pendingId)
            }

            if composerMode == .composing, let replyTo {
                composerMode = .replying(replyTo)
            }

            throw error
        }

        guard let pendingId else {
            return
        }

        // the live message already took a placeholder's place, or never comes (a command
        // answered to you alone). otherwise the live message replaces it when it arrives
        guard let messageId, !messages.contains(where: { $0.id == messageId }) else {
            removePending(pendingId)

            return
        }

        // a live message lost on the way, the socket dropping as it came, would leave the
        // placeholder for good. the page from the server settles it, without holding up the
        // composer meanwhile
        Task {
            try? await Task.sleep(for: .seconds(10))

            if pendingIds.contains(pendingId) {
                await reload()
            }
        }
    }

    private func addPending(content: String, clientNonce: String, parentMessageId: Int?, replyTo: Message?) -> Int? {
        guard hasLoaded, !isDetached, let ownUserId = session.ownUserId else {
            return nil
        }

        let id = nextPendingId
        let now = Int(Date().timeIntervalSince1970 * 1000)
        // never before the newest message, whatever this device's clock says
        let createdAt = max(now, (messages.last?.createdAt ?? 0) + 1)

        nextPendingId -= 1
        pendingIds.append(id)
        pendingNonces[id] = clientNonce
        messages.append(Message(
            id: id,
            content: content,
            userId: ownUserId,
            pluginId: nil,
            webhookName: nil,
            channelId: channelId,
            parentMessageId: parentMessageId,
            replyToMessageId: replyTo?.id,
            createdAt: createdAt,
            editedAt: nil,
            files: [],
            reactions: [],
            replyTo: replyTo.map { ReplyPreview(id: $0.id, content: $0.content, userId: $0.userId, pluginId: $0.pluginId) }
        ))

        return id
    }

    private func removePending(_ id: Int) {
        pendingIds.removeAll { $0 == id }
        pendingNonces[id] = nil
        messages.removeAll { $0.id == id }
    }

    func isPending(_ message: Message) -> Bool {
        message.id < 0
    }

    // built once, rather than for every message sent
    private static let emojiPattern = try? NSRegularExpression(pattern: ":([A-Za-z0-9_]+):")

    // the server's own emoji are picked as :name:, the web client stores them as spans it can
    // draw, so a name that matches one becomes that span. other colons stay text
    private func customEmojiSpans(in html: String) -> String {
        guard
            !session.customEmojis.isEmpty,
            let pattern = Self.emojiPattern
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

    func edit(_ message: Message, to text: String, mentions: [ComposerMention]) async throws {
        guard let client = session.client else {
            throw TRPCError(message: "Not connected to the server.", code: nil)
        }

        struct EditInput: Encodable {
            let messageId: Int
            let content: String
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        try await client.mutation("messages.edit", input: EditInput(messageId: message.id, content: HTMLText.messageHTML(fromMarkdown: trimmed, mentions: mentions)))
        composerMode = .composing
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
        guard hasLoaded, !isDetached, belongs(message) else {
            return
        }

        // matched by the nonce it was sent with. a copy without one, from a server or an app older
        // than the nonce, takes the oldest
        let matchingPending = message.clientNonce == nil
            ? pendingIds.first
            : pendingIds.first { pendingNonces[$0] == message.clientNonce }

        if let pendingId = matchingPending,
           message.userId == session.ownUserId,
           !messages.contains(where: { $0.id == message.id }) {
            removePending(pendingId)
        }

        // live messages arrive in order, so appending is the common case. sorting the whole
        // page on every message made a busy channel re-order fifty rows per event
        if let last = messages.last,
           last.id != message.id,
           (last.createdAt, last.id) < (message.createdAt, message.id) {
            messages.append(message)

            return
        }

        guard !messages.contains(where: { $0.id == message.id }) else {
            return
        }

        messages = Self.sorted(messages + [message])
    }

    func update(_ message: Message) {
        guard let index = messages.firstIndex(where: { $0.id == message.id }) else {
            return
        }

        var message = message

        settlePendingReactions(on: &message)
        messages[index] = message
    }

    // reactions tapped here, by message and emoji, that show before the server has them: each
    // says whether your own should be there. a later update that agrees settles it, one that
    // doesn't yet (someone else's reaction arriving first) keeps it showing
    private var pendingReactions: [Int: [String: Bool]] = [:]

    func setPendingReaction(_ emoji: String, isMine: Bool, on messageId: Int) {
        guard let index = messages.firstIndex(where: { $0.id == messageId }) else {
            return
        }

        pendingReactions[messageId, default: [:]][emoji] = isMine
        apply(emoji, isMine: isMine, to: &messages[index])
    }

    // a refused toggle goes back to what the server last said
    func dropPendingReaction(_ emoji: String, on messageId: Int, serverReactions: [MessageReaction]) {
        pendingReactions[messageId]?[emoji] = nil

        guard let index = messages.firstIndex(where: { $0.id == messageId }) else {
            return
        }

        messages[index].reactions = serverReactions
        settlePendingReactions(on: &messages[index])
    }

    private func settlePendingReactions(on message: inout Message) {
        guard let pending = pendingReactions[message.id], let ownUserId = session.ownUserId else {
            return
        }

        for (emoji, isMine) in pending {
            let isMineOnServer = message.reactions.contains { $0.emoji == emoji && $0.userId == ownUserId }

            if isMineOnServer == isMine {
                pendingReactions[message.id]?[emoji] = nil
            } else {
                apply(emoji, isMine: isMine, to: &message)
            }
        }
    }

    private func apply(_ emoji: String, isMine: Bool, to message: inout Message) {
        guard let ownUserId = session.ownUserId else {
            return
        }

        let existing = message.reactions.first { $0.emoji == emoji }

        message.reactions.removeAll { $0.emoji == emoji && $0.userId == ownUserId }

        if isMine {
            message.reactions.append(MessageReaction(userId: ownUserId, emoji: emoji, file: existing?.file))
        }
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

    private func fetchPage(cursor: MessagesCursor?, targetMessageId: Int? = nil) async -> MessagesPage? {
        guard !isLoading else {
            return nil
        }

        isLoading = true
        defer { isLoading = false }

        do {
            // a launch draws the chat from the last join before the sign in is through, the
            // first page waits for it rather than being turned away as unauthenticated
            let client = try await session.readyClient()
            let page: MessagesPage

            switch scope {
            case .channel:
                page = try await client.query(
                    "messages.get",
                    input: ChannelPageInput(channelId: channelId, cursor: cursor, targetMessageId: targetMessageId)
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
