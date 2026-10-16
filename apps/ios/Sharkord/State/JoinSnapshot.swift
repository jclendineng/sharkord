import CryptoKit
import Foundation

// the last others.joinServer answer for each server, and its /info with the server's icon, kept
// as the server sent them. a launch draws the server from them straight away, avatars and all,
// and the live answers replace them a moment later, rather than the app showing nothing until
// three round trips have come back
enum JoinSnapshot {
    private static let directory: URL? = {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }

        let directory = caches.appending(path: "join-snapshots", directoryHint: .isDirectory)

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        return directory
    }()

    static func save(_ data: Data, for address: ServerAddress) {
        write(data, to: url(for: address, kind: "join"))
    }

    static func saveInfo(_ data: Data, for address: ServerAddress) {
        write(data, to: url(for: address, kind: "info"))
    }

    static func load(for address: ServerAddress) -> JoinResult? {
        read(JoinResult.self, from: url(for: address, kind: "join"))
    }

    static func loadInfo(for address: ServerAddress) -> ServerInfo? {
        read(ServerInfo.self, from: url(for: address, kind: "info"))
    }

    static func delete(for address: ServerAddress) {
        for kind in ["join", "info"] {
            if let url = url(for: address, kind: kind) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private static func write(_ data: Data, to url: URL?) {
        guard let url else {
            return
        }

        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private static func read<Value: Decodable>(_ type: Value.Type, from url: URL?) -> Value? {
        guard let url, let data = try? Data(contentsOf: url) else {
            return nil
        }

        return try? JSONDecoder().decode(type, from: data)
    }

    // the address hashed, a url does not make a safe file name
    private static func url(for address: ServerAddress, kind: String) -> URL? {
        let digest = SHA256.hash(data: Data(address.baseURL.absoluteString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()

        return directory?.appending(path: "\(name).\(kind).json")
    }
}
