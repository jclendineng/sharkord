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

    static func login(_ address: ServerAddress, identity: String, password: String) async throws -> String {
        var request = URLRequest(url: address.url(path: "login"))
        request.httpMethod = "POST"
        request.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(LoginBody(identity: identity, password: password))

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
