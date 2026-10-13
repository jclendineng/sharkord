import Foundation
import Security

// where the broadcast extension finds the app: a loopback port and a secret, kept in a
// keychain group both targets share. the extension proves it is ours with the secret, so no
// other app on the phone can feed frames into a screen share.
// SharkordBroadcast/ScreenShareEndpoint.swift is the extension's copy, keep the two in step
nonisolated struct ScreenShareEndpoint: Codable, Sendable {
    let port: UInt16
    let secret: String
    // the stream settings sheet's choice, how large and how often the extension sends frames
    var maxDimension: Int
    var framesPerSecond: Int
    // only when the call was joined with MixingAudioDevice, which is what can carry it
    var shareAudio: Bool

    private static let service = "com.sharkord.screen-share"
    private static let account = "endpoint"

    private static var accessGroup: String? {
        Bundle.main.object(forInfoDictionaryKey: "SharkordKeychainGroup") as? String
    }

    private static func baseQuery() -> [String: Any]? {
        guard let accessGroup else {
            return nil
        }

        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup
        ]
    }

    static func load() -> ScreenShareEndpoint? {
        guard var query = baseQuery() else {
            return nil
        }

        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?

        guard
            SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
            let data = item as? Data
        else {
            return nil
        }

        return try? JSONDecoder().decode(ScreenShareEndpoint.self, from: data)
    }

    func save() {
        guard var query = Self.baseQuery(), let data = try? JSONEncoder().encode(self) else {
            return
        }

        Self.delete()
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }

    static func delete() {
        if let query = baseQuery() {
            SecItemDelete(query as CFDictionary)
        }
    }
}
