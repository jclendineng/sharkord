import Foundation

// the parts of the server that live outside tRPC, in apps/server/src/http
enum AuthAPI {
    struct RequestError: LocalizedError {
        let message: String

        var errorDescription: String? { message }
    }

    private struct LoginBody: Encodable {
        let identity: String
        let password: String
        // lets a new account in on a server that is closed to everyone else
        let invite: String?
    }

    private struct OIDCExchangeBody: Encodable {
        let code: String
        let verifier: String
    }

    private struct LoginResponse: Decodable {
        let token: String
    }

    // the server answers with either { error } or { errors: { field: message } }
    private struct ErrorResponse: Decodable {
        let error: String?
        let errors: [String: String]?
    }

    static func fetchInfo(_ address: ServerAddress) async throws -> ServerInfo {
        let (data, response) = try await URLSession.shared.data(from: address.url(path: "info"))

        try check(data, response)

        return try JSONDecoder().decode(ServerInfo.self, from: data)
    }

    static func login(_ address: ServerAddress, identity: String, password: String, invite: String? = nil) async throws -> String {
        var request = URLRequest(url: address.url(path: "login"))
        request.httpMethod = "POST"
        request.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(LoginBody(identity: identity, password: password, invite: invite))

        let (data, response) = try await URLSession.shared.data(for: request)

        try check(data, response)

        return try JSONDecoder().decode(LoginResponse.self, from: data).token
    }

    static func exchangeOIDC(_ login: OIDCLogin, code: String) async throws -> String {
        var request = URLRequest(url: login.address.url(path: "oidc/exchange"))
        request.httpMethod = "POST"
        request.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(OIDCExchangeBody(code: code, verifier: login.verifier))

        let (data, response) = try await URLSession.shared.data(for: request)

        try check(data, response)

        return try JSONDecoder().decode(LoginResponse.self, from: data).token
    }

    private struct LinkBody: Encodable {
        let token: String
        let claimKey: String?
    }

    private struct LinkResponse: Decodable {
        let status: String?
        let claimKey: String?
        let token: String?
    }

    // signing in from a qr code another device shows: the first ask claims it, then the device
    // waits for that one to approve, every couple of seconds until it does or the code runs out
    static func waitForLinkApproval(_ address: ServerAddress, token: String) async throws -> String {
        var claimKey: String?

        while true {
            var request = URLRequest(url: address.url(path: "login/link"))
            request.httpMethod = "POST"
            request.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(LinkBody(token: token, claimKey: claimKey))

            let (data, response) = try await URLSession.shared.data(for: request)

            try check(data, response)

            let body = try JSONDecoder().decode(LinkResponse.self, from: data)

            if let sessionToken = body.token {
                return sessionToken
            }

            claimKey = body.claimKey ?? claimKey

            try await Task.sleep(for: .seconds(2))
        }
    }

    // a sign in this device asks for, when it has no camera to scan another's code with: it
    // shows the token as a qr code and keeps the poll key to itself
    struct LoginRequest: Decodable, Equatable {
        let id: String
        let token: String
        let pollKey: String
        let expiresAt: Int
    }

    private struct LoginRequestPoll: Encodable {
        let id: String
        let pollKey: String
    }

    private struct EmptyBody: Encodable {}

    static func startLoginRequest(_ address: ServerAddress) async throws -> LoginRequest {
        let (data, response) = try await postLoginRequest(address, body: EmptyBody())

        try check(data, response)

        return try JSONDecoder().decode(LoginRequest.self, from: data)
    }

    // every couple of seconds until a signed in device approves it, declines it or it runs out
    static func waitForLoginRequestApproval(_ address: ServerAddress, request: LoginRequest) async throws -> String {
        while true {
            let poll = LoginRequestPoll(id: request.id, pollKey: request.pollKey)
            let (data, response) = try await postLoginRequest(address, body: poll)

            try check(data, response)

            let body = try JSONDecoder().decode(LinkResponse.self, from: data)

            if let sessionToken = body.token {
                return sessionToken
            }

            try await Task.sleep(for: .seconds(2))
        }
    }

    private static func postLoginRequest(_ address: ServerAddress, body: some Encodable) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: address.url(path: "login/request"))
        request.httpMethod = "POST"
        request.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        return try await URLSession.shared.data(for: request)
    }

    private static func check(_ data: Data, _ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) else {
            return
        }

        let body = try? JSONDecoder().decode(ErrorResponse.self, from: data)

        if let message = body?.error ?? body?.errors?.values.first {
            throw RequestError(message: message)
        }

        throw RequestError(message: "The server responded with status \(http.statusCode).")
    }
}
