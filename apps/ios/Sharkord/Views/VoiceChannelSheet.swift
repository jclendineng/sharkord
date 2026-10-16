import SwiftUI

// discord's voice channel sheet: who is in the channel, a mute toggle to join muted, and the
// join button. joining goes straight on to the call screen
struct VoiceChannelSheet: View {
    let channel: Channel

    @Environment(SessionStore.self) private var session
    @Environment(ServerListStore.self) private var servers
    @Environment(\.dismiss) private var dismiss

    @State private var isRoomPresented = false

    private var participants: [(user: PublicUser?, state: VoiceUserState)] {
        session.voiceParticipants(in: channel.id)
    }

    private var isConnectedHere: Bool {
        session.currentVoiceChannelId == channel.id
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button("Close", systemImage: "chevron.down", action: close)
                    .labelStyle(.iconOnly)
                    .font(.headline)
                    .foregroundStyle(Theme.header)
                    .frame(width: 40, height: 40)
                    .background(Theme.deepBackground, in: .rect(cornerRadius: 10))

                Label(channel.name, systemImage: "speaker.wave.2.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.header)
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .frame(height: 40)
                    .background(Theme.deepBackground, in: .rect(cornerRadius: 10))

                Spacer()
            }
            .padding(16)

            Group {
                if participants.isEmpty {
                    VStack(spacing: 4) {
                        Text("No one's here yet!")
                        Text("When you are ready to talk, just hop in.")
                    }
                    .font(.subheadline)
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 12)], spacing: 16) {
                            ForEach(participants, id: \.user?.id) { participant in
                                ParticipantBadge(user: participant.user, state: participant.state)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }

            JoinBar(isConnectedHere: isConnectedHere, onJoin: join, onOpen: openRoom)
        }
        .background(Theme.listBackground)
        .sheetDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.listBackground)
        // handed over by hand: on a mac a sheet's background is worked out before it inherits
        // anything, so a sheet reading a store it was not given crashed on opening
        .fullScreenCover(isPresented: $isRoomPresented, onDismiss: close) {
            VoiceRoomScreen()
                .environment(session)
                .environment(servers)
        }
    }

    private func join() {
        Task {
            await session.joinVoice(channel.id)

            if session.currentVoiceChannelId == channel.id {
                isRoomPresented = true
            }
        }
    }

    private func openRoom() {
        isRoomPresented = true
    }

    private func close() {
        dismiss()
    }
}

private struct ParticipantBadge: View {
    let user: PublicUser?
    let state: VoiceUserState

    var body: some View {
        VStack(spacing: 6) {
            AvatarView(user: user, size: 56)
                .overlay(alignment: .bottomTrailing) {
                    if state.micMuted {
                        Image(systemName: "mic.slash.fill")
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .padding(5)
                            .background(Theme.red, in: .circle)
                    }
                }

            Text(user?.name ?? "Unknown")
                .font(.caption)
                .foregroundStyle(Theme.text)
                .lineLimit(1)
        }
    }
}

private struct JoinBar: View {
    let isConnectedHere: Bool
    let onJoin: () -> Void
    let onOpen: () -> Void

    @Environment(SessionStore.self) private var session

    var body: some View {
        HStack(spacing: 14) {
            Button(session.micMuted ? "Unmute" : "Mute", systemImage: session.micMuted ? "mic.slash.fill" : "mic.fill", action: toggleMic)
                .labelStyle(.iconOnly)
                .font(.title3)
                .foregroundStyle(session.micMuted ? Theme.red : Theme.header)
                .frame(width: 56, height: 56)
                .background(session.micMuted ? Theme.red.opacity(0.2) : Theme.deepBackground, in: .rect(cornerRadius: 14))

            if isConnectedHere {
                Button(action: onOpen) {
                    Text("Open Call")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(Theme.blurple, in: .rect(cornerRadius: 14))
                }
            } else {
                Button(action: onJoin) {
                    Group {
                        if session.isJoiningVoice {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Join Voice")
                        }
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Theme.green, in: .rect(cornerRadius: 14))
                }
                .disabled(session.isJoiningVoice)
            }
        }
        .buttonStyle(.plain)
        .padding(14)
        .background(Theme.deepBackground.opacity(0.6), in: .rect(cornerRadius: 22))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    // before joining this only decides whether the call starts muted
    private func toggleMic() {
        Task {
            await session.toggleMicMuted()
        }
    }
}
