import Foundation

// messages.search, over the channels and direct messages the caller can see
struct SearchResults: Decodable {
    let messages: [SearchMessage]
    let files: [SearchFile]
    let truncated: Bool
}

struct SearchMessage: Decodable, Identifiable {
    let id: Int
    let channelId: Int
    let userId: Int?
    let createdAt: Int
    let channelName: String
    let channelIsDm: Bool
    let plainContent: String
    // the html, which still holds the links plainContent drops
    let content: String?

    // every web link in it, in order and each once
    var links: [URL] {
        guard let content else {
            return []
        }

        let matches = content.matches(of: /href="(https?:[^"]+)"/)
        var seen = Set<String>()

        return matches.compactMap { match in
            let raw = String(match.1).replacingOccurrences(of: "&amp;", with: "&")

            guard seen.insert(raw).inserted else {
                return nil
            }

            return URL(string: raw)
        }
    }

    var createdDate: Date {
        Date(timeIntervalSince1970: TimeInterval(createdAt) / 1000)
    }
}

struct SearchFile: Decodable, Identifiable {
    let file: SharkordFile
    let messageId: Int
    let channelId: Int
    let channelName: String
    let messageCreatedAt: Int?

    // the same file can be attached to more than one message
    var id: String { "\(messageId)-\(file.id)" }
}

// channels.getActivity
struct ChannelActivity: Decodable {
    let channelId: Int
    let lastMessageAt: Int
}

struct Invite: Decodable {
    let code: String
}

// messages.getMentions
struct MentionsPage: Decodable {
    let messages: [Message]
    let nextCursor: MessagesCursor?
}

// messages.search's filters, chosen from the search screen's filter menu
struct SearchFilters: Hashable {
    // discord's has: list, the kinds messages.search can tell apart
    enum Has: String, CaseIterable {
        case image
        case video
        case link
        case file
        case poll
        case sticker

        var title: String {
            rawValue.capitalized
        }

        var symbol: String {
            switch self {
            case .image:
                "photo.fill"
            case .video:
                "video.fill"
            case .link:
                "link"
            case .file:
                "paperclip"
            case .poll:
                "text.alignleft"
            case .sticker:
                "seal.fill"
            }
        }
    }

    var from: PublicUser?
    var channel: Channel?
    var mentions: PublicUser?
    var has: Has?
    var on: Date?
    var before: Date?
    var after: Date?

    var isEmpty: Bool {
        self == SearchFilters()
    }
}

// what goes to the server, nil fields are left out of the json
struct SearchInput: Encodable {
    let query: String?
    let fromUserId: Int?
    let channelId: Int?
    let mentionsUserId: Int?
    let has: String?
    let before: Int?
    let after: Int?
    let on: Int?

    init(query: String?, filters: SearchFilters) {
        let calendar = Calendar.current
        let milliseconds = { (date: Date) in Int(date.timeIntervalSince1970 * 1000) }

        self.query = query
        fromUserId = filters.from?.id
        channelId = filters.channel?.id
        mentionsUserId = filters.mentions?.id
        has = filters.has?.rawValue
        // whole days in the phone's own time zone
        before = filters.before.map { milliseconds(calendar.startOfDay(for: $0)) }
        after = filters.after.map { milliseconds(calendar.startOfDay(for: $0).addingTimeInterval(86_400)) - 1 }
        on = filters.on.map { milliseconds(calendar.startOfDay(for: $0)) }
    }
}
