import Foundation
import Observation
import UIKit

// every server the app is signed in to, each with its own SessionStore and socket, like the
// server rail in discord. the selected one is what the screens read from the environment
@Observable
final class ServerListStore {
    private(set) var sessions: [SessionStore] = []
    private(set) var selectedSession: SessionStore?
    // the server rail's direct messages button, it shows the selected server's conversations
    var isShowingDirectMessages = false
    // the sign in screen, for a new server or one whose session ended
    private(set) var signingInSession: SessionStore?

    @ObservationIgnored private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    init() {
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

    func addServer() {
        signingInSession = makeSession(nil)
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
    func open(channelId: Int, in session: SessionStore) {
        select(session)
        isShowingDirectMessages = session.channel(channelId)?.isDm == true
        session.requestedChannelId = channelId
    }

    func session(serverId: String) -> SessionStore? {
        sessions.first { $0.serverId == serverId }
    }

    func registerPushDevice(_ token: String) async {
        for session in sessions where session.phase == .connected {
            await session.registerPushDevice(token)
        }
    }

    func appDidBecomeActive() {
        endBackgroundTask()
        sessions.forEach { $0.appDidBecomeActive() }
    }

    // ios freezes the app seconds after it leaves the screen and its sockets die with it. the
    // time it grants on request, around thirty seconds, keeps them open through a quick
    // switch to another app. a voice call needs none of this, its audio keeps the app running
    func appDidEnterBackground() {
        guard backgroundTask == .invalid else {
            return
        }

        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "keep-connected") { [weak self] in
            self?.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else {
            return
        }

        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

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
            await other.leaveVoice()
        }
    }

    private func save() {
        CredentialStore.serverURLs = sessions.compactMap { $0.address?.baseURL.absoluteString }
    }
}

// observable classes are identified by their instance, which is what the server rail lists
extension SessionStore: Identifiable {}
