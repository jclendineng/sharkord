import Foundation
import Observation

// who is typing where, from messages.onTyping. each person shows until a moment after their
// last signal or until their message arrives, and this device's own signals are throttled the
// way the web client throttles them
@Observable
final class TypingTracker {
    struct Place: Hashable {
        let channelId: Int
        let parentMessageId: Int?
    }

    // the web client signals every TYPING_MS (300ms) and drops a typist 500ms after the last
    // one, a phone's connection gets a little more slack
    private static let shownFor: Duration = .milliseconds(1500)
    private static let signalEvery: TimeInterval = 0.4

    // in the order they started typing
    private(set) var typists: [Place: [Int]] = [:]

    @ObservationIgnored private var expiries: [Place: [Int: Task<Void, Never>]] = [:]
    @ObservationIgnored private var lastSignals: [Place: Date] = [:]

    func userIds(in place: Place) -> [Int] {
        typists[place] ?? []
    }

    func add(_ userId: Int, in place: Place) {
        expiries[place]?[userId]?.cancel()

        if !userIds(in: place).contains(userId) {
            typists[place, default: []].append(userId)
        }

        expiries[place, default: [:]][userId] = Task { [weak self] in
            try? await Task.sleep(for: Self.shownFor)

            guard !Task.isCancelled else {
                return
            }

            self?.remove(userId, from: place)
        }
    }

    func remove(_ userId: Int, from place: Place) {
        expiries[place]?[userId]?.cancel()
        expiries[place]?[userId] = nil

        guard var userIds = typists[place] else {
            return
        }

        userIds.removeAll { $0 == userId }
        typists[place] = userIds.isEmpty ? nil : userIds
    }

    // true when enough time has passed since this device last said it was typing here
    func shouldSignal(in place: Place, at now: Date = .now) -> Bool {
        if let last = lastSignals[place], now.timeIntervalSince(last) < Self.signalEvery {
            return false
        }

        lastSignals[place] = now

        return true
    }

    // after a send, so typing the next message signals straight away
    func resetSignal(in place: Place) {
        lastSignals[place] = nil
    }
}
