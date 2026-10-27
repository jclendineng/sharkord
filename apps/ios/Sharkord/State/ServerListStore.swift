import Foundation
import Observation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// every server the app is signed in to, each with its own SessionStore and socket, like the
// server rail in discord. the selected one is what the screens read from the environment
@Observable
final class ServerListStore {
    private(set) var sessions: [SessionStore] = []
    private(set) var selectedSession: SessionStore?
    // the server rail's direct messages button, it shows the selected server's conversations
    var isShowingDirectMessages = false

    // the channels shown, oldest first, for the mac's back and forward, as discord's window has
    private(set) var visits: [Visit] = []
    private(set) var visitIndex = -1
    // a channel opened by going back or forward, which is no new visit
    private var travellingTo: Visit?
    // the sign in screen, for a new server or one whose session ended
    private(set) var signingInSession: SessionStore?

    // the rail's "more options", the channel panel opens the server sheet for it
    var serverSheetRequest: ObjectIdentifier?
    // a tapped new login alert, which opens that server's devices
    var devicesRequest: ObjectIdentifier?

    struct RailMenu {
        let server: SessionStore
        let iconFrame: CGRect
    }

    // a server icon held down, HomeView draws the menu beside it
    var railMenu: RailMenu? {
        // the two are drawn in separate layers, a menu opened while the search was out sat
        // hidden under it. one open closes the other, as discord's popouts do
        didSet {
            if railMenu != nil {
                searchDropdown = nil
            }
        }
    }

    // the mac's search card under the box above the channel list, drawn over the window rather
    // than as a popover, whose window a right click menu inside it could not reach
    struct SearchDropdown {
        let route: SearchRoute
        let anchor: CGRect
    }

    // the chat's pins or threads panel is out. on an ipad a tap on the list beside the chat puts
    // it away, as one anywhere puts the search card away, which the chat's own catcher cannot reach
    var isChatDropdownOpen = false
    var chatDropdownDismissals = 0
    // bumped by the mac's Settings… menu item, which the user bar answers by opening settings
    var settingsRequests = 0
    // the call over everything, opened by the call bar so it grows out of the bar and goes back
    // into it. a voice channel's sheet asks for it here once it has put itself away
    var isCallPresented = false

    var searchDropdown: SearchDropdown? {
        didSet {
            if searchDropdown != nil {
                railMenu = nil
            }
        }
    }

    #if os(iOS)
    @ObservationIgnored private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    #endif

    init() {
        #if DEBUG
        if DebugLaunch.startsSignedOut {
            for address in CredentialStore.serverURLs.compactMap(ServerAddress.init(userInput:)) {
                CredentialStore.deleteToken(for: address)
            }

            CredentialStore.serverURLs = []
        }
        #endif

        sessions = CredentialStore.serverURLs
            .compactMap(ServerAddress.init(userInput:))
            .map(makeSession)
        selectedSession = sessions.first

        #if DEBUG
        if DebugLaunch.credentials != nil {
            return
        }
        #endif

        if sessions.isEmpty {
            addServer()
        }
    }

    var voiceSession: SessionStore? {
        sessions.first { $0.currentVoiceChannelId != nil }
    }

    func restore() async {
        #if DEBUG
        if let credentials = DebugLaunch.credentials {
            let session = makeSession(nil)

            signingInSession = session
            await session.signIn(serverURL: credentials.server, identity: credentials.identity, password: credentials.password)

            if let channelId = DebugLaunch.channelId {
                session.requestedChannelId = channelId
            }

            if let channelId = DebugLaunch.voiceChannelId {
                await session.joinVoice(channelId)
            }

            return
        }
        #endif

        await withTaskGroup(of: Void.self) { group in
            for session in sessions {
                group.addTask {
                    await session.restoreSession()
                }
            }
        }
    }

    func select(_ session: SessionStore) {
        selectedSession = session
        isShowingDirectMessages = false
    }

    func showServerSheet(for session: SessionStore) {
        select(session)
        serverSheetRequest = ObjectIdentifier(session)
    }

    func addServer() {
        signingInSession = makeSession(nil)
    }

    // an invite link opened from outside the app, waiting for the sign in screen to take it up
    var pendingInviteLink: String?
    // a sign in qr code scanned with the camera app, the same
    var pendingLinkLogin: LinkLogin?
    // another device's code asking to be signed in, scanned here, waiting to be approved
    var pendingApproval: LoginApproval?
    // a tapped notification waiting for its server, see open(_:)
    private var pendingNotification: NotificationTarget?

    struct LoginApproval: Identifiable, Equatable {
        let server: String
        let token: String

        var id: String {
            token
        }

        // sharkord://approve?server=…&request=…, what a device without a camera shows
        init?(url: URL) {
            guard url.scheme == "sharkord", url.host() == "approve" else {
                return nil
            }

            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

            guard
                let server = items.first(where: { $0.name == "server" })?.value,
                let token = items.first(where: { $0.name == "request" })?.value,
                !server.isEmpty, !token.isEmpty
            else {
                return nil
            }

            self.server = server
            self.token = token
        }
    }

    // the server here that a request comes from, the only one that can approve it. still
    // reconnecting counts: a code scanned with the camera app opens the app before it has
    func session(approving approval: LoginApproval) -> SessionStore? {
        let address = ServerAddress(userInput: approval.server)

        return sessions.first { $0.address == address }
    }

    struct ChannelLink {
        let server: String
        let channelId: Int

        // sharkord://channel?server=…&channel=…, a channel's copied link
        init?(url: URL) {
            guard url.scheme == "sharkord", url.host() == "channel" else {
                return nil
            }

            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

            guard
                let server = items.first(where: { $0.name == "server" })?.value,
                let channelId = items.first(where: { $0.name == "channel" })?.value.flatMap(Int.init)
            else {
                return nil
            }

            self.server = server
            self.channelId = channelId
        }
    }

    struct LinkLogin: Equatable {
        let server: String
        let token: String

        // sharkord://login?server=…&token=…, what a signed in device shows as a qr code
        init?(url: URL) {
            guard url.scheme == "sharkord", url.host() == "login" else {
                return nil
            }

            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

            guard
                let server = items.first(where: { $0.name == "server" })?.value,
                let token = items.first(where: { $0.name == "token" })?.value,
                !server.isEmpty, !token.isEmpty
            else {
                return nil
            }

            self.server = server
            self.token = token
        }
    }

    // an invite link tapped anywhere: a server already signed in to just opens, as discord does
    // for a server you are in, and any other starts adding it with the invite filled in
    func open(inviteURL url: URL) {
        if let approval = LoginApproval(url: url) {
            guard let session = session(approving: approval) else {
                selectedSession?.showError(AuthAPI.RequestError(message: "Sign in to that server on this device first, then scan the code again."))
                return
            }

            select(session)
            pendingApproval = approval
            return
        }

        if let link = ChannelLink(url: url) {
            let address = ServerAddress(userInput: link.server)

            guard let session = sessions.first(where: { $0.address == address && $0.phase != .signedOut }) else {
                selectedSession?.showError(AuthAPI.RequestError(message: "Sign in to that server on this device first, then open the link again."))
                return
            }

            open(channelId: link.channelId, in: session)
            return
        }

        if let login = LinkLogin(url: url) {
            pendingLinkLogin = login
            signingInSession = makeSession(nil)
            return
        }

        guard let link = Self.inviteLink(from: url), let address = ServerAddress(userInput: link) else {
            return
        }

        if let existing = sessions.first(where: { $0.address == address }), existing.phase != .signedOut {
            select(existing)
            return
        }

        pendingInviteLink = link
        signingInSession = makeSession(nil)
    }

    // the server's own invite link as it is, or the app's sharkord://join?server=…&invite=… which
    // the web client hands over for a server whose links the app cannot open by itself
    static func inviteLink(from url: URL) -> String? {
        if url.scheme == "sharkord" {
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

            guard
                let server = items.first(where: { $0.name == "server" })?.value,
                let invite = items.first(where: { $0.name == "invite" })?.value,
                !server.isEmpty, !invite.isEmpty
            else {
                return nil
            }

            let base = server.contains("://") ? server : "https://\(server)"
            let code = invite.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? invite

            return "\(base)/?invite=\(code)"
        }

        guard
            url.scheme == "https" || url.scheme == "http",
            url.query()?.contains("invite=") == true,
            ServerAddress.inviteCode(in: url.absoluteString) != nil
        else {
            return nil
        }

        return url.absoluteString
    }

    func signInAgain(_ session: SessionStore) {
        signingInSession = session
    }

    func cancelSignIn() {
        signingInSession = nil
    }

    // logging out of a server forgets it, the way leaving one does in discord
    func remove(_ session: SessionStore) {
        session.signOut()
        sessions.removeAll { $0 === session }
        save()

        if selectedSession === session {
            selectedSession = sessions.first
        }

        if sessions.isEmpty {
            addServer()
        }
    }

    // a tapped notification or an entry in the unreads inbox
    // with a message, the chat opens at it rather than at the newest
    func open(channelId: Int, messageId: Int? = nil, threadParentId: Int? = nil, atFirstUnread: Bool = false, in session: SessionStore) {
        let store = session.messages(for: channelId)

        // a reply in a thread opens the thread, from its first message in the channel
        if let threadParentId {
            store.pendingJumpMessageId = threadParentId
            store.pendingThreadParentId = threadParentId
        } else if let messageId {
            store.pendingJumpMessageId = messageId
        } else if atFirstUnread {
            store.pendingJumpToFirstUnread = true
        }

        searchDropdown = nil
        select(session)
        isShowingDirectMessages = session.channel(channelId)?.isDm == true
        session.requestedChannelId = channelId
    }

    struct Visit: Equatable {
        let sessionId: ObjectIdentifier
        let channelId: Int
    }

    private static let visitLimit = 50

    var canGoBack: Bool {
        visitIndex > 0
    }

    var canGoForward: Bool {
        visitIndex < visits.count - 1
    }

    // a visit after going back drops what was ahead of it, as a browser's history does
    func recordVisit(to channelId: Int, in session: SessionStore) {
        let visit = Visit(sessionId: ObjectIdentifier(session), channelId: channelId)

        if travellingTo == visit {
            travellingTo = nil
            return
        }

        if visits.indices.contains(visitIndex), visits[visitIndex] == visit {
            return
        }

        visits = Array(visits.prefix(visitIndex + 1).suffix(Self.visitLimit - 1)) + [visit]
        visitIndex = visits.count - 1
    }

    func goBack() {
        travel(to: visitIndex - 1)
    }

    func goForward() {
        travel(to: visitIndex + 1)
    }

    // a server signed out of since is passed over
    private func travel(to index: Int) {
        guard visits.indices.contains(index) else {
            return
        }

        let visit = visits[index]

        visitIndex = index

        guard let session = sessions.first(where: { ObjectIdentifier($0) == visit.sessionId }) else {
            return
        }

        travellingTo = visit
        open(channelId: visit.channelId, in: session)
    }

    func showDevices(for session: SessionStore) {
        select(session)
        devicesRequest = ObjectIdentifier(session)
    }

    func session(serverId: String) -> SessionStore? {
        sessions.first { $0.serverId == serverId }
    }

    // a tapped notification. one that launched the app arrives before its server has loaded,
    // so it waits here until a session knows that server's id
    func open(_ target: NotificationTarget) {
        guard let session = session(serverId: target.serverId) else {
            pendingNotification = target
            return
        }

        pendingNotification = nil

        switch target {
        case let .message(_, channelId, messageId, threadParentId):
            open(channelId: channelId, messageId: messageId, threadParentId: threadParentId, in: session)
        case .newLogin:
            showDevices(for: session)
        }
    }

    func openPendingNotification() {
        if let pendingNotification {
            open(pendingNotification)
        }
    }

    func registerPushDevice(_ token: String) async {
        for session in sessions where session.phase == .connected {
            await session.registerPushDevice(token)
        }
    }

    func appDidBecomeActive() {
        #if os(iOS)
        endBackgroundTask()
        #endif
        sessions.forEach { $0.appDidBecomeActive() }
    }

    // ios freezes the app seconds after it leaves the screen and its sockets die with it. the
    // time it grants on request, around thirty seconds, keeps them open through a quick
    // switch to another app. a voice call needs none of this, its audio keeps the app running.
    // a mac never freezes it
    func appDidEnterBackground() {
        #if os(iOS)
        guard backgroundTask == .invalid else {
            return
        }

        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "keep-connected") { [weak self] in
            self?.endBackgroundTask()
        }
        #endif
    }

    #if os(iOS)
    private func endBackgroundTask() {
        guard backgroundTask != .invalid else {
            return
        }

        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
    #endif

    private func makeSession(_ address: ServerAddress?) -> SessionStore {
        let session = SessionStore(address: address)

        session.onAuthenticated = { [weak self] session in
            self?.adopt(session)
        }

        session.onWillJoinVoice = { [weak self] session in
            await self?.leaveVoice(except: session)
        }

        return session
    }

    // signing in again to a server already in the list replaces its old session
    private func adopt(_ session: SessionStore) {
        if let index = sessions.firstIndex(where: { $0.address == session.address }) {
            let existing = sessions[index]

            if existing !== session {
                existing.signOut()
                sessions[index] = session
            }
        } else {
            sessions.append(session)
        }

        save()
        signingInSession = nil
        select(session)
    }

    private func leaveVoice(except session: SessionStore) async {
        for other in sessions where other !== session {
            await other.leaveVoice(playsSound: false)
        }
    }

    private func save() {
        CredentialStore.serverURLs = sessions.compactMap { $0.address?.baseURL.absoluteString }
    }
}

// observable classes are identified by their instance, which is what the server rail lists
extension SessionStore: Identifiable {}
