import SwiftUI

// the call itself: screen shares across the top, a tile per person with their camera or
// avatar, the controls along the bottom
struct VoiceRoomScreen: View {
    @Environment(SessionStore.self) private var session
    @Environment(ServerListStore.self) private var servers
    @Environment(\.dismiss) private var dismiss
    @Environment(\.closeCall) private var closeCall

    @State private var isReactionBarShown = false
    @State private var isSoundboardPresented = false
    @State private var isSettingsPresented = false
    // the tile tapped to fill the call, with everyone else in a strip under it
    @State private var focused: FocusTarget?
    // the room the tiles have between the header and the controls
    @State private var gridSize = CGSize.zero
    // each camera's shape as its tile shows it, width over height, from its first frame
    @State private var tileAspects: [Int: CGFloat] = [:]

    private var shownChannelId: Int? {
        session.currentVoiceChannelId
    }

    private var channelName: String {
        shownChannelId.flatMap { session.channel($0)?.name } ?? String(localized: "Voice")
    }

    private var participants: [VoiceParticipant] {
        shownChannelId.map { session.voiceParticipants(in: $0) } ?? []
    }

    private var screenShares: [(key: VoiceStreamKey, track: VideoTrackBox)] {
        session.videoTracks
            .filter { $0.key.kind == .screen }
            .sorted { $0.key.remoteId < $1.key.remoteId }
            .map { ($0.key, $0.value) }
    }

    // only while what was tapped is still there, someone leaving or ending a share drops back to
    // the grid
    private var shownFocus: FocusTarget? {
        switch focused {
        case .person(let userId) where participants.contains(where: { $0.userId == userId }):
            focused
        case .screen(let userId) where screenShares.contains(where: { $0.key.remoteId == userId }):
            focused
        default:
            nil
        }
    }

    private var alone: VoiceParticipant? {
        guard participants.count == 1, screenShares.isEmpty, !session.isSharingScreen else {
            return nil
        }

        return participants.first
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if isReactionBarShown {
                ReactionBar()
                    .slideTransition(from: .top)
            }

            if let shownFocus {
                focusedLayout(shownFocus)
            } else if let alone {
                // the only one there fills the call. a grid put them in half a row in the corner,
                // and a tap swapped that for the focused tile and back, the tile jumping about
                ParticipantTile(user: alone.user, state: alone.state, fills: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(12)
            } else if screenShares.isEmpty, !session.isSharingScreen {
                fittedGrid
            } else {
                grid
            }

            VoiceControls(onLeave: leave)
        }
        .background(Color.black)
        .alwaysDark()
        // the home screen's toast sits under this cover, so a camera or share failing in the call
        // said nothing
        .overlay(alignment: .top) {
            if let toastMessage = session.toastMessage {
                ErrorToast(message: toastMessage)
                    .slideTransition(from: .top)
            }
        }
        .animation(.snappy, value: session.toastMessage)
        .onChange(of: session.currentVoiceChannelId) { _, currentId in
            if currentId == nil {
                close()
            }
        }
        // handed over by hand: on a mac a presentation is worked out before it inherits anything
        .sheet(isPresented: $isSoundboardPresented) {
            SoundboardSheet()
                .environment(session)
        }
        .sheet(isPresented: $isSettingsPresented) {
            CallSettingsSheet()
                .environment(session)
                .environment(servers)
                .appSheet()
        }
    }

    // the one tapped as big as the call allows, the rest in a row under it to switch to
    private func focusedLayout(_ target: FocusTarget) -> some View {
        VStack(spacing: 10) {
            focusedTile(target)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onTapGesture {
                    setFocus(nil)
                }
                .overlay(alignment: .topLeading) {
                    Button(action: clearFocus) {
                        Label("Back to Grid", systemImage: "arrow.down.right.and.arrow.up.left")
                            .labelStyle(.iconOnly)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.black.opacity(0.55), in: .circle)
                            .padding(8)
                            .contentShape(.circle)
                    }
                }

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(screenShares.filter { target != .screen($0.key.remoteId) }, id: \.key) { share in
                        screenShareTile(share)
                            .frame(height: 112)
                    }

                    ForEach(participants.filter { target != .person($0.userId) }) { participant in
                        participantTile(participant, isCompact: true)
                            .frame(width: 84)
                    }
                }
            }
            .scrollIndicators(.never)
            .frame(height: 112)
        }
        .padding(12)
    }

    @ViewBuilder
    private func focusedTile(_ target: FocusTarget) -> some View {
        switch target {
        case .person(let userId):
            if let participant = participants.first(where: { $0.userId == userId }) {
                ParticipantTile(user: participant.user, state: participant.state, fills: true)
            }
        case .screen(let userId):
            if let share = screenShares.first(where: { $0.key.remoteId == userId }) {
                ScreenShareTile(userId: userId, track: share.track, fills: true)
            }
        }
    }

    private var grid: some View {
            ScrollView {
                VStack(spacing: 10) {
                    if session.isSharingScreen {
                        Label("You're sharing your screen", systemImage: "rectangle.on.rectangle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Theme.blurple, in: .rect(cornerRadius: Radius.control))
                    }

                    ForEach(screenShares, id: \.key, content: screenShareTile)

                    // as many columns as fit: two halves of a landscape ipad made each tile taller than
                    // the screen
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 240), spacing: 10)], spacing: 10) {
                        ForEach(participants) { participant in
                            participantTile(participant)
                        }
                    }
                }
                .padding(12)
            }
    }

    // everyone as big as the room allows, without scrolling, each tile the shape of its camera:
    // a landscape camera on a portrait screen spans the width instead of sitting letterboxed in a
    // tall tile. the split into rows that gives the pictures the most room wins
    // each tile carries its own participant, shape and height: a row looked up by position from
    // the last layout read past the end when someone left, and crashed the app
    private var fittedGrid: some View {
        let aspects = participants.map(tileAspect)
        let layout = TileRows(aspects: aspects, in: gridSize, spacing: Self.tileSpacing)
        let rows = zip(layout.rows, layout.heights).map { row, height in
            row.map { PlacedTile(participant: participants[$0], aspect: aspects[$0], height: height) }
        }

        return VStack(spacing: Self.tileSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: Self.tileSpacing) {
                    ForEach(row) { tile in
                        participantTile(tile.participant, aspect: tile.aspect)
                            .frame(width: tile.height * tile.aspect, height: tile.height)
                    }
                }
            }
        }
        // the space offered, never the tiles' own size: tiles overflowing for a moment as an ipad
        // turned were measured as the space, and the grid kept that size, cut off by the screen
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .onGeometryChange(for: CGSize.self, of: \.size) { size in
            gridSize = size
        }
        .padding(12)
        .animation(Motion.standard, value: aspects)
    }

    // a tile with no camera, or one whose first frame has not arrived, is the usual tall one
    private func tileAspect(_ participant: VoiceParticipant) -> CGFloat {
        let hasVideo = session.videoTracks[VoiceStreamKey(kind: .video, remoteId: participant.userId)] != nil

        guard hasVideo, let aspect = tileAspects[participant.userId] else {
            return 3 / 4
        }

        return aspect
    }

    private static let tileSpacing: CGFloat = 10

    // a button rather than a tap on the tile: it dims under the finger, and voiceover and a
    // keyboard have something to press. the camera flip inside it is a button of its own to a
    // finger, and an action here for voiceover, which reads the tile as one thing
    @ViewBuilder
    private func participantTile(_ participant: VoiceParticipant, isCompact: Bool = false, aspect: CGFloat = 3 / 4) -> some View {
        let name = participant.user?.name ?? String(localized: "Unknown")
        let button = Button {
            setFocus(.person(participant.userId))
        } label: {
            ParticipantTile(user: participant.user, state: participant.state, isCompact: isCompact, aspect: aspect) { shown in
                tileAspects[participant.userId] = shown
            }
        }
        .buttonStyle(CallTileButtonStyle())
        .accessibilityLabel(participant.state.micMuted ? String(localized: "\(name), muted") : name)
        .accessibilityHint("Shows them larger")

        if participant.userId == session.ownUserId && session.cameraEnabled {
            button.accessibilityAction(named: "Flip Camera", session.flipCamera)
        } else {
            button
        }
    }

    private func screenShareTile(_ share: (key: VoiceStreamKey, track: VideoTrackBox)) -> some View {
        let name = session.usersById[share.key.remoteId]?.name ?? String(localized: "Someone")

        return Button {
            setFocus(.screen(share.key.remoteId))
        } label: {
            ScreenShareTile(userId: share.key.remoteId, track: share.track)
        }
        .buttonStyle(CallTileButtonStyle())
        .accessibilityLabel("\(name)'s screen")
        .accessibilityHint("Shows it larger")
    }

    private func setFocus(_ target: FocusTarget?) {
        withAnimation(Motion.standard) {
            focused = target
        }
    }

    private func clearFocus() {
        setFocus(nil)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: close) {
                Label("Close", systemImage: "chevron.down")
                    .labelStyle(.iconOnly)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.header)
                    .frame(width: 40, height: 40)
                    .background(Theme.listBackground, in: .circle)
                    .contentShape(.circle)
            }

            // the names alone, the speaker beside them cost the channel's name its room
            VStack(alignment: .leading, spacing: 1) {
                Text(channelName)
                    .font(.headline)
                    .foregroundStyle(Theme.header)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(session.displayName)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            .layoutPriority(1)

            Spacer()

            ConnectionBadge(isRound: true)

            // the sheet's settings, which the call covers once it has started
            Button(action: showSettings) {
                Label("Voice Settings", systemImage: "gearshape.fill")
                    .labelStyle(.iconOnly)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.header)
                    .frame(width: 40, height: 40)
                    .background(Theme.listBackground, in: .circle)
                    .contentShape(.circle)
            }

            if session.supports(.soundboard), session.can(.useSoundboard) {
                Button(action: showSoundboard) {
                    Label("Soundboard", systemImage: "waveform")
                        .labelStyle(.iconOnly)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.header)
                        .frame(width: 40, height: 40)
                        .background(Theme.listBackground, in: .circle)
                        .contentShape(.circle)
                }
            }

            if session.can(.sendVoiceReaction) {
                Button(action: toggleReactionBar) {
                    Label("Reactions", systemImage: "face.smiling")
                        .labelStyle(.iconOnly)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(isReactionBarShown ? Color.black : Theme.header)
                        .frame(width: 40, height: 40)
                        .background(isReactionBarShown ? Color.white : Theme.listBackground, in: .circle)
                        .contentShape(.circle)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func showSettings() {
        isSettingsPresented = true
    }

    private func showSoundboard() {
        isSoundboardPresented = true
    }

    private func toggleReactionBar() {
        withAnimation(Motion.standard) {
            isReactionBarShown.toggle()
        }
    }

    private func close() {
        if let closeCall {
            closeCall()
        } else {
            dismiss()
        }
    }

    private func leave() {
        close()

        Task {
            await session.leaveVoiceAfterClosing()
        }
    }
}

// a tile in the call answering the finger as it lands, not once it has lifted
private struct CallTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(Motion.fade, value: configuration.isPressed)
    }
}

private struct ParticipantTile: View {
    let user: PublicUser?
    let state: VoiceUserState
    // filling the call when tapped, its own shape left to the space it is given
    var fills = false
    // a thumbnail in the strip under one, too small for the name and the flip button
    var isCompact = false
    // the tile's shape, width over height: the usual tall one, or its camera's in the fitted grid
    var aspect: CGFloat = 3 / 4
    // the camera's shape as shown, width over height, for the grid to size the tile by
    var onAspect: ((CGFloat) -> Void)?

    @Environment(SessionStore.self) private var session

    private var track: VideoTrackBox? {
        user.flatMap { session.videoTracks[VoiceStreamKey(kind: .video, remoteId: $0.id)] }
    }

    private var isOwn: Bool {
        user?.id == session.ownUserId
    }

    var body: some View {
        ZStack {
            Color(hex: user?.profileColor ?? "#5865F2")
                .opacity(0.35)

            if let track, let user {
                CameraVideo(track: track, isOwn: isOwn, onAspect: onAspect)
                    .reportsVideoSize(of: VoiceStreamKey(kind: .video, remoteId: user.id))
            } else {
                AvatarView(user: user, size: isCompact ? 36 : 64)
            }
        }
        .aspectRatio(fills ? nil : aspect, contentMode: .fit)
        .clipShape(.rect(cornerRadius: 14))
        .overlay {
            if let user, session.speakingUserIds.contains(user.id) {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Theme.green, lineWidth: 3)
            }
        }
        .animation(Motion.fade, value: user.map { session.speakingUserIds.contains($0.id) })
        .overlay {
            if let user {
                FloatingReactions(reactions: session.voiceReactions[user.id] ?? [])
            }
        }
        .overlay(alignment: .bottomLeading) {
            HStack(spacing: 4) {
                if state.micMuted {
                    Image(systemName: "mic.slash.fill")
                        .foregroundStyle(Theme.redText)
                }

                if !isCompact {
                    Text(user?.name ?? "Unknown")
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, isCompact ? 5 : 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.55), in: .capsule)
            .padding(isCompact ? 4 : 8)
            .opacity(isCompact && !state.micMuted ? 0 : 1)
        }
        .overlay(alignment: .topTrailing) {
            if isOwn && track != nil && !isCompact {
                Button(action: flipCamera) {
                    Label("Flip Camera", systemImage: "arrow.triangle.2.circlepath.camera.fill")
                        .labelStyle(.iconOnly)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(.black.opacity(0.55), in: .circle)
                        .padding(8)
                        .contentShape(.circle)
                }
            }
        }
    }

    private func flipCamera() {
        session.flipCamera()
    }
}

// a camera's picture in its tile, drawn the way facetime draws it on a phone, whose screen stays
// upright however the phone is held. pictures go out upright to gravity, a phone held sideways
// sending a wide one, shown whole rather than cropped to a tall slice
// - your own preview is fixed to the screen like a window: as the phone turns, the picture turns
//   the other way inside it and ends up upright, and nothing snaps. the front camera's is
//   mirrored, which that needs: unmirrored, a phone held sideways showed you upside down, and a
//   mirrored back camera showed the room upside down. turned by gravity it lay on its side
// - anyone else's picture turns the other way as the phone turns, so it stays upright to you
private struct CameraVideo: View {
    let track: VideoTrackBox
    let isOwn: Bool
    var onAspect: ((CGFloat) -> Void)?

    @Environment(SessionStore.self) private var session

    // the picture once turned upright, from its first frame
    @State private var videoSize: CGSize?
    // how far the phone is turned from upright, someone else's picture turned back by as much
    @State private var turn = Angle.zero

    private var isPhone: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    private var isSideways: Bool {
        abs(turn.degrees) == 90
    }

    var body: some View {
        GeometryReader { proxy in
            let drawn = isSideways ? CGSize(width: proxy.size.height, height: proxy.size.width) : proxy.size

            video(in: drawn)
                .frame(width: drawn.width, height: drawn.height)
                .rotationEffect(turn)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .onChange(of: shownAspect) { _, aspect in
            if let aspect {
                onAspect?(aspect)
            }
        }
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            followPhone()
        }
        .onAppear(perform: followPhone)
        #endif
    }

    // the picture's shape as it stands on screen, someone else's turned with the phone
    private var shownAspect: CGFloat? {
        guard let videoSize, videoSize.width > 0, videoSize.height > 0 else {
            return nil
        }

        let aspect = videoSize.width / videoSize.height

        return isSideways ? 1 / aspect : aspect
    }

    @ViewBuilder
    private func video(in size: CGSize) -> some View {
        #if os(iOS)
        if isOwn && isPhone {
            // the camera's picture as a phone held upright takes it, whichever way it is held
            VideoView(track: track, isMirrored: session.isUsingFrontCamera, drawnRotation: ._90, onVideoSize: takeVideoSize)
        } else {
            VideoView(track: track, contentMode: contentMode(in: size), isMirrored: isOwn, onVideoSize: takeVideoSize)
        }
        #else
        VideoView(track: track, contentMode: contentMode(in: size), isMirrored: isOwn, onVideoSize: takeVideoSize)
        #endif
    }

    // a picture the shape of where it is drawn fills it, one the other shape shows whole
    private func contentMode(in size: CGSize) -> ContentMode {
        guard !(isOwn && isPhone), let videoSize, size.width > 0, size.height > 0 else {
            return .fill
        }

        let isWideVideo = videoSize.width > videoSize.height
        let isWideFrame = size.width > size.height

        return isWideVideo == isWideFrame ? .fill : .fit
    }

    private func takeVideoSize(_ size: CGSize) {
        videoSize = size
    }

    #if os(iOS)
    // the screen turns with the phone, so the picture turns back by as much, as facetime's does.
    // your own preview needs none, being fixed to the screen. face up, face down and unknown say
    // nothing, the last turn stays
    private func followPhone() {
        guard isPhone, !isOwn else {
            return
        }

        let degrees: Double

        switch UIDevice.current.orientation {
        case .portrait:
            degrees = 0
        case .landscapeLeft:
            degrees = 90
        case .landscapeRight:
            degrees = -90
        case .portraitUpsideDown:
            degrees = 180
        default:
            return
        }

        withAnimation(Motion.standard) {
            turn = .degrees(degrees)
        }
    }
    #endif
}

private struct ScreenShareTile: View {
    let userId: Int
    let track: VideoTrackBox
    var fills = false

    @Environment(SessionStore.self) private var session

    // the share's own shape, a portrait ipad's or phone's too, 16:9 until its first frame
    @State private var aspectRatio: CGFloat = 16 / 9

    var body: some View {
        VideoView(track: track, contentMode: .fit, onVideoSize: takeShape)
            .reportsVideoSize(of: VoiceStreamKey(kind: .screen, remoteId: userId))
            .aspectRatio(fills ? nil : aspectRatio, contentMode: .fit)
            .background(Color.black)
            .clipShape(.rect(cornerRadius: 14))
            .overlay(alignment: .bottomLeading) {
                Label("\(session.usersById[userId]?.name ?? "Someone")'s screen", systemImage: "display")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.55), in: .capsule)
                    .padding(8)
            }
    }

    private func takeShape(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else {
            return
        }

        aspectRatio = size.width / size.height
    }
}

private struct VoiceControls: View {
    let onLeave: () -> Void

    @Environment(SessionStore.self) private var session

    var body: some View {
        HStack(spacing: 14) {
            ControlButton(
                title: session.cameraEnabled ? "Turn Off Camera" : "Turn On Camera",
                systemImage: session.cameraEnabled ? "video.fill" : "video.slash.fill",
                isActive: session.cameraEnabled,
                action: toggleCamera
            )

            ControlButton(
                title: session.isSharingScreen ? "Stop Sharing Screen" : "Share Screen",
                systemImage: session.isSharingScreen ? "rectangle.on.rectangle.slash" : "rectangle.on.rectangle",
                isActive: session.isSharingScreen,
                action: toggleScreenShare
            )

            ControlButton(
                title: session.micMuted ? "Unmute" : "Mute",
                systemImage: session.micMuted ? "mic.slash.fill" : "mic.fill",
                isActive: !session.micMuted,
                action: toggleMic
            )

            ControlButton(
                title: session.soundMuted ? "Undeafen" : "Deafen",
                systemImage: session.soundMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                isActive: !session.soundMuted,
                action: toggleSound
            )

            Button(action: onLeave) {
                Label("Disconnect", systemImage: "phone.down.fill")
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Theme.red, in: .circle)
                    .contentShape(.circle)
            }
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(Theme.deepBackground)
    }

    private func toggleCamera() {
        Task { await session.toggleCamera() }
    }

    private func toggleScreenShare() {
        Task { await session.toggleScreenShare() }
    }

    private func toggleMic() {
        Task { await session.toggleMicMuted() }
    }

    private func toggleSound() {
        Task { await session.toggleSoundMuted() }
    }
}

private struct ControlButton: View {
    let title: String
    let systemImage: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.title3)
                .foregroundStyle(isActive ? Color.black : Theme.header)
                .frame(width: 56, height: 56)
                .background(isActive ? Color.white : Theme.listBackground, in: .circle)
                .contentShape(.circle)
        }
    }
}

// the web's quick voice reactions, one tap sends one to everyone in the call
private struct ReactionBar: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(SessionStore.quickVoiceReactions, id: \.self) { emoji in
                    Button {
                        send(emoji)
                    } label: {
                        EmojiView(value: emoji, size: 26)
                            .frame(width: 46, height: 46)
                            .background(Theme.listBackground, in: .circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(emoji)
                }
            }
            .padding(.horizontal, 12)
        }
        .scrollIndicators(.never)
        .padding(.bottom, 6)
    }

    private func send(_ emoji: String) {
        Task {
            await session.sendVoiceReaction(emoji)
        }
    }
}

// each reaction rises from the bottom of the tile and fades out
private struct FloatingReactions: View {
    let reactions: [VoiceReaction]

    var body: some View {
        ZStack(alignment: .bottom) {
            ForEach(reactions) { reaction in
                FloatingReaction(reaction: reaction)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(false)
    }
}

private struct FloatingReaction: View {
    let reaction: VoiceReaction

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasRisen = false

    // spreads reactions sent together across the tile
    private var drift: CGFloat {
        CGFloat((reaction.id * 37) % 60) - 30
    }

    // with reduce motion on it fades where it lands rather than floating up the tile
    private var riseHeight: CGFloat {
        reduceMotion ? -20 : -150
    }

    var body: some View {
        EmojiView(value: reaction.emoji, size: 34)
            .offset(x: drift, y: hasRisen ? riseHeight : -20)
            .opacity(hasRisen ? 0 : 1)
            .scaleEffect(hasRisen && !reduceMotion ? 1.15 : 0.8)
            .onAppear {
                withAnimation(.easeOut(duration: 2.5)) {
                    hasRisen = true
                }
            }
    }
}

// the voice sheet's settings card in the call, with the full voice and video settings behind it
private struct CallSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var isFullSettingsShown = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VoiceSheetSettings(onOpenSettings: showFullSettings)
                    .padding(.top, 8)
            }
            .background(Theme.listBackground)
            .sheetBarBackground()
            .navigationTitle("Voice Settings")
            .inlineNavigationTitle()
            .toolbar {
                ActionToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: close)
                }
            }
            .navigationDestination(isPresented: $isFullSettingsShown) {
                VoiceVideoSettingsScreen()
            }
        }
        .sheetDetents([.medium, .large])
        .presentationBackground(Theme.listBackground)
    }

    private func showFullSettings() {
        isFullSettingsShown = true
    }

    private func close() {
        dismiss()
    }
}

private enum FocusTarget: Hashable {
    case person(Int)
    case screen(Int)
}

// how a call's 3:4 tiles fill a space: each column count is tried, and the one whose tiles come
// out widest without running past the bottom wins
// tiles of different shapes in rows, as large as the space allows without scrolling. each row is
// as tall as fills the width with its tiles side by side, and everything shrinks evenly when the
// rows are too tall together. tried for every count per row, keeping the one that shows the most
private struct PlacedTile: Identifiable {
    let participant: VoiceParticipant
    let aspect: CGFloat
    let height: CGFloat

    var id: Int {
        participant.userId
    }
}

private struct TileRows {
    let rows: [[Int]]
    let heights: [CGFloat]

    init(aspects: [CGFloat], in size: CGSize, spacing: CGFloat) {
        var best: (rows: [[Int]], heights: [CGFloat], area: CGFloat) = ([], [], -1)

        guard size.width > 0, size.height > 0, !aspects.isEmpty else {
            let all = Array(aspects.indices)

            rows = all.isEmpty ? [] : [all]
            heights = all.isEmpty ? [] : [1]
            return
        }

        for perRow in 1...aspects.count {
            let rows = stride(from: 0, to: aspects.count, by: perRow).map { start in
                Array(start..<min(start + perRow, aspects.count))
            }

            var heights = rows.map { row in
                let widths = row.reduce(CGFloat(0)) { $0 + aspects[$1] }

                return (size.width - spacing * CGFloat(row.count - 1)) / widths
            }

            let gaps = spacing * CGFloat(rows.count - 1)
            let total = heights.reduce(0, +)

            if total + gaps > size.height {
                let scale = max(size.height - gaps, 0) / total

                heights = heights.map { $0 * scale }
            }

            let area = zip(rows, heights).reduce(CGFloat(0)) { sum, pair in
                sum + pair.0.reduce(CGFloat(0)) { $0 + pair.1 * pair.1 * aspects[$1] }
            }

            if area > best.area {
                best = (rows, heights, area)
            }
        }

        rows = best.rows
        heights = best.heights
    }
}
