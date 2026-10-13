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

// voice.onReaction
struct VoiceReactionEvent: Decodable {
    let channelId: Int
    let userId: Int
    let emoji: String
}

// one emoji floating over someone's tile for a moment
struct VoiceReaction: Identifiable, Hashable {
    let id: Int
    let emoji: String
}

struct VoiceMovedEvent: Decodable {
    let channelId: Int
    let fromChannelId: Int
}

struct RemoteProducers: Decodable {
    let remoteAudioIds: [Int]
    let remoteVideoIds: [Int]
    let remoteScreenIds: [Int]
    let remoteScreenAudioIds: [Int]

    var keys: [VoiceStreamKey] {
        remoteAudioIds.map { VoiceStreamKey(kind: .audio, remoteId: $0) }
            + remoteVideoIds.map { VoiceStreamKey(kind: .video, remoteId: $0) }
            + remoteScreenIds.map { VoiceStreamKey(kind: .screen, remoteId: $0) }
            + remoteScreenAudioIds.map { VoiceStreamKey(kind: .screenAudio, remoteId: $0) }
    }
}

struct VoiceProducerEvent: Decodable {
    let channelId: Int
    let remoteId: Int
    let kind: String
}
