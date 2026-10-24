import SwiftUI

struct VoiceBar: View {
    @Environment(SessionStore.self) private var session
    @Environment(ServerListStore.self) private var servers

    @Namespace private var zoom
    // where the mac's zoom starts and ends, see MacCallZoom
    @State private var frame = CGRect.zero

    private var channelName: String {
        session.currentVoiceChannelId.flatMap { session.channel($0)?.name } ?? ""
    }

    var body: some View {
        @Bindable var servers = servers

        HStack(spacing: 12) {
            Button(action: showRoom) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Voice Connected")
                            .font(.footnote.bold())
                            .foregroundStyle(Theme.green)

                        Text("\(channelName) / \(session.displayName)")
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }

                    Spacer()
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            Button(
                session.micMuted ? "Unmute" : "Mute",
                systemImage: session.micMuted ? "mic.slash.fill" : "mic.fill",
                action: toggleMic
            )
            .foregroundStyle(session.micMuted ? Theme.red : Theme.text)

            Button(
                session.soundMuted ? "Undeafen" : "Deafen",
                systemImage: session.soundMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                action: toggleSound
            )
            .foregroundStyle(session.soundMuted ? Theme.red : Theme.text)

            Button("Disconnect", systemImage: "phone.down.fill", action: leave)
                .foregroundStyle(Theme.red)
        }
        .labelStyle(.iconOnly)
        .font(.title3)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(hex: "#202125"), in: .rect(cornerRadius: 20))
        // the call grows out of the bar and shrinks back into it, a cover's own slide sent it
        // off the bottom of the screen with the bar nowhere in it
        .matchedTransitionSource(id: "call", in: zoom) { source in
            source.clipShape(.rect(cornerRadius: 20))
        }
        #if os(iOS)
        .background {
            if !Platform.isMac {
                PictureInPictureSource(track: pictureInPictureTrack)
            }
        }
        #endif
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { newFrame in
            frame = newFrame
        }
        .modifier(CallPresentation(isPresented: $servers.isCallPresented, source: frame, zoom: zoom))
    }

    // what picture in picture shows away from the app: a screen share first, then the camera of
    // whoever else is talking, then anyone else's. never the own camera, which stops in the
    // background anyway
    private var pictureInPictureTrack: VideoTrackBox? {
        let remote = session.videoTracks
            .filter { $0.key.remoteId != session.ownUserId }
            .sorted { $0.key.remoteId < $1.key.remoteId }

        if let screen = remote.first(where: { $0.key.kind == .screen }) {
            return screen.value
        }

        if let talking = remote.first(where: { $0.key.kind == .video && session.speakingUserIds.contains($0.key.remoteId) }) {
            return talking.value
        }

        return remote.first?.value
    }

    private func showRoom() {
        servers.isCallPresented = true
    }

    private func toggleMic() {
        Task { await session.toggleMicMuted() }
    }

    private func toggleSound() {
        Task { await session.toggleSoundMuted() }
    }

    private func leave() {
        Task { await session.leaveVoice() }
    }
}

// the call over everything, zooming out of the bar. the mac draws the zoom itself and opens the
// cover with no animation of its own, which would otherwise slide it up from the bottom
private struct CallPresentation: ViewModifier {
    @Environment(SessionStore.self) private var session
    @Environment(ServerListStore.self) private var servers

    @Binding var isPresented: Bool
    let source: CGRect
    let zoom: Namespace.ID

    func body(content: Content) -> some View {
        // handed over by hand: on a mac a sheet's background is worked out before it inherits
        // anything, so a sheet reading a store it was not given crashed on opening
        if Platform.isMac {
            content
                .transaction { transaction in
                    transaction.disablesAnimations = true
                }
                .fullScreen(isPresented: $isPresented) {
                    MacCallZoom(source: source, isPresented: $isPresented) {
                        VoiceRoomScreen()
                            .environment(session)
                            .environment(servers)
                    }
                }
        } else {
            content
                .fullScreen(isPresented: $isPresented) {
                    VoiceRoomScreen()
                        #if os(iOS)
                        .navigationTransition(.zoom(sourceID: "call", in: zoom))
                        #endif
                        .environment(session)
                        .environment(servers)
                }
        }
    }
}
