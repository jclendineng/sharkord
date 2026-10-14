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
    // a mute for a while ends here, in milliseconds. missing on an older server
    var mutedUntil: Int?
}

// discord's mute lengths, nil is until it is turned back on
enum MuteDuration: CaseIterable, Identifiable {
    case minutes15
    case hour1
    case hours3
    case hours8
    case hours24
    case forever

    var id: Self { self }

    var minutes: Int? {
        switch self {
        case .minutes15: 15
        case .hour1: 60
        case .hours3: 3 * 60
        case .hours8: 8 * 60
        case .hours24: 24 * 60
        case .forever: nil
        }
    }

    var title: String {
        switch self {
        case .minutes15: "For 15 Minutes"
        case .hour1: "For 1 Hour"
        case .hours3: "For 3 Hours"
        case .hours8: "For 8 Hours"
        case .hours24: "For 24 Hours"
        case .forever: "Until I turn it back on"
        }
    }
}

struct PrivacySettings: Codable {
    let allowDirectMessages: Bool
}
