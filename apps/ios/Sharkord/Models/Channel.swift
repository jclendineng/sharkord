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

// notifications.getChannelSettings. mentions is the default, a channel without a row
enum ChannelNotificationLevel: String, Codable, CaseIterable {
    case all
    case mentions
    case none
}

struct ChannelNotificationSetting: Codable {
    let channelId: Int
    let level: ChannelNotificationLevel
}

struct PrivacySettings: Codable {
    let allowDirectMessages: Bool
}
