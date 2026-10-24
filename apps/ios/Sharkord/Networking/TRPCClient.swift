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
    // a reply resumes its caller with the whole frame, which decodes its own payload from it
    private var pending: [Int: CheckedContinuation<Data, Error>] = [:]
    // one per request, asleep until its deadline, so a reply that never arrives cannot leave a
    // caller waiting forever and a channel stuck on its spinner
    private var timeouts: [Int: Task<Void, Never>] = [:]
    private var subscriptions: [Int: (Data) -> Void] = [:]
    private var receiveTask: Task<Void, Never>?
    private var keepAliveTask: Task<Void, Never>?
    private var isClosed = false
    // the server turning the connection itself down, a revoked or expired token, so every call
    // still to come fails with that answer instead of looking like a dropped connection
    private var refusal: TRPCError?

    init(wsURL: URL, token: String) {
        // the flag tells the server to wait for a connectionParams message before building the context
        var components = URLComponents(url: wsURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "connectionParams", value: "1")]

        var request = URLRequest(url: components.url!)
        request.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")

        self.task = URLSession.shared.webSocketTask(with: request)
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

    func rawQuery<Input: Encodable>(_ path: String, input: Input) async throws -> Data {
        try await requestData(method: "query", path: path, input: try jsonObject(input))
    }

    @discardableResult
    func subscribe<Output: Decodable>(_ path: String, onData: @escaping (Output) -> Void) -> Int {
        let id = makeId()

        subscriptions[id] = { [decoder] frame in
            do {
                onData(try decoder.decode(DataFrame<Output>.self, from: frame).result.data)
            } catch {
                print("[trpc] failed to decode \(path): \(error)")
            }
        }

        Task {
            try? await sendJSON(["id": id, "method": "subscription", "params": ["path": path]])
        }

        return id
    }

    func unsubscribe(_ id: Int) {
        guard subscriptions.removeValue(forKey: id) != nil, !isClosed else {
            return
        }

        Task {
            try? await sendJSON(["id": id, "method": "subscription.stop"])
        }
    }

    private func request<Output: Decodable>(method: String, path: String, input: Any?) async throws -> Output {
        let frame = try await requestFrame(method: method, path: path, input: input)

        return try decoder.decode(DataFrame<Output>.self, from: frame).result.data
    }

    // the raw calls hand their payload on as json, so only they pull it back out of the frame
    private func requestData(method: String, path: String, input: Any?) async throws -> Data {
        let frame = try await requestFrame(method: method, path: path, input: input)
        let object = try JSONSerialization.jsonObject(with: frame) as? [String: Any]
        let result = object?["result"] as? [String: Any]

        return try JSONSerialization.data(withJSONObject: result?["data"] ?? NSNull(), options: .fragmentsAllowed)
    }

    private func requestFrame(method: String, path: String, input: Any?) async throws -> Data {
        guard !isClosed else {
            throw refusal ?? TRPCError(message: "Not connected to the server.", code: nil)
        }

        let id = makeId()
        var params: [String: Any] = ["path": path]

        if let input {
            params["input"] = input
        }

        // copied before the escaping send task: a var captured there would need a heap box
        let request = params

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[id] = continuation

                timeouts[id] = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(30))

                    guard !Task.isCancelled else {
                        return
                    }

                    self?.resolve(id, with: .failure(TRPCError(
                        message: "The server took too long to respond.",
                        code: "TIMEOUT"
                    )))
                }

                Task { [weak self] in
                    do {
                        try await self?.sendJSON(["id": id, "method": method, "params": request])
                    } catch {
                        self?.resolve(id, with: .failure(error))
                    }
                }
            }
        } onCancel: {
            // the caller went away, a screen closing or a task(id:) re-firing, so its entry
            // must go too rather than wait for a reply nobody is listening for
            Task { @MainActor [weak self] in
                self?.resolve(id, with: .failure(CancellationError()))
            }
        }
    }

    private func resolve(_ id: Int, with result: Result<Data, Error>) {
        timeouts.removeValue(forKey: id)?.cancel()

        guard let continuation = pending.removeValue(forKey: id) else {
            return
        }

        continuation.resume(with: result)
    }

    private func receiveLoop() async {
        while !isClosed {
            do {
                let message = try await task.receive()

                switch message {
                case .string(let text):
                    handle(Data(text.utf8))
                case .data(let data):
                    handle(data)
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

    // each frame is decoded once into the few fields that route it, and the payload is then
    // decoded straight from the same bytes by whoever asked for it. it used to be parsed into
    // [String: Any], written back out and decoded a third time
    private func handle(_ frame: Data) {
        if frame == Self.pong {
            return
        }

        if frame == Self.ping {
            Task { try? await task.send(.string("PONG")) }
            return
        }

        guard let envelope = try? decoder.decode(Frame.self, from: frame) else {
            return
        }

        if envelope.method == "reconnect" {
            finish(.serverRequestedReconnect)
            task.cancel(with: .normalClosure, reason: nil)
            return
        }

        // an error with no id is the server refusing the token, just before it closes the socket
        guard let id = envelope.id else {
            if let error = envelope.error {
                let trpcError = TRPCError(message: error.message ?? "Unknown error", code: error.data?.code)

                refusal = trpcError

                for id in Array(pending.keys) {
                    resolve(id, with: .failure(trpcError))
                }
            }

            return
        }

        if let error = envelope.error {
            let code = error.data?.code
            // a route this server does not have yet, it runs an older sharkord than the app
            let message = code == "NOT_FOUND" && error.message?.contains("-procedure on path") == true
                ? "This server needs to be updated to use this."
                : error.message ?? "Unknown error"
            let trpcError = TRPCError(message: message, code: code)

            if pending[id] != nil {
                resolve(id, with: .failure(trpcError))
            } else if subscriptions.removeValue(forKey: id) != nil {
                print("[trpc] subscription \(id) failed: \(trpcError.message)")
            }

            return
        }

        guard envelope.result?.type == "data" else {
            return
        }

        if let onData = subscriptions[id] {
            onData(frame)
        } else {
            resolve(id, with: .success(frame))
        }
    }

    private func finish(_ reason: CloseReason) {
        guard !isClosed else {
            return
        }

        isClosed = true
        receiveTask?.cancel()
        keepAliveTask?.cancel()

        let error = refusal ?? TRPCError(message: "Disconnected from the server.", code: nil)

        for timeout in timeouts.values {
            timeout.cancel()
        }

        timeouts.removeAll()

        for continuation in pending.values {
            continuation.resume(throwing: error)
        }

        pending.removeAll()
        subscriptions.removeAll()
        onClose?(reason)
    }

    private static let ping = Data("PING".utf8)
    private static let pong = Data("PONG".utf8)

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

// the parts of a frame that say where it goes. result.data is left for DataFrame
private struct Frame: Decodable {
    struct Failure: Decodable {
        struct Details: Decodable {
            let code: String?
        }

        let message: String?
        let data: Details?
    }

    struct Result: Decodable {
        let type: String?
    }

    let id: Int?
    let method: String?
    let error: Failure?
    let result: Result?
}

// a data frame with its payload decoded as the caller's type
private struct DataFrame<Output: Decodable>: Decodable {
    struct Result: Decodable {
        let data: Output

        private enum CodingKeys: String, CodingKey {
            case data
        }

        // a procedure that returns nothing sends no data key at all, which reads as null,
        // the way the payload did when it was written back out before decoding
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            if container.contains(.data) {
                data = try container.decode(Output.self, forKey: .data)
            } else {
                data = try JSONDecoder().decode(Output.self, from: Data("null".utf8))
            }
        }
    }

    let result: Result
}
