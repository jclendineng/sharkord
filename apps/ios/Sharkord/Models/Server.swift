import Foundation

struct ServerInfo: Decodable {
    let serverId: String
    let name: String
    let description: String?
    let allowNewUsers: Bool
    let logo: SharkordFile?
    // optional so servers from before oidc still decode
    let oidcEnabled: Bool?
    let oidcDisableLocalLogin: Bool?
    let pushEnabled: Bool?
    // where reports about the server or a message on it go, set by its admins
    let reportEmail: String?
}

struct Handshake: Decodable {
    let handshakeHash: String
    let hasPassword: Bool
}

struct JoinResult: Decodable {
    let categories: [ChannelCategory]
    let channels: [Channel]
    let users: [PublicUser]
    let serverId: String
    let serverName: String
    let ownUserId: Int
    // missing on a server from before the about page asked for it
    let serverVersion: String?
    // false for an account made through sso, which has no password to confirm with
    let ownUserPasswordSet: Bool?
    let roles: [Role]
    let emojis: [CustomEmoji]
    let stickers: [Sticker]?
    // missing on a server from before the soundboard
    let sounds: [SoundboardSound]?
    let publicSettings: PublicSettings
    // this account's resolved permissions in each channel, keyed by channel id
    let channelPermissions: [String: ChannelPermissions]?
    // keyed by channel id, sent as strings since it is a JSON object
    let readStates: [String: Int]
    let voiceMap: [String: VoiceChannelUsers]
}

// one channel's entry in the join payload and in channels.onPermissionsUpdate
struct ChannelPermissions: Decodable {
    let channelId: Int
    let permissions: [String: Bool]
}

struct ReadStateUpdate: Decodable {
    let channelId: Int
    let count: Int
}

struct ReadStateDelta: Decodable {
    let channelId: Int
    let delta: Int
}

struct PublicSettings: Decodable {
    let storageUploadEnabled: Bool
    let directMessagesEnabled: Bool
    let storageUploadMaxFileSize: Int
    let storageFileSharingInDirectMessages: Bool
    let storageMaxFilesPerMessage: Int
    // missing on a server from before gifs
    let gifsEnabled: Bool?
    // missing on a server from before freesound search
    let soundSearchEnabled: Bool?
    // the rules message members react to for access, missing from an older server
    let onboardingMessageId: Int?
    // whether cameras send several qualities for viewers to pick from, missing from an older server
    let webRtcSimulcastEnabled: Bool?
}

struct Role: Decodable, Hashable, Identifiable {
    let id: Int
    let name: String
    let color: String
    // optional so a role from an event without them still decodes
    let permissions: [String]?
    // missing on a server from before roles had an order
    let position: Int?
    let isDefault: Bool?

    // discord's order: the owner's role first, the default one last, the rest as arranged
    static func ranksAbove(_ lhs: Role, _ rhs: Role) -> Bool {
        let lhsKey = (lhs.isDefault == true ? 1 : 0, lhs.id == 1 ? 0 : 1, lhs.position ?? lhs.id, lhs.id)
        let rhsKey = (rhs.isDefault == true ? 1 : 0, rhs.id == 1 ? 0 : 1, rhs.position ?? rhs.id, rhs.id)

        return lhsKey < rhsKey
    }
}

struct CustomEmoji: Decodable, Hashable, Identifiable {
    let id: Int
    let name: String
    let file: SharkordFile
}

struct DirectMessageConversation: Decodable, Hashable, Identifiable {
    let channelId: Int
    let userId: Int
    let lastMessageAt: Int
    // the newest message as plain text and who sent it, missing from an older server
    var lastMessagePreview: String?
    var lastMessageUserId: Int?
    // a group conversation, missing for two people and from an older server
    var group: GroupInfo?

    var id: Int { channelId }
}

struct GroupInfo: Decodable, Hashable {
    let name: String?
    // everyone in it but you
    let memberIds: [Int]
}

// discord's bounds for a group, packages/shared statics/dms.ts
enum GroupLimits {
    static let maxMembers = 10
    static let maxNameLength = 100
}

// friends.get: user ids
struct FriendLists: Decodable, Equatable {
    var friends: [Int] = []
    // asked by them, waiting on you
    var incoming: [Int] = []
    // asked by you, waiting on them
    var outgoing: [Int] = []
}

struct FriendshipUpdate: Decodable {
    let userId: Int
}

// where someone stands with you, for their profile's friend button
enum FriendStatus {
    case none
    case friends
    case incoming
    case outgoing
}

struct OpenedDirectMessage: Decodable {
    let channelId: Int
}

// sessions.getAll, one signed in device
struct DeviceSession: Decodable, Identifiable, Hashable {
    let id: String
    let os: String?
    let device: String?
    let ip: String?
    let city: String?
    let region: String?
    let country: String?
    let createdAt: Int
    let lastActiveAt: Int
    let isCurrent: Bool

    var lastActiveDate: Date {
        Date(timeIntervalSince1970: TimeInterval(lastActiveAt) / 1000)
    }
}

struct RefreshedToken: Decodable {
    let token: String
}

struct RevokedSessions: Decodable {
    let revokedCount: Int
}
