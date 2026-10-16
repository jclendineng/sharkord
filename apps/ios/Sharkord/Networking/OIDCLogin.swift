import CryptoKit
import Foundation

// the server binds the sign in to a verifier only this app holds, since the state cookie it
// uses for the web client stays inside the browser sheet (apps/server/src/http/oidc)
struct OIDCLogin {
    static let callbackScheme = "sharkord"

    let address: ServerAddress
    let verifier: String
    // lets sso make an account on a server closed to new members, as an invite does for a password
    let invite: String?

    init(address: ServerAddress, invite: String? = nil) {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)

        self.address = address
        self.verifier = Self.base64URL(Data(bytes))
        self.invite = invite
    }

    var startURL: URL {
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))

        var queryItems = [URLQueryItem(name: "app_challenge", value: challenge)]

        if let invite {
            queryItems.append(URLQueryItem(name: "invite", value: invite))
        }

        return address.url(path: "oidc/login").appending(queryItems: queryItems)
    }

    func handoffCode(from callbackURL: URL) throws -> String {
        let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []

        if let code = items.first(where: { $0.name == "code" })?.value {
            return code
        }

        let error = items.first { $0.name == "oidc_error" }?.value

        throw AuthAPI.RequestError(message: Self.message(for: error))
    }

    // mirrors oidcError in the web client's connect.json
    private static func message(for error: String?) -> String {
        switch error {
        case "access_denied":
            "Your identity provider refused the sign in."
        case "invalid_state":
            "This sign in request could not be verified. Please try again."
        case "expired":
            "This sign in request expired. Please try again."
        case "rate_limited":
            "Too many sign in attempts. Please wait a moment and try again."
        case "registration_closed":
            "This server is not accepting new registrations. Ask an administrator to create your account."
        default:
            "Something went wrong while signing in. Please try again."
        }
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
