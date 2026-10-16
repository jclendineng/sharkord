import AVKit
import SwiftUI

// discord's voice channel sheet: who is in the channel, a mute toggle to join muted, and the
// join button, with the voice settings under them once the sheet is pulled up. joining goes
// straight on to the call screen
struct VoiceChannelSheet: View {
    let channel: Channel

    @Environment(SessionStore.self) private var session
    @Environment(ServerListStore.self) private var servers
    @Environment(\.dismiss) private var dismiss

    @State private var isRoomPresented = false
    @State private var isSettingsPresented = false

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

            // one scroll, so pulling up past the join bar opens the sheet onto the settings
            ScrollView {
                VStack(spacing: 0) {
                    Group {
                        if participants.isEmpty {
                            VStack(spacing: 4) {
                                Text("No one's here yet!")
                                Text("When you are ready to talk, just hop in.")
                            }
                            .font(.subheadline)
                            .foregroundStyle(Theme.text)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 12)], spacing: 16) {
                                ForEach(participants, id: \.user?.id) { participant in
                                    ParticipantBadge(user: participant.user, state: participant.state)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    // the half height sheet ends just below the join bar
                    .frame(minHeight: 200)

                    JoinBar(isConnectedHere: isConnectedHere, onJoin: join, onOpen: openRoom)

                    VoiceSheetSettings(onOpenSettings: showSettings)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Theme.listBackground)
        .sheetDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.listBackground)
        // handed over by hand: on a mac a sheet's background is worked out before it inherits
        // anything, so a sheet reading a store it was not given crashed on opening
        .sheet(isPresented: $isSettingsPresented) {
            NavigationStack {
                VoiceVideoSettingsScreen()
            }
            .environment(session)
            .environment(servers)
            .appSheet(addsClose: true)
        }
        .fullScreenCover(isPresented: $isRoomPresented) {
            VoiceRoomScreen()
                .environment(session)
                .environment(servers)
                .environment(\.closeVoiceRoom, close)
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

    private func showSettings() {
        isSettingsPresented = true
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

// discord's voice and video settings under the join bar: what can be changed right here,
// before or during the call, and the way into the rest
private struct VoiceSheetSettings: View {
    let onOpenSettings: () -> Void

    @Environment(SessionStore.self) private var session

    @State private var settings = AppSettings.shared

    private var isDeafened: Binding<Bool> {
        Binding(
            get: { session.soundMuted },
            set: { _ in toggleSound() }
        )
    }

    // a call joined without them cannot take them up until the next one
    private var footnote: String? {
        guard session.currentVoiceChannelId != nil else {
            return nil
        }

        if settings.hearYourselfInCalls && !session.canHearYourselfNow {
            return "Hear Yourself applies the next time you join a voice channel."
        }

        return "Noise Suppression applies the next time you join a voice channel."
    }

    var body: some View {
        @Bindable var settings = settings

        VStack(alignment: .leading, spacing: 8) {
            Text("VOICE & VIDEO SETTINGS")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                SettingToggle(title: "Deafen", subtitle: "Mutes everyone in the call", systemImage: "headphones", isOn: isDeafened)

                Theme.divider.frame(height: 1).padding(.leading, 52)

                HStack(spacing: 14) {
                    Image(systemName: "speaker.wave.2.fill")
                        .frame(width: 24)

                    Text("Audio Output")

                    Spacer()

                    AudioRoutePicker()
                        .frame(width: 36, height: 36)
                }
                .foregroundStyle(Theme.header)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

                Theme.divider.frame(height: 1).padding(.leading, 52)

                SettingToggle(
                    title: "Hear Yourself",
                    subtitle: "Plays your mic back to you, use headphones",
                    systemImage: "ear",
                    isOn: $settings.hearYourselfInCalls
                )
                .onChange(of: settings.hearYourselfInCalls) { _, hears in
                    session.setHearsYourself(hears)
                }

                Theme.divider.frame(height: 1).padding(.leading, 52)

                SettingToggle(
                    title: "Noise Suppression",
                    subtitle: "Cuts background noise from your mic",
                    systemImage: "waveform",
                    isOn: $settings.noiseSuppression
                )
            }
            .background(Theme.deepBackground, in: .rect(cornerRadius: 14))

            if let footnote {
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 4)
            }

            Button(action: onOpenSettings) {
                HStack(spacing: 14) {
                    Image(systemName: "gearshape.fill")
                        .frame(width: 24)

                    Text("Voice & Video Settings")

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.muted)
                }
                .foregroundStyle(Theme.header)
                .padding(14)
                .background(Theme.deepBackground, in: .rect(cornerRadius: 14))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 24)
    }

    private func toggleSound() {
        Task {
            await session.toggleSoundMuted()
        }
    }
}

private struct SettingToggle: View {
    let title: String
    let subtitle: String
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(Theme.header)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .foregroundStyle(Theme.header)
        .tint(Theme.blurple)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// the system's own picker for where the call plays, the speaker, headphones or airpods
private struct AudioRoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()

        picker.tintColor = UIColor(Theme.header)
        picker.activeTintColor = UIColor(Theme.blurple)

        return picker
    }

    func updateUIView(_ picker: AVRoutePickerView, context: Context) {}
}
