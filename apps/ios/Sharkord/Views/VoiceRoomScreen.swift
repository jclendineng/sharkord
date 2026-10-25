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

    private var shownChannelId: Int? {
        session.currentVoiceChannelId
    }

    private var channelName: String {
        shownChannelId.flatMap { session.channel($0)?.name } ?? "Voice"
    }

    private var participants: [(user: PublicUser?, state: VoiceUserState)] {
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
        case .person(let userId) where participants.contains(where: { $0.user?.id == userId }):
            focused
        case .screen(let userId) where screenShares.contains(where: { $0.key.remoteId == userId }):
            focused
        default:
            nil
        }
    }

    private var alone: (user: PublicUser?, state: VoiceUserState)? {
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
                    .transition(.move(edge: .top).combined(with: .opacity))
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
        .preferredColorScheme(.dark)
        // the home screen's toast sits under this cover, so a camera or share failing in the call
        // said nothing
        .overlay(alignment: .top) {
            if let toastMessage = session.toastMessage {
                ErrorToast(message: toastMessage)
                    .transition(.move(edge: .top).combined(with: .opacity))
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
                        ScreenShareTile(userId: share.key.remoteId, track: share.track)
                            .frame(height: 112)
                            .onTapGesture {
                                setFocus(.screen(share.key.remoteId))
                            }
                    }

                    ForEach(participants.filter { target != .person($0.user?.id ?? -1) }, id: \.user?.id) { participant in
                        ParticipantTile(user: participant.user, state: participant.state, isCompact: true)
                            .frame(width: 84)
                            .onTapGesture {
                                if let userId = participant.user?.id {
                                    setFocus(.person(userId))
                                }
                            }
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
            if let participant = participants.first(where: { $0.user?.id == userId }) {
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
                            .background(Theme.blurple, in: .rect(cornerRadius: 12))
                    }

                    ForEach(screenShares, id: \.key) { share in
                        ScreenShareTile(userId: share.key.remoteId, track: share.track)
                            .onTapGesture {
                                setFocus(.screen(share.key.remoteId))
                            }
                    }

                    // as many columns as fit: two halves of a landscape ipad made each tile taller than
                    // the screen
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 240), spacing: 10)], spacing: 10) {
                        ForEach(participants, id: \.user?.id, content: participantTile)
                    }
                }
                .padding(12)
            }
    }

    // everyone as big as the room allows, without scrolling: the column count that gives each
    // tile the most room, the tiles centred in what is left over
    private var fittedGrid: some View {
        let layout = TileLayout(count: participants.count, in: gridSize, spacing: Self.tileSpacing)
        let columns = Array(repeating: GridItem(.fixed(layout.tileWidth), spacing: Self.tileSpacing), count: layout.columns)

        return LazyVGrid(columns: columns, spacing: Self.tileSpacing) {
            ForEach(participants, id: \.user?.id, content: participantTile)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGSize.self, of: \.size) { size in
            gridSize = size
        }
        .padding(12)
    }

    private static let tileSpacing: CGFloat = 10

    private func participantTile(_ participant: (user: PublicUser?, state: VoiceUserState)) -> some View {
        ParticipantTile(user: participant.user, state: participant.state)
            .onTapGesture {
                if let userId = participant.user?.id {
                    setFocus(.person(userId))
                }
            }
    }

    private func setFocus(_ target: FocusTarget?) {
        withAnimation(.snappy(duration: 0.3)) {
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

            if session.can(.useSoundboard) {
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
        withAnimation(.smooth(duration: 0.25)) {
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

private struct ParticipantTile: View {
    let user: PublicUser?
    let state: VoiceUserState
    // filling the call when tapped, its own shape left to the space it is given
    var fills = false
    // a thumbnail in the strip under one, too small for the name and the flip button
    var isCompact = false

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
                VideoView(track: track, isMirrored: isOwn)
                    .reportsVideoSize(of: VoiceStreamKey(kind: .video, remoteId: user.id))
            } else {
                AvatarView(user: user, size: isCompact ? 36 : 64)
            }
        }
        .aspectRatio(fills ? nil : 3 / 4, contentMode: .fit)
        .clipShape(.rect(cornerRadius: 14))
        .overlay {
            if let user, session.speakingUserIds.contains(user.id) {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Theme.green, lineWidth: 3)
            }
        }
        .animation(.easeOut(duration: 0.15), value: user.map { session.speakingUserIds.contains($0.id) })
        .overlay {
            if let user {
                FloatingReactions(reactions: session.voiceReactions[user.id] ?? [])
            }
        }
        .overlay(alignment: .bottomLeading) {
            HStack(spacing: 4) {
                if state.micMuted {
                    Image(systemName: "mic.slash.fill")
                        .foregroundStyle(Theme.red)
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

private struct ScreenShareTile: View {
    let userId: Int
    let track: VideoTrackBox
    var fills = false

    @Environment(SessionStore.self) private var session

    var body: some View {
        VideoView(track: track, contentMode: .fit)
            .reportsVideoSize(of: VoiceStreamKey(kind: .screen, remoteId: userId))
            .aspectRatio(fills ? nil : 16 / 9, contentMode: .fit)
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

    @State private var hasRisen = false

    // spreads reactions sent together across the tile
    private var drift: CGFloat {
        CGFloat((reaction.id * 37) % 60) - 30
    }

    var body: some View {
        EmojiView(value: reaction.emoji, size: 34)
            .offset(x: drift, y: hasRisen ? -150 : -20)
            .opacity(hasRisen ? 0 : 1)
            .scaleEffect(hasRisen ? 1.15 : 0.8)
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
private struct TileLayout {
    let columns: Int
    let tileWidth: CGFloat

    init(count: Int, in size: CGSize, spacing: CGFloat) {
        var best = (columns: 1, width: CGFloat(0))

        for columns in 1...max(count, 1) {
            let rows = CGFloat((count + columns - 1) / columns)
            let widthByRow = (size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
            let widthByHeight = (size.height - spacing * (rows - 1)) / rows * 3 / 4
            let width = min(widthByRow, widthByHeight)

            if width > best.width {
                best = (columns, width)
            }
        }

        columns = best.columns
        tileWidth = max(best.width, 1)
    }
}
