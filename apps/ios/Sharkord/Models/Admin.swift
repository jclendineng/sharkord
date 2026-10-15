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
struct AdminServerSettings: Codable, Equatable {
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
    // missing on a server from before the setting existed
    var pushShowMessageContent: Bool?
    var linkPreviewsPrivateNetwork: Bool?
    var reportEmail: String?
    var klipyApiKey: String?
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

// others.getStorageSettings
struct AdminStorage: Decodable {
    struct Settings: Codable, Equatable {
        var storageUploadEnabled: Bool
        var storageFileSharingInDirectMessages: Bool
        var storageQuota: Int
        var storageUploadMaxFileSize: Int
        var storageMaxAvatarSize: Int
        var storageMaxBannerSize: Int
        var storageMaxFilesPerMessage: Int
        var storageSpaceQuotaByUser: Int
        var storageOverflowAction: String
        var storageSignedUrlsTtlSeconds: Int
        var storageImageOptimizationEnabled: Bool
        var storageImageOptimizationQuality: Int
    }

    struct Disk: Decodable {
        let totalSpace: Int
        let usedSpace: Int
        let freeSpace: Int
        let sharkordUsedSpace: Int
    }

    struct PluginUsage: Decodable, Identifiable {
        let pluginId: String
        let fileCount: Int
        let usedSpace: Int
        let installed: Bool

        var id: String { pluginId }
    }

    let storageSettings: Settings
    let diskMetrics: Disk
    let pluginStorage: [PluginUsage]
}

// others.getUpdate
struct AdminUpdate: Decodable {
    let canUpdate: Bool
    let latestVersion: String
    let hasUpdate: Bool
    let currentVersion: String?
}

// plugins.get, TPluginInfo
struct AdminPlugin: Decodable, Identifiable, Hashable {
    let id: String
    let enabled: Bool
    let loadError: String?
    let sdkVersion: Int?
    let author: String?
    let description: String?
    let version: String?
    let logo: String?
    let name: String?
    let homepage: String?

    var title: String {
        name ?? id
    }
}

// a plugin setting holds a string, a number or a boolean
enum PluginSettingValue: Codable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        }
    }
}

// plugins.getSettings, TPluginSettingsResponse
struct AdminPluginSettings: Decodable {
    struct Option: Decodable, Hashable {
        let value: String
        let label: String
    }

    struct Definition: Decodable, Identifiable {
        let key: String
        let name: String
        let description: String?
        let type: String
        let defaultValue: PluginSettingValue
        let options: [Option]?

        var id: String { key }
    }

    let definitions: [Definition]
    let values: [String: PluginSettingValue?]
    let secretsSet: [String]
}

// plugins.getCapabilities, TPluginCapability
struct AdminPluginCapability: Decodable, Identifiable, Hashable {
    struct Access: Decodable, Hashable {
        let mode: String
        let roleIds: [Int]
    }

    let type: String
    let name: String
    let description: String?
    let configured: Bool
    let requires: String?
    let defaultAccess: Access
    let mode: String
    let roleIds: [Int]

    var id: String { "\(type):\(name)" }
}

// plugins.getLogs, TLogEntry
struct AdminPluginLog: Decodable, Hashable {
    let type: String
    let timestamp: Int
    let message: String
}

// the marketplace registry the web client reads, packages/shared plugins/marketplace.ts
struct MarketplaceEntry: Decodable, Identifiable {
    // PLUGIN_SDK_VERSION, a version built for another sdk is refused at load
    static let sdkVersion = 2
    static let registryURL = URL(string: "https://raw.githubusercontent.com/Sharkord/plugins/refs/heads/main/plugins.json?raw=true")!

    struct Plugin: Decodable {
        let id: String
        let name: String
        let description: String
        let author: String
        let logo: String
        let homepage: String?
        let tags: [String]?
        let verified: Bool
    }

    struct Version: Decodable {
        let version: String
        let sdkVersion: Int
        let size: Int
        let timestamp: Int
    }

    let plugin: Plugin
    let versions: [Version]

    var id: String { plugin.id }

    var latestCompatible: Version? {
        versions
            .filter { $0.sdkVersion == Self.sdkVersion }
            .max { $0.timestamp < $1.timestamp }
    }
}

// users.getInfo, what the web's mod view shows about a member
struct AdminUserInfo: Decodable {
    struct Login: Decodable, Identifiable {
        let id: Int
        let os: String?
        let device: String?
        let userAgent: String?
        // null without VIEW_USER_SENSITIVE_DATA
        let ip: String?
        let city: String?
        let region: String?
        let country: String?
        let createdAt: Int

        var place: String? {
            let parts = [city, region, country].compactMap { $0 }.filter { !$0.isEmpty }

            return parts.isEmpty ? nil : parts.joined(separator: ", ")
        }
    }

    struct Activity: Decodable, Identifiable {
        let id: Int
        let channelId: Int
        let content: String?
        let createdAt: Int
    }

    struct Storage: Decodable {
        let fileCount: Int
        let usedStorage: Int
        let quota: Int
    }

    let logins: [Login]
    let files: [SharkordFile]
    let messages: [Activity]
    let storage: Storage
}
