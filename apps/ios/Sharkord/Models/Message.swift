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
    let replyToMessageId: Int?
    let createdAt: Int
    let editedAt: Int?
    let files: [SharkordFile]
    let reactions: [MessageReaction]
    // missing from a server without polls
    var poll: Poll?
    var sticker: Sticker?
    // link previews the server worked out, a gif's link is one
    var metadata: [MessageMetadata]?
    var replyCount: Int?
    var pinned: Bool?
    var pinnedAt: Int?
    var pinnedBy: Int?
    // the message this one answers, or nil when it was deleted since
    let replyTo: ReplyPreview?

    var createdDate: Date {
        Date(timeIntervalSince1970: TimeInterval(createdAt) / 1000)
    }
}

struct ReplyPreview: Codable, Hashable {
    let id: Int
    let content: String?
    let userId: Int?
    let pluginId: String?
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

// messages.onTyping
struct TypingEvent: Decodable {
    let channelId: Int
    let userId: Int
    let parentMessageId: Int?
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

// polls.create, a message's poll with who picked each answer
struct Poll: Codable, Hashable {
    struct Answer: Codable, Hashable, Identifiable {
        let id: Int
        let text: String
        let emoji: String?
        let userIds: [Int]
    }

    let question: String
    let allowMultiple: Bool
    let expiresAt: Int
    let endedAt: Int?
    let answers: [Answer]

    var expiresDate: Date {
        Date(timeIntervalSince1970: TimeInterval(expiresAt) / 1000)
    }

    func isClosed(at now: Date = .now) -> Bool {
        endedAt != nil || expiresDate <= now
    }

    var voterCount: Int {
        Set(answers.flatMap(\.userIds)).count
    }

    func votes(of userId: Int?) -> Set<Int> {
        guard let userId else {
            return []
        }

        return Set(answers.filter { $0.userIds.contains(userId) }.map(\.id))
    }
}

// a server sticker, sent as a message of its own
struct Sticker: Codable, Hashable, Identifiable {
    let id: Int
    let name: String
    let description: String?
    let file: SharkordFile
}

// what the server found at a link in a message: the media itself, or a page's preview
struct MessageMetadata: Codable, Hashable {
    let kind: String
    let url: String
    let mediaType: String?
    let title: String?
    let siteName: String?
    let description: String?
    let images: [String]?

    var isImage: Bool {
        kind == "media" && mediaType == "image"
    }

    // a page's preview with something to show, a title or a picture
    var isLinkPreview: Bool {
        kind == "open_graph" && (title?.isEmpty == false || images?.isEmpty == false)
    }
}

extension Message {
    // gifs and images the server found at links in the message
    var mediaImages: [MessageMetadata] {
        (metadata ?? []).filter(\.isImage)
    }

    var linkPreviews: [MessageMetadata] {
        (metadata ?? []).filter(\.isLinkPreview)
    }

    // a message that is just the link to the gif it shows, like one from the picker: the gif
    // says it all, the link above it would only repeat it
    var isMediaLinkOnly: Bool {
        let images = mediaImages

        guard images.count == 1, let content else {
            return false
        }

        return HTMLText.plainText(from: content).trimmingCharacters(in: .whitespacesAndNewlines) == images[0].url
    }
}

// gifs.trending and gifs.search
struct Gif: Decodable, Hashable, Identifiable {
    let id: String
    let title: String
    let url: String
    let previewUrl: String
    let width: Double
    let height: Double
}

struct GifPage: Decodable {
    let gifs: [Gif]
    let hasMore: Bool
}

// gifs.categories, a tile and the search it runs
struct GifCategory: Decodable, Hashable, Identifiable {
    let term: String
    let previewUrl: String

    var id: String { term }
}
