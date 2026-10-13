import Foundation
import Security

// server urls are not secret and live in UserDefaults, session tokens go to the keychain
enum CredentialStore {
    private static let serverURLsKey = "serverURLs"
    // the single server the app held before it could hold several
    private static let legacyServerURLKey = "serverURL"
    private static let lastChannelKeyPrefix = "lastChannel."
    private static let tokenService = "com.sharkord.ios.token"

    static var serverURLs: [String] {
        get {
            if let urls = UserDefaults.standard.stringArray(forKey: serverURLsKey) {
                return urls
            }

            return UserDefaults.standard.string(forKey: legacyServerURLKey).map { [$0] } ?? []
        }
        set {
            UserDefaults.standard.set(newValue, forKey: serverURLsKey)
            UserDefaults.standard.removeObject(forKey: legacyServerURLKey)
        }
    }

    static func lastChannelId(for address: ServerAddress) -> Int? {
        UserDefaults.standard.object(forKey: lastChannelKeyPrefix + address.baseURL.absoluteString) as? Int
    }

    static func setLastChannelId(_ channelId: Int?, for address: ServerAddress) {
        UserDefaults.standard.set(channelId, forKey: lastChannelKeyPrefix + address.baseURL.absoluteString)
    }

    static func token(for address: ServerAddress) -> String? {
        var query = baseQuery(address)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?

        guard
            SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
            let data = item as? Data
        else {
            return nil
        }

        return String(decoding: data, as: UTF8.self)
    }

    static func save(token: String, for address: ServerAddress) {
        deleteToken(for: address)

        var query = baseQuery(address)
        query[kSecValueData as String] = Data(token.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        SecItemAdd(query as CFDictionary, nil)
    }

    static func deleteToken(for address: ServerAddress) {
        SecItemDelete(baseQuery(address) as CFDictionary)
    }

    private static func baseQuery(_ address: ServerAddress) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: tokenService,
            kSecAttrAccount as String: address.baseURL.absoluteString
        ]
    }
}
