import SwiftUI

// the call itself: screen shares across the top, a tile per person with their camera or
// avatar, the controls along the bottom
struct VoiceRoomScreen: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.closeVoiceRoom) private var closeVoiceRoom

    @State private var isReactionBarShown = false

    private var channelName: String {
        session.currentVoiceChannelId.flatMap { session.channel($0)?.name } ?? "Voice"
    }

    private var participants: [(user: PublicUser?, state: VoiceUserState)] {
        session.currentVoiceChannelId.map { session.voiceParticipants(in: $0) } ?? []
    }

    private var screenShares: [(key: VoiceStreamKey, track: VideoTrackBox)] {
        session.videoTracks
            .filter { $0.key.kind == .screen }
            .sorted { $0.key.remoteId < $1.key.remoteId }
            .map { ($0.key, $0.value) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if isReactionBarShown {
                ReactionBar()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

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
                    }

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(participants, id: \.user?.id) { participant in
                            ParticipantTile(user: participant.user, state: participant.state)
                        }
                    }
                }
                .padding(12)
            }

            VoiceControls(onLeave: leave)
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
        .onChange(of: session.currentVoiceChannelId) { _, channelId in
            if channelId == nil {
                close()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button("Close", systemImage: "chevron.down", action: close)
                .labelStyle(.iconOnly)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.header)
                .frame(width: 40, height: 40)
                .background(Theme.listBackground, in: .circle)

            VStack(alignment: .leading, spacing: 1) {
                Label(channelName, systemImage: "speaker.wave.2.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.header)
                    .lineLimit(1)

                Text(session.displayName)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }

            Spacer()

            if session.can(.sendVoiceReaction) {
                Button("Reactions", systemImage: "face.smiling", action: toggleReactionBar)
                    .labelStyle(.iconOnly)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isReactionBarShown ? Color.black : Theme.header)
                    .frame(width: 40, height: 40)
                    .background(isReactionBarShown ? Color.white : Theme.listBackground, in: .circle)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func toggleReactionBar() {
        withAnimation(.smooth(duration: 0.25)) {
            isReactionBarShown.toggle()
        }
    }

    private func close() {
        if let closeVoiceRoom {
            closeVoiceRoom()
        } else {
            dismiss()
        }
    }

    private func leave() {
        close()

        Task {
            await session.leaveVoice()
        }
    }
}

private struct ParticipantTile: View {
    let user: PublicUser?
    let state: VoiceUserState

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

            if let track {
                VideoView(track: track, isMirrored: isOwn)
            } else {
                AvatarView(user: user, size: 64)
            }
        }
        .aspectRatio(3 / 4, contentMode: .fit)
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

                Text(user?.name ?? "Unknown")
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.55), in: .capsule)
            .padding(8)
        }
        .overlay(alignment: .topTrailing) {
            if isOwn && track != nil {
                Button("Flip Camera", systemImage: "arrow.triangle.2.circlepath.camera.fill", action: flipCamera)
                    .labelStyle(.iconOnly)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.black.opacity(0.55), in: .circle)
                    .padding(8)
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

    @Environment(SessionStore.self) private var session

    var body: some View {
        VideoView(track: track, contentMode: .scaleAspectFit)
            .aspectRatio(16 / 9, contentMode: .fit)
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

            Button("Disconnect", systemImage: "phone.down.fill", action: onLeave)
                .labelStyle(.iconOnly)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Theme.red, in: .circle)
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
        Button(title, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .font(.title3)
            .foregroundStyle(isActive ? Color.black : Theme.header)
            .frame(width: 56, height: 56)
            .background(isActive ? Color.white : Theme.listBackground, in: .circle)
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
        .scrollIndicators(.hidden)
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
