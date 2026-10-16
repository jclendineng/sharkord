import Foundation

// packages/shared tables.ts TJoinedSoundboardSound
struct SoundboardSound: Codable, Hashable, Identifiable {
    let id: Int
    let name: String
    let emoji: String?
    // a percentage, packages/shared statics/soundboard.ts SOUND_MAX_VOLUME
    let volume: Int
    // set on a sound picked from the server's library
    let libraryKey: String?
    let file: SharkordFile
}

// soundboard.getLibrary: the sounds the server ships with, to pick from
struct SoundboardLibrarySound: Codable, Hashable, Identifiable {
    let key: String
    let name: String
    let emoji: String

    var id: String {
        key
    }
}

// voice.onSound, sent to everyone and played only by the apps in that call
struct VoiceSoundEvent: Decodable {
    let channelId: Int
    let userId: Int
    let soundId: Int
}
