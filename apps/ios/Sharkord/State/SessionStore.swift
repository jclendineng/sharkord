import AuthenticationServices
import AVFoundation
import Foundation
import Observation
import UIKit
import UserNotifications

@Observable
final class SessionStore {
    enum Phase: Equatable {
        case signedOut
        case connecting
        case needsServerPassword
        case connected
        case reconnecting
    }

    struct ChannelSection: Identifiable {
        let id: Int
        let title: String?
        let channels: [Channel]
    }

    private(set) var phase: Phase
    var errorMessage: String?
    private(set) var toastMessage: String?

    @ObservationIgnored private var toastTask: Task<Void, Never>?

    private(set) var address: ServerAddress?
    private(set) var serverName = ""
    private(set) var serverId: String?
    private(set) var serverInfo: ServerInfo?
    // highlighted in the channel list and opened when the server is picked in the rail
    private(set) var lastChannelId: Int?
    private(set) var ownUserId: Int?
    private(set) var categories: [ChannelCategory] = []
    private(set) var channels: [Channel] = []
    private(set) var usersById: [Int: PublicUser] = [:]
    private(set) var unreadCounts: [Int: Int] = [:]
    private(set) var rolesById: [Int: Role] = [:]
    private(set) var customEmojis: [CustomEmoji] = []
    private(set) var settings: PublicSettings?
    private(set) var directMessages: [DirectMessageConversation] = []
    private(set) var client: TRPCClient?
    private(set) var token: String?
    // set when a notification is tapped, the tab owning that channel opens it and clears it
    var requestedChannelId: Int?
    // who is in which voice channel, keyed by channel id then user id
    private(set) var voiceUsers: [Int: [Int: VoiceUserState]] = [:]
    private(set) var currentVoiceChannelId: Int?
    private(set) var isJoiningVoice = false
    private(set) var micMuted = false
    private(set) var soundMuted = false

    private var handshakeHash: String?
    private var messageStores: [Int: ChannelMessagesStore] = [:]
    private var threadStores: [Int: ChannelMessagesStore] = [:]
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempt = 0
    private var pushToken: String?
    private var hasRequestedPush = false
    private var voice: VoiceConnection?
    // the server drops a socket's voice session with the socket, so a reconnect rejoins it
    private var voiceChannelToRejoin: Int?

    // set by ServerListStore, which keeps the list of servers and allows voice on one at a time
    @ObservationIgnored var onAuthenticated: ((SessionStore) -> Void)?
    @ObservationIgnored var onWillJoinVoice: ((SessionStore) async -> Void)?

    init(address: ServerAddress?) {
        self.address = address
        phase = address.flatMap(CredentialStore.token(for:)) == nil ? .signedOut : .connecting
    }

    // before the first join there is no server name yet, the host stands in for it
    var displayName: String {
        if !serverName.isEmpty {
            return serverName
        }

        return address?.baseURL.host() ?? "Server"
    }

    // text channels and conversations with something unread, for the unreads inbox
    var unreadChannels: [Channel] {
        channels
            .filter { unreadCounts[$0.id, default: 0] > 0 }
            .sorted { $0.position < $1.position }
    }

    var hasUnreadChannels: Bool {
        channels.contains { !$0.isDm && unreadCounts[$0.id, default: 0] > 0 }
    }

    // the channel opened last on this server, like discord, or the first text channel
    var defaultChannelId: Int? {
        let textChannels = channelSections
            .flatMap(\.channels)
            .filter { $0.type == .text }

        if let lastChannelId, textChannels.contains(where: { $0.id == lastChannelId }) {
            return lastChannelId
        }

        return textChannels.first?.id
    }

    func rememberChannel(_ channelId: Int) {
        guard let address, channel(channelId)?.isDm == false else {
            return
        }

        lastChannelId = channelId
        CredentialStore.setLastChannelId(channelId, for: address)
    }

    var channelSections: [ChannelSection] {
        let serverChannels = channels
            .filter { !$0.isDm }
            .sorted { $0.position < $1.position }

        var sections: [ChannelSection] = []
        let uncategorized = serverChannels.filter { $0.categoryId == nil }

        if !uncategorized.isEmpty {
            sections.append(ChannelSection(id: -1, title: nil, channels: uncategorized))
        }

        for category in categories.sorted(by: { $0.position < $1.position }) {
            let categoryChannels = serverChannels.filter { $0.categoryId == category.id }

            sections.append(ChannelSection(id: category.id, title: category.name, channels: categoryChannels))
        }

        return sections
    }

    var ownUser: PublicUser? {
        ownUserId.flatMap { usersById[$0] }
    }

    var directMessagesUnreadCount: Int {
        directMessages.reduce(0) { $0 + unreadCounts[$1.channelId, default: 0] }
    }

    func channel(_ channelId: Int) -> Channel? {
        channels.first { $0.id == channelId }
    }

    // discord style: a name takes the color of the first colored role the user has
    func roleColor(for user: PublicUser?) -> String? {
        guard let user else {
            return nil
        }

        for roleId in user.roleIds {
            if let role = rolesById[roleId], role.color.lowercased() != "#ffffff" {
                return role.color
            }
        }

        return nil
    }

    func customEmoji(named name: String) -> CustomEmoji? {
        customEmojis.first { $0.name == name }
    }

    // for actions with no screen of their own to report on, like a reaction tap
    func showError(_ error: Error) {
        toastMessage = error.localizedDescription
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(3))

            if !Task.isCancelled {
                toastMessage = nil
            }
        }
    }

    func restoreSession() async {
        guard let address, let token = CredentialStore.token(for: address) else {
            return
        }

        await connect(address, token: token)
    }

    func signIn(serverURL: String, identity: String, password: String) async {
        guard let address = ServerAddress(userInput: serverURL) else {
            errorMessage = "Enter a valid server address."
            return
        }

        await signIn(address) {
            try await AuthAPI.login(address, identity: identity, password: password)
        }
    }

    // authenticate shows the provider in a browser sheet and returns the url it redirected
    // back to, it lives in the view since that is where SwiftUI hands out the session
    func signInWithOIDC(serverURL: String, authenticate: (URL) async throws -> URL) async {
        guard let address = ServerAddress(userInput: serverURL) else {
            errorMessage = "Enter a valid server address."
            return
        }

        let login = OIDCLogin(address: address)

        await signIn(address) {
            let callbackURL = try await authenticate(login.startURL)
            let code = try login.handoffCode(from: callbackURL)

            return try await AuthAPI.exchangeOIDC(login, code: code)
        }
    }

    private func signIn(_ address: ServerAddress, token fetchToken: () async throws -> String) async {
        errorMessage = nil
        phase = .connecting

        do {
            let token = try await fetchToken()

            self.address = address
            // first, since adopting this session signs out any older one for the same server,
            // which deletes that server's token from the keychain
            onAuthenticated?(self)
            CredentialStore.save(token: token, for: address)

            await connect(address, token: token)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            phase = .signedOut
        } catch {
            phase = .signedOut
            errorMessage = error.localizedDescription
        }
    }

    func submitServerPassword(_ password: String) async {
        guard let handshakeHash else {
            return
        }

        errorMessage = nil

        do {
            try await join(handshakeHash: handshakeHash, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut(message: String? = nil) {
        reconnectTask?.cancel()
        stopVoice()
        voiceChannelToRejoin = nil

        // the socket has to stay open long enough to tell the server to stop pushing here
        if let client, let pushToken {
            Task {
                try? await client.mutation("notifications.unregisterDevice", input: ["token": pushToken])
                client.close()
            }
        } else {
            client?.close()
        }

        if let address {
            CredentialStore.deleteToken(for: address)
        }

        client = nil
        token = nil
        pushToken = nil
        hasRequestedPush = false
        requestedChannelId = nil
        voiceUsers = [:]
        handshakeHash = nil
        categories = []
        channels = []
        usersById = [:]
        unreadCounts = [:]
        messageStores = [:]
        threadStores = [:]
        directMessages = []
        rolesById = [:]
        customEmojis = []
        settings = nil
        errorMessage = message
        phase = .signedOut
    }

    // ios suspends the socket in the background, so coming back is the moment to retry without waiting
    func appDidBecomeActive() {
        guard phase == .reconnecting, let address, let token else {
            return
        }

        reconnectTask?.cancel()
        reconnectTask = Task {
            await connect(address, token: token)
        }
    }

    func voiceParticipants(in channelId: Int) -> [(user: PublicUser?, state: VoiceUserState)] {
        (voiceUsers[channelId] ?? [:])
            .sorted { $0.key < $1.key }
            .map { (usersById[$0.key], $0.value) }
    }

    func joinVoice(_ channelId: Int) async {
        guard let client, !isJoiningVoice, currentVoiceChannelId != channelId else {
            return
        }

        await onWillJoinVoice?(self)

        if currentVoiceChannelId != nil {
            await leaveVoice()
        }

        isJoiningVoice = true

        defer {
            isJoiningVoice = false
        }

        // listening still works without the microphone, the user just joins muted
        let canSpeak = await AVAudioApplication.requestRecordPermission()

        if !canSpeak {
            micMuted = true
        }

        do {
            let input = try JSONSerialization.data(withJSONObject: [
                "channelId": channelId,
                "state": ["micMuted": micMuted, "soundMuted": soundMuted]
            ])
            let joined = try await client.rawMutation("voice.join", json: input)

            guard
                let object = try JSONSerialization.jsonObject(with: joined) as? [String: Any],
                let capabilities = object["routerRtpCapabilities"]
            else {
                throw VoiceConnection.VoiceError(message: "The server did not answer the voice join.")
            }

            currentVoiceChannelId = channelId

            let connection = VoiceConnection(
                signal: { [weak client] path, json in
                    guard let client else {
                        throw TRPCError(message: "Not connected to the server.", code: nil)
                    }

                    return try await client.rawMutation(path, json: json)
                },
                onFailure: { [weak self] in
                    self?.voiceConnectionFailed()
                }
            )

            voice = connection

            let routerRtpCapabilities = String(
                decoding: try JSONSerialization.data(withJSONObject: capabilities),
                as: UTF8.self
            )

            try await connection.start(
                routerRtpCapabilities: routerRtpCapabilities,
                micMuted: micMuted,
                soundMuted: soundMuted,
                canSpeak: canSpeak
            )

            // the only voice procedure that is a query, so it cannot go through the signal
            let producers: RemoteProducers = try await client.query("voice.getProducers")

            for remoteId in producers.remoteAudioIds {
                await connection.consume(remoteId: remoteId)
            }
        } catch {
            showError(error)
            await leaveVoice()
        }
    }

    func leaveVoice() async {
        guard currentVoiceChannelId != nil else {
            return
        }

        stopVoice()

        _ = try? await client?.rawMutation("voice.leave", json: nil)
    }

    func toggleMicMuted() async {
        micMuted.toggle()
        voice?.setMicMuted(micMuted)

        await updateVoiceState(["micMuted": micMuted])
    }

    func toggleSoundMuted() async {
        soundMuted.toggle()
        voice?.setSoundMuted(soundMuted)

        await updateVoiceState(["soundMuted": soundMuted])
    }

    func isChannelVisible(_ channelId: Int) -> Bool {
        messageStores[channelId]?.isVisible == true
    }

    func registerPushDevice(_ token: String) async {
        guard let client else {
            return
        }

        struct DeviceInput: Encodable {
            let token: String
            let sandbox: Bool
        }

        // a debug build is signed for the apns sandbox, which only accepts its own tokens
        #if DEBUG
        let sandbox = true
        #else
        let sandbox = false
        #endif

        do {
            try await client.mutation("notifications.registerDevice", input: DeviceInput(token: token, sandbox: sandbox))
            pushToken = token
        } catch {
            showError(error)
        }
    }

    func messages(for channelId: Int) -> ChannelMessagesStore {
        if let store = messageStores[channelId] {
            return store
        }

        let store = ChannelMessagesStore(channelId: channelId, scope: .channel, session: self)

        messageStores[channelId] = store

        return store
    }

    func thread(for parent: Message) -> ChannelMessagesStore {
        if let store = threadStores[parent.id] {
            return store
        }

        let store = ChannelMessagesStore(
            channelId: parent.channelId,
            scope: .thread(parentMessageId: parent.id),
            session: self
        )

        threadStores[parent.id] = store

        return store
    }

    func toggleReaction(messageId: Int, emoji: String) async throws {
        guard let client else {
            return
        }

        struct ReactionInput: Encodable {
            let messageId: Int
            let emoji: String
        }

        try await client.mutation("messages.toggleReaction", input: ReactionInput(messageId: messageId, emoji: emoji))
    }

    func loadDirectMessages() async {
        guard let client, settings?.directMessagesEnabled == true else {
            return
        }

        if let conversations: [DirectMessageConversation] = try? await client.query("dms.get") {
            directMessages = conversations
        }
    }

    // returns the existing conversation when there already is one with this user
    func openDirectMessage(with userId: Int) async throws -> Int {
        guard let client else {
            throw TRPCError(message: "Not connected to the server.", code: nil)
        }

        let opened: OpenedDirectMessage = try await client.mutation("dms.open", input: ["userId": userId])

        await loadDirectMessages()

        return opened.channelId
    }

    func directMessagePartner(for channelId: Int) -> PublicUser? {
        directMessages
            .first { $0.channelId == channelId }
            .flatMap { usersById[$0.userId] }
    }

    func deleteTemporaryFile(_ file: TemporaryFile) async {
        try? await client?.mutation("files.deleteTemporary", input: ["fileId": file.id])
    }

    func markAsRead(_ channelId: Int) async {
        guard let client, unreadCounts[channelId, default: 0] > 0 else {
            return
        }

        unreadCounts[channelId] = 0

        try? await client.mutation("channels.markAsRead", input: ["channelId": channelId])
    }

    private func connect(_ address: ServerAddress, token: String) async {
        self.address = address
        self.token = token

        if phase != .reconnecting {
            phase = .connecting
        }

        client?.close()

        let client = TRPCClient(wsURL: address.webSocketURL, token: token)

        client.onClose = { [weak self, weak client] reason in
            guard let self, let client, client === self.client else {
                return
            }

            self.handleClose(reason)
        }

        self.client = client

        do {
            try await client.connect()

            let handshake: Handshake = try await client.query("others.handshake")

            if handshake.hasPassword {
                handshakeHash = handshake.handshakeHash
                phase = .needsServerPassword
                return
            }

            try await join(handshakeHash: handshake.handshakeHash, password: nil)
        } catch let error as TRPCError where error.code != nil {
            // the server answered and refused, retrying with the same token will not help
            signOut(message: error.message)
        } catch {
            guard client === self.client else {
                return
            }

            scheduleReconnect()
        }
    }

    private func join(handshakeHash: String, password: String?) async throws {
        guard let client else {
            return
        }

        struct JoinInput: Encodable {
            let handshakeHash: String
            let password: String?
        }

        let result: JoinResult = try await client.query(
            "others.joinServer",
            input: JoinInput(handshakeHash: handshakeHash, password: password)
        )

        serverName = result.serverName
        serverId = result.serverId
        lastChannelId = address.flatMap(CredentialStore.lastChannelId(for:))
        ownUserId = result.ownUserId
        categories = result.categories
        channels = result.channels
        usersById = Dictionary(uniqueKeysWithValues: result.users.map { ($0.id, $0) })
        rolesById = Dictionary(uniqueKeysWithValues: result.roles.map { ($0.id, $0) })
        customEmojis = result.emojis
        settings = result.publicSettings
        unreadCounts = Dictionary(
            uniqueKeysWithValues: result.readStates.compactMap { key, count in
                Int(key).map { ($0, count) }
            }
        )
        voiceUsers = result.voiceMap.reduce(into: [:]) { map, entry in
            guard let channelId = Int(entry.key), !entry.value.users.isEmpty else {
                return
            }

            map[channelId] = entry.value.users.reduce(into: [:]) { users, user in
                if let userId = Int(user.key) {
                    users[userId] = user.value
                }
            }
        }

        self.handshakeHash = nil
        reconnectAttempt = 0
        phase = .connected

        subscribe(client)

        if let address {
            serverInfo = try? await AuthAPI.fetchInfo(address)
        }

        await loadDirectMessages()
        await enablePushIfAvailable()

        if let channelId = voiceChannelToRejoin {
            voiceChannelToRejoin = nil
            await joinVoice(channelId)
        }

        // anything that arrived while disconnected was missed by the subscriptions
        for store in Array(messageStores.values) + Array(threadStores.values) where store.hasLoaded {
            await store.reload()
        }
    }

    private func stopVoice() {
        voice?.close()
        voice = nil
        currentVoiceChannelId = nil
    }

    private func voiceConnectionFailed() {
        guard voice != nil else {
            return
        }

        showError(VoiceConnection.VoiceError(message: "Lost the voice connection."))

        Task {
            await leaveVoice()
        }
    }

    private func updateVoiceState(_ state: [String: Bool]) async {
        guard let client, currentVoiceChannelId != nil else {
            return
        }

        do {
            _ = try await client.rawMutation("voice.updateState", json: try JSONSerialization.data(withJSONObject: state))
        } catch {
            showError(error)
        }
    }

    private func setVoiceUser(_ userId: Int, in channelId: Int, state: VoiceUserState?) {
        var users = voiceUsers[channelId] ?? [:]

        users[userId] = state
        voiceUsers[channelId] = users.isEmpty ? nil : users
    }

    // once per sign in, a reconnect would only register the same token again
    private func enablePushIfAvailable() async {
        guard !hasRequestedPush else {
            return
        }

        hasRequestedPush = true

        guard
            serverInfo?.pushEnabled == true,
            (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) == true
        else {
            return
        }

        UIApplication.shared.registerForRemoteNotifications()
    }

    private func subscribe(_ client: TRPCClient) {
        client.subscribe("messages.onNew") { [weak self] (message: Message) in
            self?.receive(message)
        }

        client.subscribe("messages.onUpdate") { [weak self] (message: Message) in
            self?.storesShowing(channelId: message.channelId).forEach { $0.update(message) }
        }

        client.subscribe("messages.onDelete") { [weak self] (event: MessageDeletedEvent) in
            self?.storesShowing(channelId: event.channelId).forEach { $0.remove(event.messageId) }
        }

        client.subscribe("messages.onThreadReplyCountUpdate") { [weak self] (update: ThreadReplyCountUpdate) in
            self?.messageStores[update.channelId]?.updateReplyCount(messageId: update.messageId, replyCount: update.replyCount)
        }

        client.subscribe("dms.onConversationOpen") { [weak self] (_: OpenedDirectMessage) in
            Task { await self?.loadDirectMessages() }
        }

        for path in ["users.onJoin", "users.onUpdate", "users.onCreate"] {
            client.subscribe(path) { [weak self] (user: PublicUser) in
                self?.usersById[user.id] = user
            }
        }

        client.subscribe("users.onLeave") { [weak self] (userId: Int) in
            self?.usersById[userId]?.status = .offline
        }

        for path in ["channels.onCreate", "channels.onUpdate"] {
            client.subscribe(path) { [weak self] (channel: Channel) in
                self?.upsert(channel)
            }
        }

        client.subscribe("channels.onDelete") { [weak self] (channelId: Int) in
            self?.channels.removeAll { $0.id == channelId }
        }

        client.subscribe("voice.onJoin") { [weak self] (event: VoiceJoinEvent) in
            self?.setVoiceUser(event.userId, in: event.channelId, state: event.state)
        }

        client.subscribe("voice.onUpdateState") { [weak self] (event: VoiceJoinEvent) in
            self?.setVoiceUser(event.userId, in: event.channelId, state: event.state)
        }

        client.subscribe("voice.onLeave") { [weak self] (event: VoiceLeaveEvent) in
            guard let self else {
                return
            }

            self.setVoiceUser(event.userId, in: event.channelId, state: nil)

            // removed by the server, from another device or by a moderator
            if event.userId == self.ownUserId, event.channelId == self.currentVoiceChannelId, !self.isJoiningVoice {
                self.stopVoice()
            }
        }

        client.subscribe("voice.onNewProducer") { [weak self] (event: VoiceProducerEvent) in
            guard
                let self,
                event.kind == "audio",
                event.channelId == self.currentVoiceChannelId,
                event.remoteId != self.ownUserId
            else {
                return
            }

            Task { await self.voice?.consume(remoteId: event.remoteId) }
        }

        client.subscribe("voice.onProducerClosed") { [weak self] (event: VoiceProducerEvent) in
            guard let self, event.kind == "audio", event.channelId == self.currentVoiceChannelId else {
                return
            }

            self.voice?.closeConsumer(remoteId: event.remoteId)
        }

        client.subscribe("voice.onMoved") { [weak self] (event: VoiceMovedEvent) in
            guard let self, event.fromChannelId == self.currentVoiceChannelId else {
                return
            }

            Task {
                await self.leaveVoice()
                await self.joinVoice(event.channelId)
            }
        }

        client.subscribe("channels.onReadStateUpdate") { [weak self] (update: ReadStateUpdate) in
            self?.unreadCounts[update.channelId] = update.count
        }

        client.subscribe("channels.onReadStateDelta") { [weak self] (delta: ReadStateDelta) in
            guard let self else {
                return
            }

            self.unreadCounts[delta.channelId, default: 0] += delta.delta

            if self.messageStores[delta.channelId]?.isVisible == true {
                Task { await self.markAsRead(delta.channelId) }
            }
        }
    }

    private func receive(_ message: Message) {
        storesShowing(channelId: message.channelId).forEach { $0.insert(message) }

        guard channel(message.channelId)?.isDm == true, message.parentMessageId == nil else {
            return
        }

        // keeps the conversation list sorted by latest activity without refetching it
        if directMessages.contains(where: { $0.channelId == message.channelId }) {
            directMessages = directMessages
                .map { conversation in
                    guard conversation.channelId == message.channelId else {
                        return conversation
                    }

                    return DirectMessageConversation(
                        channelId: conversation.channelId,
                        userId: conversation.userId,
                        lastMessageAt: message.createdAt
                    )
                }
                .sorted { $0.lastMessageAt > $1.lastMessageAt }
        } else {
            Task { await loadDirectMessages() }
        }
    }

    private func storesShowing(channelId: Int) -> [ChannelMessagesStore] {
        let threads = threadStores.values.filter { $0.channelId == channelId }

        return (messageStores[channelId].map { [$0] } ?? []) + threads
    }

    private func upsert(_ channel: Channel) {
        if let index = channels.firstIndex(where: { $0.id == channel.id }) {
            channels[index] = channel
        } else {
            channels.append(channel)
        }
    }

    private func handleClose(_ reason: TRPCClient.CloseReason) {
        switch reason {
        case .closedByClient:
            return
        case .serverRequestedReconnect, .connectionLost:
            scheduleReconnect()
        }
    }

    private func scheduleReconnect() {
        guard let address, let token else {
            return
        }

        if let channelId = currentVoiceChannelId {
            voiceChannelToRejoin = channelId
            stopVoice()
        }

        phase = .reconnecting
        reconnectAttempt += 1

        let delay = min(pow(2, Double(reconnectAttempt - 1)), 30)

        reconnectTask?.cancel()
        reconnectTask = Task {
            try? await Task.sleep(for: .seconds(delay))

            guard !Task.isCancelled else {
                return
            }

            await connect(address, token: token)
        }
    }
}
