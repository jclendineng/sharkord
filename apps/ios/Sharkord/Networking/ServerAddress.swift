import Foundation

struct ServerAddress: Hashable {
    let baseURL: URL

    // accepts what people type: "chat.example.com", "192.168.1.5:4991" or a full url
    init?(userInput: String) {
        var text = userInput.trimmingCharacters(in: .whitespacesAndNewlines)

        while text.hasSuffix("/") {
            text.removeLast()
        }

        // "https://" alone, which would otherwise become a server named https
        if text.hasSuffix(":") {
            return nil
        }

        if !text.contains("://") {
            text = "https://\(text)"
        }

        guard
            let url = URL(string: text),
            let scheme = url.scheme,
            ["http", "https"].contains(scheme),
            url.host() != nil
        else {
            return nil
        }

        // an invite link is the server's address with the code on it, the server is the address
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = nil
        components?.fragment = nil

        while components?.path.hasSuffix("/") == true {
            components?.path.removeLast()
        }

        self.baseURL = components?.url ?? url
    }

    // the code in an invite link, https://chat.example.com/?invite=abc, or a code on its own
    static func inviteCode(in userInput: String) -> String? {
        let text = userInput.trimmingCharacters(in: .whitespacesAndNewlines)

        if let components = URLComponents(string: text.contains("://") ? text : "https://\(text)"),
           let code = components.queryItems?.first(where: { $0.name == "invite" })?.value,
           !code.isEmpty {
            return code
        }

        guard !text.isEmpty, !text.contains("/"), !text.contains("."), !text.contains(" ") else {
            return nil
        }

        return text
    }

    static let insecureMessage = "This server isn't using HTTPS, so everything sent to it could be read on the way. Sharkord only uses plain HTTP on your local network or Tailscale. Add it with an https:// address."

    // plain http anywhere past the local network, where anyone along the way could read it.
    // a private address or a tailscale one is fine, wireguard already encrypts tailscale
    var isInsecure: Bool {
        guard baseURL.scheme == "http", let host = baseURL.host(percentEncoded: false)?.lowercased() else {
            return false
        }

        return !Self.isLocal(host)
    }

    private static let localSuffixes = [".local", ".lan", ".home.arpa", ".internal", ".ts.net"]

    private static func isLocal(_ host: String) -> Bool {
        let host = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))

        if host == "localhost" || localSuffixes.contains(where: host.hasSuffix) {
            return true
        }

        if host.contains(":") {
            return host == "::1" || host.hasPrefix("fe80:") || host.hasPrefix("fc") || host.hasPrefix("fd")
        }

        let octets = host.split(separator: ".").compactMap { Int($0) }

        // a name without dots resolves on the local network only
        guard octets.count == 4 else {
            return !host.contains(".")
        }

        switch (octets[0], octets[1]) {
        case (10, _), (127, _), (192, 168), (169, 254):
            return true
        case (172, 16...31):
            return true
        case (100, 64...127):
            return true
        default:
            return false
        }
    }

    var webSocketURL: URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.scheme = components.scheme == "https" ? "wss" : "ws"

        return components.url!
    }

    func url(path: String) -> URL {
        baseURL.appending(path: path)
    }

    func fileURL(_ file: SharkordFile) -> URL {
        var components = URLComponents(url: url(path: "public/\(file.name)"), resolvingAgainstBaseURL: false)!

        // a fresh link once the one the file came with has run out, see FileTokens
        if let token = FileTokens.shared.token(for: file, host: baseURL.host() ?? "") {
            components.queryItems = [
                URLQueryItem(name: "accessToken", value: token.accessToken),
                URLQueryItem(name: "expires", value: String(token.expiresAt))
            ]
        }

        return components.url!
    }
}
