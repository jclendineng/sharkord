import Foundation

struct SharkordFile: Codable, Hashable, Identifiable {
    let id: Int
    let name: String
    let originalName: String
    let size: Int
    let mimeType: String
    let accessToken: String?
    let accessTokenExpiresAt: Int?

    var isImage: Bool {
        mimeType.hasPrefix("image/")
    }

    var isAudio: Bool {
        mimeType.hasPrefix("audio/") || ["m4a", "mp3", "aac", "wav", "ogg", "flac"].contains((name as NSString).pathExtension.lowercased())
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, originalName, size, mimeType
        case accessToken = "_accessToken"
        case accessTokenExpiresAt = "_accessTokenExpiresAt"
    }
}
