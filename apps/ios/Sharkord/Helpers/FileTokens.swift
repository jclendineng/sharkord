import Foundation
import Observation

// signed file links run out, an hour by default, while the app keeps what it loaded for far
// longer. this fetches fresh ones (files.sign) for the files the app has drawn a little before
// theirs run out, and hands them out once the old ones have, so nothing already on screen
// loads again. views that draw a file's link read `version`, so they draw it again then
@MainActor
@Observable
final class FileTokens {
    struct Token: Decodable {
        let fileId: Int
        let accessToken: String
        let expiresAt: Int
    }

    private struct SignInput: Encodable {
        let fileIds: [Int]
    }

    static let shared = FileTokens()

    // fetch new links this long before the ones on screen run out
    private static let margin: TimeInterval = 5 * 60
    // files.sign takes at most this many ids per call
    private static let batchSize = 200

    private(set) var version = 0

    // keyed by server host, file ids are only unique on one server
    @ObservationIgnored private var fresh: [String: [Int: Token]] = [:]
    @ObservationIgnored private var known: [String: [Int: Int]] = [:]
    @ObservationIgnored private var clients: [String: TRPCClient] = [:]
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    func setClient(_ client: TRPCClient?, for host: String) {
        clients[host] = client
    }

    // the link to use: the file's own while it still works, then the fresh one fetched for it
    func token(for file: SharkordFile, host: String) -> (accessToken: String, expiresAt: Int)? {
        _ = version

        guard let accessToken = file.accessToken else {
            return nil
        }

        let own = (accessToken: accessToken, expiresAt: file.accessTokenExpiresAt ?? 0)
        let newer = fresh[host]?[file.id].flatMap { $0.expiresAt > own.expiresAt ? $0 : nil }
        let newest = newer.map { (accessToken: $0.accessToken, expiresAt: $0.expiresAt) } ?? own

        if newest.expiresAt > known[host]?[file.id] ?? 0 {
            known[host, default: [:]][file.id] = newest.expiresAt
        }

        scheduleRefresh()

        if Double(own.expiresAt) / 1000 > Date().timeIntervalSince1970 {
            return own
        }

        return newest
    }

    // after a refresh, at least a little later, so links that could not be refreshed (no
    // connection yet) are tried again without spinning
    private func scheduleRefresh(notBefore minimumDelay: TimeInterval = 0) {
        guard refreshTask == nil, let earliest = known.values.flatMap(\.values).min() else {
            return
        }

        let delay = max(minimumDelay, Double(earliest) / 1000 - Self.margin - Date().timeIntervalSince1970)

        // deferred, this is asked for while views are drawn
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            await self?.refresh()
        }
    }

    private func refresh() async {
        let threshold = Int((Date().timeIntervalSince1970 + Self.margin) * 1000)
        var earliestReplaced = Int.max

        for (host, expiries) in known {
            guard let client = clients[host] else {
                continue
            }

            let due = expiries.filter { $0.value <= threshold }.map(\.key)

            for start in stride(from: 0, to: due.count, by: Self.batchSize) {
                let batch = Array(due[start..<min(start + Self.batchSize, due.count)])

                guard let signed: [Token] = try? await client.query("files.sign", input: SignInput(fileIds: batch)) else {
                    // no connection, the next file drawn tries again
                    continue
                }

                let signedIds = Set(signed.map(\.fileId))

                for token in signed {
                    earliestReplaced = min(earliestReplaced, known[host]?[token.fileId] ?? Int.max)
                    fresh[host, default: [:]][token.fileId] = token
                    known[host, default: [:]][token.fileId] = token.expiresAt
                }

                // deleted, or no longer visible: stop asking for it
                for fileId in batch where !signedIds.contains(fileId) {
                    known[host]?[fileId] = nil
                }
            }
        }

        refreshTask = nil

        // the links on screen are kept until they run out, then everything draws again
        if earliestReplaced != Int.max {
            let wait = max(0, Double(earliestReplaced) / 1000 - Date().timeIntervalSince1970) + 1

            Task { [weak self] in
                try? await Task.sleep(for: .seconds(wait))
                self?.version += 1
            }
        }

        scheduleRefresh(notBefore: 30)
    }
}
