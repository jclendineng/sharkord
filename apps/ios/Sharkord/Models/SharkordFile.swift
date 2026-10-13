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

    private enum CodingKeys: String, CodingKey {
        case id, name, originalName, size, mimeType
        case accessToken = "_accessToken"
        case accessTokenExpiresAt = "_accessTokenExpiresAt"
    }
}
