import Foundation

// messages.search, which only looks through server channels, never direct messages
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
    let plainContent: String

    var createdDate: Date {
        Date(timeIntervalSince1970: TimeInterval(createdAt) / 1000)
    }
}

struct SearchFile: Decodable, Identifiable {
    let file: SharkordFile
    let messageId: Int
    let channelId: Int
    let channelName: String

    // the same file can be attached to more than one message
    var id: String { "\(messageId)-\(file.id)" }
}

struct Invite: Decodable {
    let code: String
}
