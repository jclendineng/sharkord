import Foundation

struct TRPCError: LocalizedError {
    let message: String
    let code: String?

    var errorDescription: String? { message }
}

// speaks the tRPC v11 websocket protocol the server exposes through applyWSSHandler.
// there is no transformer on the server, so inputs and outputs are plain JSON
final class TRPCClient {
    enum CloseReason {
        case closedByClient
        case serverRequestedReconnect
        case connectionLost(code: Int, reason: String)
    }

    var onClose: ((CloseReason) -> Void)?

    private let task: URLSessionWebSocketTask
    private let token: String
    private let decoder = JSONDecoder()
    private var nextId = 0
    private var pending: [Int: CheckedContinuation<Data, Error>] = [:]
    private var subscriptions: [Int: (Data) -> Void] = [:]
    private var receiveTask: Task<Void, Never>?
    private var keepAliveTask: Task<Void, Never>?
    private var isClosed = false

    init(wsURL: URL, token: String) {
        // the flag tells the server to wait for a connectionParams message before building the context
        var components = URLComponents(url: wsURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "connectionParams", value: "1")]

        self.task = URLSession.shared.webSocketTask(with: components.url!)
        self.token = token
    }

    func connect() async throws {
        task.resume()

        try await sendJSON(["method": "connectionParams", "data": ["token": token]])

        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }

        keepAliveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                try? await self?.task.send(.string("PING"))
            }
        }
    }

    func close() {
        finish(.closedByClient)
        task.cancel(with: .normalClosure, reason: nil)
    }

    func query<Output: Decodable>(_ path: String) async throws -> Output {
        try await request(method: "query", path: path, input: nil)
    }

    func query<Input: Encodable, Output: Decodable>(_ path: String, input: Input) async throws -> Output {
        try await request(method: "query", path: path, input: try jsonObject(input))
    }

    @discardableResult
    func mutation<Input: Encodable, Output: Decodable>(_ path: String, input: Input) async throws -> Output {
        try await request(method: "mutation", path: path, input: try jsonObject(input))
    }

    func mutation<Input: Encodable>(_ path: String, input: Input) async throws {
        let _: IgnoredResult = try await request(method: "mutation", path: path, input: try jsonObject(input))
    }

    // for payloads the app only relays, like mediasoup's rtp and dtls parameters, which go
    // through as json without a model of their own
    func rawMutation(_ path: String, json: Data?) async throws -> Data {
        let input = try json.map { try JSONSerialization.jsonObject(with: $0, options: .fragmentsAllowed) }

        return try await requestData(method: "mutation", path: path, input: input)
    }

    func rawQuery(_ path: String) async throws -> Data {
        try await requestData(method: "query", path: path, input: nil)
    }

    func subscribe<Output: Decodable>(_ path: String, onData: @escaping (Output) -> Void) {
        let id = makeId()

        subscriptions[id] = { [decoder] data in
            do {
                onData(try decoder.decode(Output.self, from: data))
            } catch {
                print("[trpc] failed to decode \(path): \(error)")
            }
        }

        Task {
            try? await sendJSON(["id": id, "method": "subscription", "params": ["path": path]])
        }
    }

    private func request<Output: Decodable>(method: String, path: String, input: Any?) async throws -> Output {
        let data = try await requestData(method: method, path: path, input: input)

        return try decoder.decode(Output.self, from: data)
    }

    private func requestData(method: String, path: String, input: Any?) async throws -> Data {
        guard !isClosed else {
            throw TRPCError(message: "Not connected to the server.", code: nil)
        }

        let id = makeId()
        var params: [String: Any] = ["path": path]

        if let input {
            params["input"] = input
        }

        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation

            Task {
                do {
                    try await sendJSON(["id": id, "method": method, "params": params])
                } catch {
                    pending.removeValue(forKey: id)?.resume(throwing: error)
                }
            }
        }
    }

    private func receiveLoop() async {
        while !isClosed {
            do {
                let message = try await task.receive()

                switch message {
                case .string(let text):
                    handle(text)
                case .data(let data):
                    handle(String(decoding: data, as: UTF8.self))
                @unknown default:
                    break
                }
            } catch {
                let reason = task.closeReason.map { String(decoding: $0, as: UTF8.self) } ?? ""

                finish(.connectionLost(code: task.closeCode.rawValue, reason: reason))
                return
            }
        }
    }

    private func handle(_ text: String) {
        if text == "PONG" {
            return
        }

        if text == "PING" {
            Task { try? await task.send(.string("PONG")) }
            return
        }

        guard
            let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        else {
            return
        }

        if object["method"] as? String == "reconnect" {
            finish(.serverRequestedReconnect)
            task.cancel(with: .normalClosure, reason: nil)
            return
        }

        guard let id = object["id"] as? Int else {
            return
        }

        if let error = object["error"] as? [String: Any] {
            let data = error["data"] as? [String: Any]
            let trpcError = TRPCError(
                message: error["message"] as? String ?? "Unknown error",
                code: data?["code"] as? String
            )

            if let continuation = pending.removeValue(forKey: id) {
                continuation.resume(throwing: trpcError)
            } else if subscriptions.removeValue(forKey: id) != nil {
                print("[trpc] subscription \(id) failed: \(trpcError.message)")
            }

            return
        }

        guard
            let result = object["result"] as? [String: Any],
            result["type"] as? String == "data"
        else {
            return
        }

        let payload = result["data"] ?? NSNull()

        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: .fragmentsAllowed) else {
            return
        }

        if let continuation = pending.removeValue(forKey: id) {
            continuation.resume(returning: data)
        } else if let onData = subscriptions[id] {
            onData(data)
        }
    }

    private func finish(_ reason: CloseReason) {
        guard !isClosed else {
            return
        }

        isClosed = true
        receiveTask?.cancel()
        keepAliveTask?.cancel()

        let error = TRPCError(message: "Disconnected from the server.", code: nil)

        for continuation in pending.values {
            continuation.resume(throwing: error)
        }

        pending.removeAll()
        subscriptions.removeAll()
        onClose?(reason)
    }

    private func makeId() -> Int {
        nextId += 1

        return nextId
    }

    private func sendJSON(_ object: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: object)

        try await task.send(.string(String(decoding: data, as: UTF8.self)))
    }

    private func jsonObject<Input: Encodable>(_ input: Input) throws -> Any {
        let data = try JSONEncoder().encode(input)

        return try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
    }
}

// mutations whose result the app does not use; decodes anything, including null
private struct IgnoredResult: Decodable {
    init(from decoder: Decoder) throws {}
}
