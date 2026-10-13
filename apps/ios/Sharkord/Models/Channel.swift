import Foundation

enum ChannelType: String, Codable {
    case text = "TEXT"
    case voice = "VOICE"
}

struct ChannelCategory: Codable, Hashable, Identifiable {
    let id: Int
    let name: String
    let position: Int
}

struct Channel: Codable, Hashable, Identifiable {
    let id: Int
    let type: ChannelType
    let name: String
    let topic: String?
    let `private`: Bool
    let isDm: Bool
    let position: Int
    let categoryId: Int?
}
