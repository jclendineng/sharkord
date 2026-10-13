import Foundation

struct ServerAddress: Hashable {
    let baseURL: URL

    // accepts what people type: "chat.example.com", "192.168.1.5:4991" or a full url
    init?(userInput: String) {
        var text = userInput.trimmingCharacters(in: .whitespacesAndNewlines)

        while text.hasSuffix("/") {
            text.removeLast()
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

        self.baseURL = url
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

        if let accessToken = file.accessToken {
            var items = [URLQueryItem(name: "accessToken", value: accessToken)]

            if let expires = file.accessTokenExpiresAt {
                items.append(URLQueryItem(name: "expires", value: String(expires)))
            }

            components.queryItems = items
        }

        return components.url!
    }
}
