import Foundation

struct VoiceUserState: Codable, Hashable {
    var micMuted: Bool
    var soundMuted: Bool
    var webcamEnabled: Bool
    var sharingScreen: Bool
}

// keyed by user id, sent as strings since it is a JSON object
struct VoiceChannelUsers: Decodable {
    let users: [String: VoiceUserState]
}

struct VoiceJoinEvent: Decodable {
    let channelId: Int
    let userId: Int
    let state: VoiceUserState
}

struct VoiceLeaveEvent: Decodable {
    let channelId: Int
    let userId: Int
}

struct VoiceMovedEvent: Decodable {
    let channelId: Int
    let fromChannelId: Int
}

struct RemoteProducers: Decodable {
    let remoteAudioIds: [Int]
}

struct VoiceProducerEvent: Decodable {
    let channelId: Int
    let remoteId: Int
    let kind: String
}
