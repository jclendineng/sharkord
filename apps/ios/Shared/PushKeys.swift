import CryptoKit
import Foundation
import Security

// the p-256 key each server encrypts this device's relay notifications to, one per server so a
// mixed up ticket can never show one server's notification as another's. kept in the keychain
// group the notification extension shares, readable after the first unlock so a push that
// arrives on a locked phone still opens. built into the app and the extension both
nonisolated enum PushKeys {
    private static let service = "com.sharkord.ios.push-key"
    // the same as the server's in utils/push-encryption.ts
    private static let info = Data("sharkord push v1".utf8)
    private static let ephemeralKeyLength = 65

    // the public half as the server takes it: x963, unpadded base64url
    static func encryptionKey(for serverId: String) -> String? {
        if let key = privateKey(for: serverId) {
            return base64URL(key.publicKey.x963Representation)
        }

        let key = P256.KeyAgreement.PrivateKey()
        var query = baseQuery(account: serverId)

        query[kSecValueData as String] = key.rawRepresentation
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else {
            return nil
        }

        return base64URL(key.publicKey.x963Representation)
    }

    static func delete(for serverId: String) {
        SecItemDelete(baseQuery(account: serverId) as CFDictionary)
    }

    // the payload the server sealed, tried against every server's key: the push names no server,
    // so that the relay and apple cannot tell them apart, and only the right key opens it
    static func open(_ encrypted: String) -> Data? {
        guard
            let bytes = data(base64URL: encrypted),
            bytes.count > ephemeralKeyLength,
            let ephemeral = try? P256.KeyAgreement.PublicKey(x963Representation: bytes.prefix(ephemeralKeyLength)),
            let box = try? AES.GCM.SealedBox(combined: bytes.dropFirst(ephemeralKeyLength))
        else {
            return nil
        }

        for key in allPrivateKeys() {
            guard let secret = try? key.sharedSecretFromKeyAgreement(with: ephemeral) else {
                continue
            }

            let symmetricKey = secret.hkdfDerivedSymmetricKey(
                using: SHA256.self,
                salt: bytes.prefix(ephemeralKeyLength),
                sharedInfo: info,
                outputByteCount: 32
            )

            if let opened = try? AES.GCM.open(box, using: symmetricKey) {
                return opened
            }
        }

        return nil
    }

    private static func privateKey(for serverId: String) -> P256.KeyAgreement.PrivateKey? {
        var query = baseQuery(account: serverId)
        var item: CFTypeRef?

        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        guard
            SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
            let data = item as? Data
        else {
            return nil
        }

        return try? P256.KeyAgreement.PrivateKey(rawRepresentation: data)
    }

    private static func allPrivateKeys() -> [P256.KeyAgreement.PrivateKey] {
        var query = baseQuery(account: nil)
        var items: CFTypeRef?

        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitAll

        guard
            SecItemCopyMatching(query as CFDictionary, &items) == errSecSuccess,
            let keys = items as? [Data]
        else {
            return []
        }

        return keys.compactMap { try? P256.KeyAgreement.PrivateKey(rawRepresentation: $0) }
    }

    // the data protection keychain on a mac too, where the file based one would not share the
    // item with the extension
    private static func baseQuery(account: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecUseDataProtectionKeychain as String: true
        ]

        if let account {
            query[kSecAttrAccount as String] = account
        }

        return query
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func data(base64URL: String) -> Data? {
        var base64 = base64URL
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)

        return Data(base64Encoded: base64)
    }
}
