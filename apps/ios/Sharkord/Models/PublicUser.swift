import Foundation

enum UserStatus: String, Codable {
    case online
    case idle
    case offline
}

struct PublicUser: Codable, Hashable, Identifiable {
    // the account a deleted user's messages are moved to, DELETED_USER_IDENTITY_AND_NAME
    private static let deletedPlaceholderName = "__deleted_user__"

    let id: Int
    let name: String
    let profileColor: String
    let bio: String?
    let avatar: SharkordFile?
    let banner: SharkordFile?
    var status: UserStatus?
    let roleIds: [Int]
    // optional so a server that leaves it out still decodes
    let createdAt: Int?
    let banned: Bool?
    let isDeleted: Bool

    var memberSince: Date? {
        createdAt.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }
    }

    // a real member, not the deleted user placeholder or someone banned
    var isMember: Bool {
        !isDeleted && banned != true
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, profileColor, bio, avatar, banner, status, roleIds, createdAt, banned
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawName = try container.decode(String.self, forKey: .name)

        id = try container.decode(Int.self, forKey: .id)
        isDeleted = rawName == Self.deletedPlaceholderName
        name = isDeleted ? "Deleted User" : rawName
        profileColor = try container.decode(String.self, forKey: .profileColor)
        bio = try container.decodeIfPresent(String.self, forKey: .bio)
        avatar = try container.decodeIfPresent(SharkordFile.self, forKey: .avatar)
        banner = try container.decodeIfPresent(SharkordFile.self, forKey: .banner)
        status = try container.decodeIfPresent(UserStatus.self, forKey: .status)
        roleIds = try container.decode([Int].self, forKey: .roleIds)
        createdAt = try container.decodeIfPresent(Int.self, forKey: .createdAt)
        banned = try container.decodeIfPresent(Bool.self, forKey: .banned)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(isDeleted ? Self.deletedPlaceholderName : name, forKey: .name)
        try container.encode(profileColor, forKey: .profileColor)
        try container.encodeIfPresent(bio, forKey: .bio)
        try container.encodeIfPresent(avatar, forKey: .avatar)
        try container.encodeIfPresent(banner, forKey: .banner)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encode(roleIds, forKey: .roleIds)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(banned, forKey: .banned)
    }
}

// users.onDelete
struct UserDeletedEvent: Decodable {
    let userId: Int
}
