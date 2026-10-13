import Foundation

// the server settings screens, see apps/server/src/routers/{others,roles,users,invites}

// packages/shared statics/permissions.ts
enum Permission: String, CaseIterable, Codable {
    case sendMessages = "SEND_MESSAGES"
    case reactToMessages = "REACT_TO_MESSAGES"
    case pinMessages = "PIN_MESSAGES"
    case uploadFiles = "UPLOAD_FILES"
    case joinVoiceChannels = "JOIN_VOICE_CHANNELS"
    case shareScreen = "SHARE_SCREEN"
    case enableWebcam = "ENABLE_WEBCAM"
    case sendVoiceReaction = "SEND_VOICE_REACTION"
    case manageChannels = "MANAGE_CHANNELS"
    case manageChannelPermissions = "MANAGE_CHANNEL_PERMISSIONS"
    case manageCategories = "MANAGE_CATEGORIES"
    case manageRoles = "MANAGE_ROLES"
    case manageEmojis = "MANAGE_EMOJIS"
    case manageSettings = "MANAGE_SETTINGS"
    case manageUsers = "MANAGE_USERS"
    case moveMembers = "MOVE_MEMBERS"
    case manageMessages = "MANAGE_MESSAGES"
    case manageStorage = "MANAGE_STORAGE"
    case manageInvites = "MANAGE_INVITES"
    case manageUpdates = "MANAGE_UPDATES"
    case managePlugins = "MANAGE_PLUGINS"
    case managePluginPermissions = "MANAGE_PLUGIN_PERMISSIONS"
    case usePlugins = "USE_PLUGINS"
    case viewUserSensitiveData = "VIEW_USER_SENSITIVE_DATA"

    var title: String {
        rawValue
            .split(separator: "_")
            .map { $0.prefix(1) + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    var isAdmin: Bool {
        rawValue.hasPrefix("MANAGE_") || self == .moveMembers || self == .viewUserSensitiveData
    }
}

// roles.getAll
struct AdminRole: Codable, Identifiable, Hashable {
    let id: Int
    var name: String
    var color: String
    let isPersistent: Bool
    let isDefault: Bool
    var permissions: [Permission]
    let storageQuotaOverrideEnabled: Bool
    let storageSpaceQuota: Int
}

// others.getSettings, the general part of it
struct AdminServerSettings: Codable {
    var name: String
    var description: String?
    var password: String?
    var onlyAskForPasswordOnFirstJoin: Bool
    var allowNewUsers: Bool
    var directMessagesEnabled: Bool
    var enablePlugins: Bool
    var enableSearch: Bool
    var showWelcomeDialog: Bool
    var webRtcSimulcastEnabled: Bool
}

// users.getAll
struct AdminUser: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let identity: String?
    let banned: Bool
    let banReason: String?
    let roleIds: [Int]
    let avatar: SharkordFile?
    let createdAt: Int
    let lastLoginAt: Int?

    var isDeletedPlaceholder: Bool {
        name == "__deleted_user__"
    }
}

// invites.getAll
struct AdminInvite: Decodable, Identifiable, Hashable {
    struct Creator: Decodable, Hashable {
        let id: Int
        let name: String
    }

    struct InviteRole: Decodable, Hashable {
        let id: Int
        let name: String
        let color: String
    }

    let id: Int
    let code: String
    let uses: Int
    let maxUses: Int?
    let expiresAt: Int?
    let createdAt: Int
    let creator: Creator?
    let role: InviteRole?

    var isExpired: Bool {
        expiresAt.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) < .now } ?? false
    }
}
