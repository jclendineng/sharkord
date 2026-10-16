import SwiftUI

// discord's call once it is lowered on a phone or an ipad: a small tile over everything that
// the finger drags anywhere and lets go into the nearest corner, and that opens the call again
// when tapped. it shows whoever else is talking, then anyone else in the call, then you
struct FloatingCallTile: View {
    private static let width: CGFloat = 96
    private static let height: CGFloat = 128

    @Environment(SessionStore.self) private var session
    @Environment(ServerListStore.self) private var servers

    @State private var corner = Corner.topTrailing
    // the drag in progress, moved by offset rather than layout so the tile follows the finger
    // without the screen laying itself out again every frame
    @State private var drag = CGSize.zero
    @State private var isRoomPresented = false

    private var shown: (user: PublicUser?, state: VoiceUserState)? {
        guard let channelId = session.currentVoiceChannelId else {
            return nil
        }

        let participants = session.voiceParticipants(in: channelId)
        let others = participants.filter { $0.user?.id != session.ownUserId }
        let talking = others.first { $0.user.map { session.speakingUserIds.contains($0.id) } ?? false }

        return talking ?? others.first ?? participants.first
    }

    private var isShownSpeaking: Bool {
        shown?.user.map { session.speakingUserIds.contains($0.id) } ?? false
    }

    var body: some View {
        GeometryReader { proxy in
            tile
                .offset(drag)
                .gesture(dragGesture(in: proxy.size))
                .onTapGesture(perform: showRoom)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: corner.alignment)
        }
        // clear of the status bar at the top and of the user bar and message bar at the bottom
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 150)
        // handed over by hand: on a mac a presentation is worked out before it inherits anything
        .fullScreenCover(isPresented: $isRoomPresented) {
            VoiceRoomScreen()
                .environment(session)
                .environment(servers)
        }
    }

    private var tile: some View {
        ZStack {
            Color(hex: shown?.user?.profileColor ?? "#5865F2")
                .opacity(0.35)
                .background(Theme.deepBackground)

            if let track {
                VideoView(track: track, isMirrored: shown?.user?.id == session.ownUserId)
            } else {
                AvatarView(user: shown?.user, size: 48)
            }
        }
        .frame(width: Self.width, height: Self.height)
        .clipShape(.rect(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .bottomLeading) {
            if shown?.state.micMuted == true {
                Image(systemName: "mic.slash.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(5)
                    .background(Theme.red, in: .circle)
                    .padding(6)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isShownSpeaking ? Theme.green : Theme.panelEdge, lineWidth: isShownSpeaking ? 3 : 1)
        }
        .animation(.easeOut(duration: 0.15), value: isShownSpeaking)
        .shadow(color: .black.opacity(0.45), radius: 12, y: 4)
        .contentShape(.rect(cornerRadius: 14))
        .accessibilityElement()
        .accessibilityLabel("Open the call")
        .accessibilityAddTraits(.isButton)
    }

    private var track: VideoTrackBox? {
        shown?.user.flatMap { session.videoTracks[VoiceStreamKey(kind: .video, remoteId: $0.id)] }
    }

    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                drag = value.translation
            }
            .onEnded { value in
                settle(value, in: size)
            }
    }

    // into the corner nearest where the flick was headed, the move and the tile's new corner in
    // one spring so it glides on from where the finger let go
    private func settle(_ value: DragGesture.Value, in size: CGSize) {
        let start = corner.origin(in: size, tile: CGSize(width: Self.width, height: Self.height))
        let landing = CGPoint(
            x: start.x + value.translation.width + value.velocity.width * 0.15 + Self.width / 2,
            y: start.y + value.translation.height + value.velocity.height * 0.15 + Self.height / 2
        )
        let isRight = landing.x > size.width / 2
        let isBottom = landing.y > size.height / 2

        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            corner = Corner(isRight: isRight, isBottom: isBottom)
            drag = .zero
        }
    }

    private func showRoom() {
        isRoomPresented = true
    }
}

private enum Corner {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing

    init(isRight: Bool, isBottom: Bool) {
        switch (isRight, isBottom) {
        case (false, false):
            self = .topLeading
        case (true, false):
            self = .topTrailing
        case (false, true):
            self = .bottomLeading
        case (true, true):
            self = .bottomTrailing
        }
    }

    var alignment: Alignment {
        switch self {
        case .topLeading:
            .topLeading
        case .topTrailing:
            .topTrailing
        case .bottomLeading:
            .bottomLeading
        case .bottomTrailing:
            .bottomTrailing
        }
    }

    // the tile's top left corner here, within the space it moves in
    func origin(in size: CGSize, tile: CGSize) -> CGPoint {
        switch self {
        case .topLeading:
            CGPoint(x: 0, y: 0)
        case .topTrailing:
            CGPoint(x: size.width - tile.width, y: 0)
        case .bottomLeading:
            CGPoint(x: 0, y: size.height - tile.height)
        case .bottomTrailing:
            CGPoint(x: size.width - tile.width, y: size.height - tile.height)
        }
    }
}
