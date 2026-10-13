import SwiftUI

struct VoiceBar: View {
    @Environment(SessionStore.self) private var session

    @State private var isRoomPresented = false

    private var channelName: String {
        session.currentVoiceChannelId.flatMap { session.channel($0)?.name } ?? ""
    }

    var body: some View {
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
        .background(Theme.listBackground, in: .rect(cornerRadius: 20))
        .fullScreenCover(isPresented: $isRoomPresented) {
            VoiceRoomScreen()
                .environment(session)
        }
    }

    private func showRoom() {
        isRoomPresented = true
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
