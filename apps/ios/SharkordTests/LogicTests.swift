import Foundation
import Testing
@testable import Sharkord

struct ServerAddressTests {
    @Test(arguments: ["chat.example.com", "https://chat.example.com/", "  chat.example.com//  "])
    func typedAddressesBecomeHTTPS(_ typed: String) throws {
        let address = try #require(ServerAddress(userInput: typed))

        #expect(address.baseURL.absoluteString == "https://chat.example.com")
        #expect(!address.isInsecure)
    }

    @Test(arguments: ["https://chat.example.com/?invite=abc123", "chat.example.com/?invite=abc123", "https://chat.example.com?invite=abc123"])
    func anInviteLinkGivesTheServerAndTheCode(_ typed: String) throws {
        let address = try #require(ServerAddress(userInput: typed))

        #expect(address.baseURL.absoluteString == "https://chat.example.com")
        #expect(ServerAddress.inviteCode(in: typed) == "abc123")
    }

    @Test func aCodeOnItsOwnIsTheCode() {
        #expect(ServerAddress.inviteCode(in: " abc123 ") == "abc123")
        #expect(ServerAddress.inviteCode(in: "chat.example.com") == nil)
        #expect(ServerAddress.inviteCode(in: "") == nil)
    }

    @Test(arguments: ["ftp://chat.example.com", "https://", ""])
    func nonsenseIsRefused(_ typed: String) {
        #expect(ServerAddress(userInput: typed) == nil)
    }

    @Test(arguments: [
        "http://192.168.1.5:4991", "http://10.0.2.27:4991", "http://172.20.0.4", "http://100.100.1.1",
        "http://localhost:4991", "http://nas.local", "http://box.ts.net", "http://unraid"
    ])
    func plainHTTPIsAllowedOnTheLocalNetworkAndTailscale(_ typed: String) throws {
        let address = try #require(ServerAddress(userInput: typed))

        #expect(!address.isInsecure)
    }

    @Test(arguments: ["http://chat.example.com", "http://8.8.8.8", "http://172.32.0.1", "http://100.128.0.1"])
    func plainHTTPOnTheInternetIsInsecure(_ typed: String) throws {
        let address = try #require(ServerAddress(userInput: typed))

        #expect(address.isInsecure)
    }

    @Test func fileLinksCarryTheirSignedToken() throws {
        let address = try #require(ServerAddress(userInput: "chat.example.com"))
        let file = SharkordFile(
            id: 1, name: "test.pdf", originalName: "test.pdf", size: 10, mimeType: "application/pdf",
            accessToken: "abc", accessTokenExpiresAt: 99
        )

        #expect(address.fileURL(file).absoluteString == "https://chat.example.com/public/test.pdf?accessToken=abc&expires=99")
    }
}

struct SearchTests {
    private func message(content: String?) -> SearchMessage {
        SearchMessage(
            id: 1, channelId: 1, userId: 1, createdAt: 0, channelName: "general", channelIsDm: false,
            plainContent: "", content: content, metadata: nil
        )
    }

    @Test func linksComeOutOfTheHTMLInOrderAndOnce() {
        let links = message(content: """
        <p><a href="https://a.com/x?y=1&amp;z=2">a</a> <a href="https://b.com">b</a> <a href="https://a.com/x?y=1&amp;z=2">again</a> <a href="mailto:x@y.z">mail</a></p>
        """).links

        #expect(links.map(\.absoluteString) == ["https://a.com/x?y=1&z=2", "https://b.com"])
    }

    @Test func aMessageWithoutContentHasNoLinks() {
        #expect(message(content: nil).links.isEmpty)
    }

    @Test func searchInputLeavesOutWhatIsNotSet() throws {
        let data = try JSONEncoder().encode(SearchInput(query: "hello", filters: SearchFilters()))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json.keys.sorted() == ["query"])
    }

    @Test func dateFiltersCoverWholeDaysInTheLocalTimeZone() throws {
        let calendar = Calendar.current
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 14, hour: 15)))
        var filters = SearchFilters()

        filters.after = day
        filters.before = day

        let input = SearchInput(query: nil, filters: filters)
        let startOfDay = Int(calendar.startOfDay(for: day).timeIntervalSince1970 * 1000)

        #expect(input.before == startOfDay)
        // after takes everything past the end of the picked day
        #expect(input.after == startOfDay + 86_400_000 - 1)
    }

    @Test func pinsOnlyShowInAChannelAndChannelsOnlyForTheServer() {
        #expect(SearchTab.tabs(inChannel: true).contains(.pins))
        #expect(!SearchTab.tabs(inChannel: true).contains(.channels))
        #expect(SearchTab.tabs(inChannel: false).contains(.channels))
        #expect(!SearchTab.tabs(inChannel: false).contains(.pins))
    }

    @Test func activityReadsLikeDiscord() {
        let now = Date.now

        #expect(ChannelActivityText.text(now) == "Active just now")
        #expect(ChannelActivityText.text(now.addingTimeInterval(-58 * 60)) == "Active 58m ago")
        #expect(ChannelActivityText.text(now.addingTimeInterval(-4 * 3600)) == "Active 4h ago")
        #expect(ChannelActivityText.text(now.addingTimeInterval(-3 * 86_400)) == "Active 3d ago")
    }
}

struct TypingTrackerTests {
    private let place = TypingTracker.Place(channelId: 1, parentMessageId: nil)

    @Test func typistsShowInOrderOnceEach() {
        let tracker = TypingTracker()

        tracker.add(2, in: place)
        tracker.add(3, in: place)
        tracker.add(2, in: place)

        #expect(tracker.userIds(in: place) == [2, 3])
    }

    @Test func aThreadIsSeparateFromItsChannel() {
        let tracker = TypingTracker()
        let thread = TypingTracker.Place(channelId: 1, parentMessageId: 9)

        tracker.add(2, in: thread)

        #expect(tracker.userIds(in: place).isEmpty)
        #expect(tracker.userIds(in: thread) == [2])
    }

    @Test func aSentMessageClearsItsAuthor() {
        let tracker = TypingTracker()

        tracker.add(2, in: place)
        tracker.remove(2, from: place)

        #expect(tracker.userIds(in: place).isEmpty)
    }

    @Test func typistsDropOffAfterAPause() async throws {
        let tracker = TypingTracker()

        tracker.add(2, in: place)
        try await Task.sleep(for: .milliseconds(1700))

        #expect(tracker.userIds(in: place).isEmpty)
    }

    @Test func signalsAreThrottledUntilReset() {
        let tracker = TypingTracker()
        let start = Date.now

        #expect(tracker.shouldSignal(in: place, at: start))
        #expect(!tracker.shouldSignal(in: place, at: start.addingTimeInterval(0.1)))
        #expect(tracker.shouldSignal(in: place, at: start.addingTimeInterval(0.5)))

        tracker.resetSignal(in: place)

        #expect(tracker.shouldSignal(in: place, at: start.addingTimeInterval(0.6)))
    }
}

struct HTMLTextTests {
    @Test func paragraphsAndBreaksBecomeLines() {
        #expect(HTMLText.plainText(from: "<p>one</p><p>two<br>three</p>") == "one\ntwo\nthree")
    }

    @Test func entitiesAreDecoded() {
        #expect(HTMLText.plainText(from: "<p>a &amp; b &lt;c&gt;</p>") == "a & b <c>")
    }

    @Test func bareDomainsBecomeHttpsLinks() {
        #expect(HTMLText.paragraphs(from: "see chat.example.com") == "<p>see <a href=\"https://chat.example.com\">chat.example.com</a></p>")
    }

    @Test func writtenSchemesAreKept() {
        #expect(HTMLText.paragraphs(from: "http://old.example.com") == "<p><a href=\"http://old.example.com\">http://old.example.com</a></p>")
    }

    @Test func textAroundLinksIsEscaped() {
        #expect(HTMLText.paragraphs(from: "<b> https://example.com") == "<p>&lt;b&gt; <a href=\"https://example.com\">https://example.com</a></p>")
    }
}

struct ShortAgeTests {
    private let now = Date(timeIntervalSince1970: 1_000_000_000)

    private func age(secondsAgo: Double) -> String {
        ShortAge.text(since: Int((now.timeIntervalSince1970 - secondsAgo) * 1000), now: now)
    }

    @Test func showsDiscordsShortAges() {
        #expect(age(secondsAgo: 20) == "now")
        #expect(age(secondsAgo: 5 * 60) == "5m")
        #expect(age(secondsAgo: 3 * 3600) == "3h")
        #expect(age(secondsAgo: 15 * 86400) == "15d")
        #expect(age(secondsAgo: 65 * 86400) == "2mo")
        #expect(age(secondsAgo: 400 * 86400) == "1y")
    }
}
