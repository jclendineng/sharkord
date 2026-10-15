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
    // a reconnect usually finishes before anyone notices, the banner waits a moment first
    private(set) var showsReconnectingBanner = false
    var errorMessage: String?
    // set when the server refused the sign in rather than you logging out, so the login screen opens once
    var wantsSignInPrompt = false
    private(set) var toastMessage: String?

    @ObservationIgnored private var toastTask: Task<Void, Never>?

    private(set) var address: ServerAddress?
    private(set) var serverName = ""
    private(set) var serverId: String?
    private(set) var serverInfo: ServerInfo?

    // the address the server's admins set for reports, nil while they haven't
    var reportEmail: String? {
        guard let email = serverInfo?.reportEmail, !email.isEmpty else {
            return nil
        }

        return email
    }
    // highlighted in the channel list and opened when the server is picked in the rail
    private(set) var lastChannelId: Int?
    private(set) var notificationLevels: [Int: ChannelNotificationLevel] = [:]
    // when a mute for a while ends, by channel, in milliseconds
    private(set) var mutedUntil: [Int: Int] = [:]
    private(set) var pinnedChannelIds: [Int] = []
    private(set) var hidesMutedChannels = false
    private(set) var allowsDirectMessages = true
    private(set) var friendLists = FriendLists()
    // what this account picked, which the member list cannot say for invisible
    private(set) var ownPresence = Presence.online
    private(set) var ownCustomStatus: String?
    private(set) var ownUserId: Int?
    private(set) var categories: [ChannelCategory] = []
    private(set) var channels: [Channel] = []
    private(set) var usersById: [Int: PublicUser] = [:]
    private(set) var unreadCounts: [Int: Int] = [:]
    private(set) var rolesById: [Int: Role] = [:]
    private(set) var customEmojis: [CustomEmoji] = []
    private(set) var stickers: [Sticker] = []
    private(set) var settings: PublicSettings?
    // keyed by channel id, only private channels are bound by it, as on the web
    private(set) var channelPermissions: [Int: [String: Bool]] = [:]
    private(set) var directMessages: [DirectMessageConversation] = []
    private(set) var client: TRPCClient?
    let typing = TypingTracker()
    private(set) var token: String?
    // set when a notification is tapped, the tab owning that channel opens it and clears it
    var requestedChannelId: Int?
    // who is in which voice channel, keyed by channel id then user id
    private(set) var voiceUsers: [Int: [Int: VoiceUserState]] = [:]
    private(set) var currentVoiceChannelId: Int?
    // the emoji each person in the call just sent, VOICE_REACTION_DURATION_MS on the web
    private(set) var voiceReactions: [Int: [VoiceReaction]] = [:]
    @ObservationIgnored private var nextVoiceReactionId = 0
    private(set) var isJoiningVoice = false
    private(set) var micMuted = false
    private(set) var soundMuted = false
    private(set) var cameraEnabled = false
    private(set) var isSharingScreen = false
    // webcams and screen shares in the current voice channel, the own camera under the own id
    private(set) var videoTracks: [VoiceStreamKey: VideoTrackBox] = [:]

    private var handshakeHash: String?
    private var messageStores: [Int: ChannelMessagesStore] = [:]
    private var threadStores: [Int: ChannelMessagesStore] = [:]
    private var reconnectTask: Task<Void, Never>?
    private var reconnectBannerTask: Task<Void, Never>?
    private var reconnectAttempt = 0
    private var pushToken: String?
    private var hasRequestedPush = false
    private var voice: VoiceConnection?
    private var screenReceiver: ScreenShareReceiver?
    // present when the call was joined with app audio on, see AppSettings.shareAppAudio
    private var mixingDevice: MixingAudioDevice?
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
            .filter { unreadCounts[$0.id, default: 0] > 0 && !isMuted($0.id) }
            .sorted { $0.position < $1.position }
    }

    // everyone on the server, without the deleted user placeholder or banned accounts
    var members: [PublicUser] {
        usersById.values.filter(\.isMember)
    }

    var onlineCount: Int {
        members.filter { $0.status == .online || $0.status == .idle }.count
    }

    // a muted channel never lights up the server, like discord
    // OWNER_ROLE_ID, which holds every permission whatever its list says
    private static let ownerRoleId = 1

    // what the account may do server wide, from its roles
    var ownPermissions: Set<String> {
        guard let roleIds = ownUser?.roleIds else {
            return []
        }

        return Set(roleIds.flatMap { rolesById[$0]?.permissions ?? [] })
    }

    var isOwner: Bool {
        ownUser?.roleIds.contains(Self.ownerRoleId) == true
    }

    func can(_ permission: Permission) -> Bool {
        isOwner || ownPermissions.contains(permission.rawValue)
    }

    // useChannelCan on the web: public channels and direct messages are not bound by channel
    // permissions, in a private one view has to hold before anything else counts
    func can(_ permission: String, inChannel channelId: Int) -> Bool {
        guard !isOwner, let channel = channel(channelId), channel.private, !channel.isDm else {
            return true
        }

        let permissions = channelPermissions[channelId] ?? [:]

        if permissions["VIEW_CHANNEL"] == false {
            return false
        }

        return permissions[permission] == true
    }

    private func applyChannelPermissions(_ map: [String: ChannelPermissions]) {
        channelPermissions = map.values.reduce(into: [:]) { result, entry in
            result[entry.channelId] = entry.permissions
        }
    }

    // the logo and description live in /info, read again after an admin changes them
    func refreshServerInfo() async {
        if let address, let info = try? await AuthAPI.fetchInfo(address) {
            serverInfo = info
            serverName = info.name
        }
    }

    // the settings screens call routes directly, these fail plainly while disconnected
    func request<Output: Decodable>(_ path: String) async throws -> Output {
        guard let client else {
            throw TRPCError(message: "Not connected to the server.", code: nil)
        }

        return try await client.query(path)
    }

    func request<Input: Encodable, Output: Decodable>(_ path: String, _ input: Input) async throws -> Output {
        guard let client else {
            throw TRPCError(message: "Not connected to the server.", code: nil)
        }

        return try await client.query(path, input: input)
    }

    // tells the others in a channel or thread that this account is typing, throttled
    func signalTyping(channelId: Int, parentMessageId: Int?) {
        struct TypingInput: Encodable {
            let channelId: Int
            let parentMessageId: Int?
        }

        guard typing.shouldSignal(in: .init(channelId: channelId, parentMessageId: parentMessageId)) else {
            return
        }

        Task {
            try? await perform("messages.signalTyping", TypingInput(channelId: channelId, parentMessageId: parentMessageId))
        }
    }

    func perform<Input: Encodable>(_ path: String, _ input: Input) async throws {
        guard let client else {
            throw TRPCError(message: "Not connected to the server.", code: nil)
        }

        try await client.mutation(path, input: input)
    }

    func perform<Input: Encodable, Output: Decodable>(_ path: String, _ input: Input) async throws -> Output {
        guard let client else {
            throw TRPCError(message: "Not connected to the server.", code: nil)
        }

        return try await client.mutation(path, input: input)
    }

    // whether the server settings screen has anything to show this account
    var canManageServer: Bool {
        isOwner || Permission.allCases.contains { $0.isAdmin && ownPermissions.contains($0.rawValue) }
    }

    var hasUnreadChannels: Bool {
        channels.contains { !$0.isDm && !isMuted($0.id) && unreadCounts[$0.id, default: 0] > 0 }
    }

    func notificationLevel(for channelId: Int) -> ChannelNotificationLevel {
        // a mute that has run out is the default again
        if let end = mutedUntil[channelId], Double(end) / 1000 <= Date().timeIntervalSince1970 {
            return .mentions
        }

        return notificationLevels[channelId] ?? .mentions
    }

    func isMuted(_ channelId: Int) -> Bool {
        notificationLevel(for: channelId) == .none
    }

    func isPinned(_ channelId: Int) -> Bool {
        pinnedChannelIds.contains(channelId)
    }

    func togglePinned(_ channelId: Int) {
        guard let address else {
            return
        }

        if isPinned(channelId) {
            pinnedChannelIds.removeAll { $0 == channelId }
        } else {
            pinnedChannelIds.append(channelId)
        }

        CredentialStore.setPinnedChannelIds(pinnedChannelIds, for: address)
    }

    func setHidesMutedChannels(_ hides: Bool) {
        guard let address else {
            return
        }

        hidesMutedChannels = hides
        CredentialStore.setHidesMutedChannels(hides, for: address)
    }

    func setNotificationLevel(_ level: ChannelNotificationLevel, for channelId: Int, muteForMinutes: Int? = nil) async {
        guard let client else {
            return
        }

        struct LevelInput: Encodable {
            let channelId: Int
            let level: ChannelNotificationLevel
            let muteForMinutes: Int?
        }

        let previous = notificationLevels[channelId]
        let previousEnd = mutedUntil[channelId]

        notificationLevels[channelId] = level == .mentions ? nil : level
        mutedUntil[channelId] = muteForMinutes.map { Int((Date().timeIntervalSince1970 + Double($0) * 60) * 1000) }

        do {
            try await client.mutation(
                "notifications.setChannelSetting",
                input: LevelInput(channelId: channelId, level: level, muteForMinutes: muteForMinutes)
            )
        } catch {
            notificationLevels[channelId] = previous
            mutedUntil[channelId] = previousEnd
            showError(error)
        }
    }

    // muted, and until when if it is for a while
    func muteEnd(for channelId: Int) -> Date? {
        guard isMuted(channelId), let end = mutedUntil[channelId] else {
            return nil
        }

        return Date(timeIntervalSince1970: Double(end) / 1000)
    }

    func setAllowsDirectMessages(_ allows: Bool) async {
        guard let client else {
            return
        }

        allowsDirectMessages = allows

        do {
            try await client.mutation("users.updatePrivacy", input: ["allowDirectMessages": allows])
        } catch {
            allowsDirectMessages = !allows
            showError(error)
        }
    }

    // both are newer than some servers, which then simply keep the defaults
    private func loadPersonalSettings() async {
        guard let client else {
            return
        }

        if let settings: [ChannelNotificationSetting] = try? await client.query("notifications.getChannelSettings") {
            notificationLevels = Dictionary(uniqueKeysWithValues: settings.map { ($0.channelId, $0.level) })
            mutedUntil = Dictionary(uniqueKeysWithValues: settings.compactMap { setting in
                setting.mutedUntil.map { (setting.channelId, $0) }
            })
        }

        if let privacy: PrivacySettings = try? await client.query("users.getPrivacy") {
            allowsDirectMessages = privacy.allowDirectMessages
        }

        if let presence: PresenceState = try? await client.query("users.getPresence") {
            ownPresence = presence.presence
            ownCustomStatus = presence.customStatus
            applyOwnPresence()
        }
    }

    func setPresence(_ presence: Presence, customStatus: String?) async throws {
        guard let client else {
            return
        }

        struct PresenceInput: Encodable {
            let presence: Presence
            let customStatus: String?
        }

        try await client.mutation("users.setPresence", input: PresenceInput(presence: presence, customStatus: customStatus))

        ownPresence = presence
        ownCustomStatus = customStatus?.isEmpty == true ? nil : customStatus
        applyOwnPresence()
    }

    // the own entry shows the status picked, invisible as offline the way others see it
    private func applyOwnPresence() {
        guard let ownUserId else {
            return
        }

        usersById[ownUserId]?.status = ownPresence.status
        usersById[ownUserId]?.customStatus = ownCustomStatus
    }

    // MARK: server emoji

    // images from the photo library or files app, at most 20 per request on the server
    func addEmojis(_ uploads: [(fileURL: URL, name: String)]) async throws {
        guard let client, let address, let token else {
            return
        }

        struct NewEmoji: Encodable {
            let fileId: String
            let name: String
        }

        var pending: [NewEmoji] = []

        for upload in uploads {
            let file = try await UploadAPI.upload(fileAt: upload.fileURL, name: upload.fileURL.lastPathComponent, to: address, token: token)

            pending.append(NewEmoji(fileId: file.id, name: upload.name))
        }

        for start in stride(from: 0, to: pending.count, by: 20) {
            let batch = Array(pending[start..<min(start + 20, pending.count)])

            try await client.mutation("emojis.add", input: batch)
        }
    }

    func renameEmoji(_ emojiId: Int, to name: String) async throws {
        guard let client else {
            return
        }

        struct RenameInput: Encodable {
            let emojiId: Int
            let name: String
        }

        try await client.mutation("emojis.update", input: RenameInput(emojiId: emojiId, name: name))
    }

    func deleteEmoji(_ emojiId: Int) async throws {
        guard let client else {
            return
        }

        try await client.mutation("emojis.delete", input: ["emojiId": emojiId])
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
            .filter { !$0.isDm && !(hidesMutedChannels && isMuted($0.id)) }
            .sorted { $0.position < $1.position }

        var sections: [ChannelSection] = []
        let pinned = pinnedChannelIds.compactMap { id in serverChannels.first { $0.id == id } }

        if !pinned.isEmpty {
            sections.append(ChannelSection(id: -2, title: "Pinned", channels: pinned))
        }
        // a pinned channel moves to the top rather than showing twice
        let uncategorized = serverChannels.filter { $0.categoryId == nil && !isPinned($0.id) }

        if !uncategorized.isEmpty {
            sections.append(ChannelSection(id: -1, title: nil, channels: uncategorized))
        }

        for category in categories.sorted(by: { $0.position < $1.position }) {
            let categoryChannels = serverChannels.filter { $0.categoryId == category.id && !isPinned($0.id) }

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
        guard !address.isInsecure else {
            errorMessage = ServerAddress.insecureMessage
            return
        }

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

        if let address {
            FileTokens.shared.setClient(nil, for: address.baseURL.host() ?? "")
        }

        client = nil
        token = nil
        pushToken = nil
        friendLists = FriendLists()
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
        stickers = []
        settings = nil
        errorMessage = message
        wantsSignInPrompt = message != nil
        hideReconnectingBanner()
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

    // the quick picks the web shows, QUICK_VOICE_REACTION_EMOJIS
    static let quickVoiceReactions = ["sparkling_heart", "+1", "tada", "clap", "smile", "open_mouth", "cry", "thinking", "-1"]

    func sendVoiceReaction(_ emoji: String) async {
        do {
            try await perform("voice.sendReaction", ["emoji": emoji])
        } catch {
            showError(error)
        }
    }

    // at most five at once per person, each gone after a little over two and a half seconds
    private func showVoiceReaction(_ emoji: String, from userId: Int) {
        nextVoiceReactionId += 1

        let reaction = VoiceReaction(id: nextVoiceReactionId, emoji: emoji)

        voiceReactions[userId, default: []].append(reaction)
        voiceReactions[userId] = Array(voiceReactions[userId, default: []].suffix(5))

        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(2600))
            self?.voiceReactions[userId]?.removeAll { $0.id == reaction.id }
        }
    }

    // MOVE_MEMBERS: puts someone in another voice channel, the web's drag between channels
    func moveToVoice(userId: Int, channelId: Int) async {
        struct MoveInput: Encodable {
            let userId: Int
            let channelId: Int
        }

        do {
            try await perform("voice.moveUser", MoveInput(userId: userId, channelId: channelId))
        } catch {
            showError(error)
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

            let settings = AppSettings.shared
            let audioOptions = VoiceConnection.AudioOptions(
                echoCancellation: settings.echoCancellation,
                noiseSuppression: settings.noiseSuppression,
                autoGainControl: settings.autoGainControl,
                speakerByDefault: settings.speakerByDefault,
                outputVolume: settings.outputVolume
            )
            let mixer = settings.shareAppAudio ? MixingAudioDevice(options: audioOptions) : nil

            mixingDevice = mixer

            let connection = VoiceConnection(
                audioOptions: audioOptions,
                mixingDevice: mixer,
                signal: { [weak client] path, json in
                    guard let client else {
                        throw TRPCError(message: "Not connected to the server.", code: nil)
                    }

                    return try await client.rawMutation(path, json: json)
                },
                onFailure: { [weak self] in
                    self?.voiceConnectionFailed()
                },
                onVideo: { [weak self] key, track in
                    self?.videoTracks[key] = track
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

            for key in producers.keys {
                await connection.consume(key)
            }

            listenForScreenShare()
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

    func toggleCamera() async {
        guard let voice, let ownUserId else {
            return
        }

        if cameraEnabled {
            cameraEnabled = false
            await voice.stopCamera(ownUserId: ownUserId)
            await updateVoiceState(["webcamEnabled": false])
            return
        }

        guard await AVCaptureDevice.requestAccess(for: .video) else {
            showError(VoiceConnection.VoiceError(message: "Allow camera access in Settings to turn on your camera."))
            return
        }

        do {
            try await voice.startCamera(ownUserId: ownUserId)
            cameraEnabled = true
            await updateVoiceState(["webcamEnabled": true])
        } catch {
            showError(error)
        }
    }

    // the broadcast extension connects to this when someone starts sharing from the picker
    private func listenForScreenShare() {
        screenReceiver?.stop()

        let quality = AppSettings.shared.streamQuality
        let receiver = ScreenShareReceiver(
            maxDimension: quality.maxDimension,
            framesPerSecond: quality.framesPerSecond,
            shareAudio: mixingDevice != nil,
            onConnect: { [weak self] in
                Task { @MainActor in
                    await self?.startScreenShare()
                }
            },
            onDisconnect: { [weak self] in
                Task { @MainActor in
                    await self?.stopScreenShare()
                }
            }
        )

        receiver.start()
        screenReceiver = receiver
    }

    func setStreamQuality(_ quality: AppSettings.StreamQuality) {
        AppSettings.shared.streamQuality = quality
        screenReceiver?.setQuality(maxDimension: quality.maxDimension, framesPerSecond: quality.framesPerSecond)
    }

    private func startScreenShare() async {
        guard let voice, let screenReceiver else {
            return
        }

        do {
            let sink = try await voice.startScreenShare()

            screenReceiver.setFrameHandler { pixelBuffer in
                sink.push(pixelBuffer)
            }

            if let mixer = mixingDevice {
                screenReceiver.setAudioHandler { samples in
                    mixer.writeGameAudio(samples)
                }
            }

            isSharingScreen = true
            await updateVoiceState(["sharingScreen": true])
        } catch {
            showError(error)
            // the extension sees the connection close and ends the broadcast
            screenReceiver.dropClient()
        }
    }

    private func stopScreenShare() async {
        screenReceiver?.setFrameHandler(nil)
        screenReceiver?.setAudioHandler(nil)
        mixingDevice?.clearGameAudio()

        guard isSharingScreen, let voice else {
            return
        }

        isSharingScreen = false
        await voice.stopScreenShare()
        await updateVoiceState(["sharingScreen": false])
    }

    func flipCamera() {
        voice?.flipCamera()
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
        CredentialStore.devicePushToken = token

        guard let client, let address, !CredentialStore.isPushMuted(for: address) else {
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

    // a server from before friends simply has none
    func loadFriends() async {
        guard let client, let lists: FriendLists = try? await client.query("friends.get") else {
            return
        }

        friendLists = lists
    }

    func friendStatus(with userId: Int) -> FriendStatus {
        if friendLists.friends.contains(userId) {
            return .friends
        }

        if friendLists.incoming.contains(userId) {
            return .incoming
        }

        if friendLists.outgoing.contains(userId) {
            return .outgoing
        }

        return .none
    }

    // request, accept or remove, then the list as the server has it
    func changeFriendship(_ action: String, with userId: Int) async {
        do {
            try await perform("friends.\(action)", ["userId": userId])
            await loadFriends()
        } catch {
            showError(error)
        }
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

    // out of a group, it leaves the list and the chat if it is open
    func leaveGroup(_ channelId: Int) async {
        do {
            try await perform("dms.leaveGroup", ["channelId": channelId])
            await loadDirectMessages()
        } catch {
            showError(error)
        }
    }

    // a group conversation's details, nil for two people
    func group(for channelId: Int) -> GroupInfo? {
        directMessages.first { $0.channelId == channelId }?.group
    }

    // what a conversation is called: the other person, or a group's name, or its people
    // a direct message's channel is named after its two ids, "DM - 2:5", which means nothing to
    // anyone: it goes by the person or group instead
    func isDirectMessage(_ channelId: Int) -> Bool {
        channel(channelId)?.isDm == true || directMessages.contains { $0.channelId == channelId }
    }

    func placeName(channelId: Int, channelName: String) -> String {
        isDirectMessage(channelId) ? conversationTitle(for: channelId) : channelName
    }

    func placeSymbol(channelId: Int) -> String {
        guard isDirectMessage(channelId) else {
            return "number"
        }

        return group(for: channelId) == nil ? "at" : "person.2.fill"
    }

    func conversationTitle(for channelId: Int) -> String {
        if let group = group(for: channelId) {
            if let name = group.name, !name.isEmpty {
                return name
            }

            let names = group.memberIds.compactMap { usersById[$0]?.name }

            return names.isEmpty ? "Group" : names.joined(separator: ", ")
        }

        return directMessagePartner(for: channelId)?.name ?? "Direct Message"
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
        // a server added before plain http was refused, its token never goes out unencrypted
        guard !address.isInsecure else {
            signOut(message: ServerAddress.insecureMessage)
            return
        }

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
        FileTokens.shared.setClient(client, for: address.baseURL.host() ?? "")

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
        pinnedChannelIds = address.map(CredentialStore.pinnedChannelIds(for:)) ?? []
        hidesMutedChannels = address.map(CredentialStore.hidesMutedChannels(for:)) ?? false
        ownUserId = result.ownUserId
        categories = result.categories
        channels = result.channels
        usersById = Dictionary(uniqueKeysWithValues: result.users.map { ($0.id, $0) })
        // joining is what makes this account online, whatever the list said a moment before
        usersById[result.ownUserId]?.status = .online
        rolesById = Dictionary(uniqueKeysWithValues: result.roles.map { ($0.id, $0) })
        customEmojis = result.emojis
        stickers = result.stickers ?? []
        settings = result.publicSettings
        applyChannelPermissions(result.channelPermissions ?? [:])
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
        hideReconnectingBanner()

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

        await refreshToken()
        await loadPersonalSettings()
        await loadFriends()

        // anything that arrived while disconnected was missed by the subscriptions
        for store in Array(messageStores.values) + Array(threadStores.values) where store.hasLoaded {
            await store.reload()
        }
    }

    private func showReconnectingBannerLater() {
        guard reconnectBannerTask == nil else {
            return
        }

        reconnectBannerTask = Task {
            try? await Task.sleep(for: .seconds(2))

            if !Task.isCancelled, phase == .reconnecting {
                showsReconnectingBanner = true
            }
        }
    }

    private func hideReconnectingBanner() {
        reconnectBannerTask?.cancel()
        reconnectBannerTask = nil
        showsReconnectingBanner = false
    }

    // a token lives a week from when it was issued, renewing it on every connect keeps a
    // device that is in use signed in. an older server without sessions just says no
    private func refreshToken() async {
        guard let client, let address else {
            return
        }

        struct NoInput: Encodable {}

        guard let refreshed: RefreshedToken = try? await client.mutation("sessions.refreshToken", input: NoInput()) else {
            return
        }

        token = refreshed.token
        CredentialStore.save(token: refreshed.token, for: address)
    }

    func deviceSessions() async throws -> [DeviceSession] {
        guard let client else {
            return []
        }

        return try await client.query("sessions.getAll")
    }

    func revokeSession(_ sessionId: String) async throws {
        guard let client else {
            return
        }

        try await client.mutation("sessions.revoke", input: ["sessionId": sessionId])
    }

    func revokeOtherSessions() async throws -> Int {
        guard let client else {
            return 0
        }

        struct NoInput: Encodable {}

        let result: RevokedSessions = try await client.mutation("sessions.revokeOthers", input: NoInput())

        return result.revokedCount
    }

    // the server signs every device out afterwards, this one included
    func changePassword(current: String, new: String) async throws {
        guard let client else {
            return
        }

        struct PasswordInput: Encodable {
            let currentPassword: String
            let newPassword: String
            let confirmNewPassword: String
        }

        try await client.mutation(
            "users.updatePassword",
            input: PasswordInput(currentPassword: current, newPassword: new, confirmNewPassword: new)
        )
    }

    var isPushEnabled: Bool {
        guard let address else {
            return false
        }

        return serverInfo?.pushEnabled == true && !CredentialStore.isPushMuted(for: address)
    }

    func setPushEnabled(_ enabled: Bool) async {
        guard let address else {
            return
        }

        CredentialStore.setPushMuted(!enabled, for: address)

        if enabled {
            if let token = CredentialStore.devicePushToken {
                await registerPushDevice(token)
            } else {
                hasRequestedPush = false
                await enablePushIfAvailable()
            }
        } else if let client, let pushToken {
            try? await client.mutation("notifications.unregisterDevice", input: ["token": pushToken])
            self.pushToken = nil
        }
    }

    func setOutputVolume(_ volume: Double) {
        voice?.setOutputVolume(volume)
    }

    func markAllAsRead() async {
        for channel in unreadChannels where !channel.isDm {
            await markAsRead(channel.id)
        }
    }

    func mentions() async throws -> [Message] {
        guard let client else {
            return []
        }

        struct MentionsInput: Encodable {}

        let page: MentionsPage = try await client.query("messages.getMentions", input: MentionsInput())

        return page.messages
    }

    func updateProfile(name: String, bio: String, profileColor: String) async throws {
        guard let client else {
            return
        }

        struct ProfileInput: Encodable {
            let name: String
            let profileColor: String
            let bio: String
        }

        try await client.mutation("users.update", input: ProfileInput(name: name, profileColor: profileColor, bio: bio))
    }

    enum ProfileImage: String {
        case avatar = "users.changeAvatar"
        case banner = "users.changeBanner"
    }

    // uploads the picture and sets it, or with no file removes the one there is
    func changeProfileImage(_ kind: ProfileImage, fileAt fileURL: URL?) async throws {
        struct ImageInput: Encodable {
            let fileId: String?
        }

        guard let client, let address, let token else {
            return
        }

        var fileId: String?

        if let fileURL {
            fileId = try await UploadAPI.upload(fileAt: fileURL, name: fileURL.lastPathComponent, to: address, token: token).id
        }

        try await client.mutation(kind.rawValue, input: ImageInput(fileId: fileId))
    }

    private func stopVoice() {
        screenReceiver?.stop()
        screenReceiver = nil
        isSharingScreen = false
        voice?.close()
        voice = nil
        mixingDevice = nil
        currentVoiceChannelId = nil
        cameraEnabled = false
        videoTracks = [:]
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

        client.subscribe("others.onServerSettingsUpdate") { [weak self] (settings: PublicSettings) in
            self?.settings = settings
        }

        client.subscribe("channels.onPermissionsUpdate") { [weak self] (map: [String: ChannelPermissions]) in
            self?.applyChannelPermissions(map)
        }

        client.subscribe("messages.onTyping") { [weak self] (event: TypingEvent) in
            guard let self, event.userId != self.ownUserId else {
                return
            }

            self.typing.add(event.userId, in: .init(channelId: event.channelId, parentMessageId: event.parentMessageId))
        }

        client.subscribe("messages.onThreadReplyCountUpdate") { [weak self] (update: ThreadReplyCountUpdate) in
            self?.messageStores[update.channelId]?.updateReplyCount(messageId: update.messageId, replyCount: update.replyCount)
        }

        client.subscribe("dms.onConversationOpen") { [weak self] (_: OpenedDirectMessage) in
            Task { await self?.loadDirectMessages() }
        }

        client.subscribe("friends.onUpdate") { [weak self] (_: FriendshipUpdate) in
            Task { await self?.loadFriends() }
        }

        client.subscribe("users.onJoin") { [weak self] (user: PublicUser) in
            var joined = user

            joined.status = joined.status ?? .online
            self?.usersById[user.id] = joined
        }

        // a profile change carries no status, the one already known still holds
        for path in ["users.onUpdate", "users.onCreate"] {
            client.subscribe(path) { [weak self] (user: PublicUser) in
                var updated = user

                updated.status = updated.status ?? self?.usersById[user.id]?.status
                self?.usersById[user.id] = updated
            }
        }

        client.subscribe("users.onDelete") { [weak self] (event: UserDeletedEvent) in
            self?.usersById[event.userId] = nil
        }

        for path in ["emojis.onCreate", "emojis.onUpdate"] {
            client.subscribe(path) { [weak self] (emoji: CustomEmoji) in
                guard let self else {
                    return
                }

                if let index = self.customEmojis.firstIndex(where: { $0.id == emoji.id }) {
                    self.customEmojis[index] = emoji
                } else {
                    self.customEmojis.append(emoji)
                }
            }
        }

        client.subscribe("emojis.onDelete") { [weak self] (emojiId: Int) in
            self?.customEmojis.removeAll { $0.id == emojiId }
        }

        for path in ["stickers.onCreate", "stickers.onUpdate"] {
            client.subscribe(path) { [weak self] (sticker: Sticker) in
                guard let self else {
                    return
                }

                if let index = self.stickers.firstIndex(where: { $0.id == sticker.id }) {
                    self.stickers[index] = sticker
                } else {
                    self.stickers.append(sticker)
                }
            }
        }

        client.subscribe("stickers.onDelete") { [weak self] (stickerId: Int) in
            self?.stickers.removeAll { $0.id == stickerId }
        }

        for path in ["roles.onCreate", "roles.onUpdate"] {
            client.subscribe(path) { [weak self] (role: Role) in
                self?.rolesById[role.id] = role
            }
        }

        client.subscribe("roles.onDelete") { [weak self] (roleId: Int) in
            self?.rolesById[roleId] = nil
        }

        for path in ["categories.onCreate", "categories.onUpdate"] {
            client.subscribe(path) { [weak self] (category: ChannelCategory) in
                guard let self else {
                    return
                }

                if let index = self.categories.firstIndex(where: { $0.id == category.id }) {
                    self.categories[index] = category
                } else {
                    self.categories.append(category)
                }
            }
        }

        client.subscribe("categories.onDelete") { [weak self] (categoryId: Int) in
            self?.categories.removeAll { $0.id == categoryId }
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
                let kind = VoiceStreamKey.Kind(rawValue: event.kind),
                event.channelId == self.currentVoiceChannelId,
                event.remoteId != self.ownUserId
            else {
                return
            }

            Task { await self.voice?.consume(VoiceStreamKey(kind: kind, remoteId: event.remoteId)) }
        }

        client.subscribe("voice.onProducerClosed") { [weak self] (event: VoiceProducerEvent) in
            guard
                let self,
                let kind = VoiceStreamKey.Kind(rawValue: event.kind),
                event.channelId == self.currentVoiceChannelId
            else {
                return
            }

            self.voice?.closeConsumer(VoiceStreamKey(kind: kind, remoteId: event.remoteId))
        }

        client.subscribe("voice.onReaction") { [weak self] (event: VoiceReactionEvent) in
            guard let self, event.channelId == self.currentVoiceChannelId else {
                return
            }

            self.showVoiceReaction(event.emoji, from: event.userId)
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

        if let userId = message.userId {
            typing.remove(userId, from: .init(channelId: message.channelId, parentMessageId: message.parentMessageId))
        }

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
                        lastMessageAt: message.createdAt,
                        lastMessagePreview: HTMLText.plainText(from: message.content ?? ""),
                        lastMessageUserId: message.userId,
                        group: conversation.group
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
        showReconnectingBannerLater()

        // the first retry is immediate, a socket ios dropped in the background usually comes
        // straight back, only repeated failures back off
        let delay = reconnectAttempt == 1 ? 0 : min(pow(2, Double(reconnectAttempt - 2)), 30)

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
