import Foundation

// the app's own push relay, apps/push-relay. it holds this build's apns keys, so a server with
// no apple account of its own can still notify it. its address is a build setting of the app,
// never of a server, and a fork with its own build points it at its own copy
enum PushRelay {
    struct Ticket: Decodable {
        // stable for this device on this server, what the server stores it under
        let id: String
        let ticket: String
    }

    struct RequestError: LocalizedError {
        let status: Int

        var errorDescription: String? {
            "Push notifications could not be set up through the relay (\(status))."
        }
    }

    private struct TicketBody: Encodable {
        let deviceToken: String
        let sandbox: Bool
        let serverKey: String
    }

    static let url: URL? = {
        guard
            let address = Bundle.main.object(forInfoDictionaryKey: "SharkordPushRelayURL") as? String,
            !address.isEmpty
        else {
            return nil
        }

        return URL(string: address)
    }()

    // the device token sealed to one server's key, which only that server can then push with
    static func ticket(relay: URL, deviceToken: String, sandbox: Bool, serverKey: String) async throws -> Ticket {
        var request = URLRequest(url: relay.appending(path: "v1/tickets"))
        request.httpMethod = "POST"
        request.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(TicketBody(deviceToken: deviceToken, sandbox: sandbox, serverKey: serverKey))

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        guard status == 200 else {
            throw RequestError(status: status)
        }

        return try JSONDecoder().decode(Ticket.self, from: data)
    }
}
