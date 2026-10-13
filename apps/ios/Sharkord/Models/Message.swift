import Foundation

struct MessageReaction: Codable, Hashable {
    let userId: Int?
    let emoji: String
    // set for custom emoji, which wins over a built-in of the same name
    let file: SharkordFile?
}

struct Message: Codable, Hashable, Identifiable {
    let id: Int
    let content: String?
    let userId: Int?
    let pluginId: String?
    let channelId: Int
    let parentMessageId: Int?
    let createdAt: Int
    let editedAt: Int?
    let files: [SharkordFile]
    let reactions: [MessageReaction]
    var replyCount: Int?

    var createdDate: Date {
        Date(timeIntervalSince1970: TimeInterval(createdAt) / 1000)
    }
}

struct MessagesCursor: Codable, Hashable {
    let createdAt: Int
    let id: Int
}

struct MessagesPage: Decodable {
    let messages: [Message]
    let nextCursor: MessagesCursor?
}

struct MessageDeletedEvent: Decodable {
    let messageId: Int
    let channelId: Int
}

struct ThreadReplyCountUpdate: Decodable {
    let messageId: Int
    let channelId: Int
    let replyCount: Int
}

// what POST /upload returns, its id is what messages.send takes in files
struct TemporaryFile: Decodable, Hashable {
    let id: String
    let originalName: String
    let size: Int
}
