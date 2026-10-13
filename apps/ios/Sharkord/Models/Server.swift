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
    let roles: [Role]
    let emojis: [CustomEmoji]
    let publicSettings: PublicSettings
    // keyed by channel id, sent as strings since it is a JSON object
    let readStates: [String: Int]
    let voiceMap: [String: VoiceChannelUsers]
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
}

struct Role: Decodable, Hashable, Identifiable {
    let id: Int
    let name: String
    let color: String
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

    var id: Int { channelId }
}

struct OpenedDirectMessage: Decodable {
    let channelId: Int
}
