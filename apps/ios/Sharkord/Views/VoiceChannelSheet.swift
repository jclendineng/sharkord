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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var isRoomPresented = false
    @State private var isSettingsPresented = false

    private var participants: [(user: PublicUser?, state: VoiceUserState)] {
        session.voiceParticipants(in: channel.id)
    }

    private var isConnectedHere: Bool {
        session.currentVoiceChannelId == channel.id
    }

    // discord's on a phone: a short sheet that a swipe grows into the settings, the join box
    // becoming the sheet as it rises. the system drags the sheet, the contents only follow its
    // height, so nothing fights the finger. a mac and a wide ipad draw the sheet as a form in
    // the middle with no heights to move between, so there it stays one list
    private var growsIntoSettings: Bool {
        horizontalSizeClass == .compact && !ProcessInfo.processInfo.isiOSAppOnMac
    }

    var body: some View {
        Group {
            if growsIntoSettings {
                growingLayout
            } else {
                listLayout
            }
        }
        .background(Theme.listBackground)
        .modifier(VoiceSheetDetents(growsIntoSettings: growsIntoSettings))
        // the join box carries the grip there, as discord's does
        .presentationDragIndicator(growsIntoSettings ? .hidden : .visible)
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

    private var listLayout: some View {
        VStack(spacing: 0) {
            header

            // one scroll, so pulling up past the join bar opens the sheet onto the settings
            ScrollView {
                VStack(spacing: 0) {
                    participantsArea
                        // the half height sheet ends just below the join bar
                        .frame(minHeight: 200)

                    JoinBar(isConnectedHere: isConnectedHere, onJoin: join, onOpen: openRoom)

                    VoiceSheetSettings(onOpenSettings: showSettings)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var growingLayout: some View {
        GeometryReader { proxy in
            let progress = GrowingSheet.progress(height: proxy.size.height)
            let channelHeight = GrowingSheet.channelHeight * (1 - progress)

            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    header

                    participantsArea
                        .frame(maxHeight: .infinity)
                }
                .frame(height: GrowingSheet.channelHeight, alignment: .top)
                .frame(height: channelHeight, alignment: .bottom)
                .clipped()
                .opacity(1 - progress)

                JoinBar(isConnectedHere: isConnectedHere, onJoin: join, onOpen: openRoom, showsGrip: true, boxOpacity: 1 - progress)

                ScrollView {
                    VoiceSheetSettings(onOpenSettings: showSettings)
                }
                .scrollBounceBehavior(.basedOnSize)
                .opacity(progress)
            }
        }
    }

    private var header: some View {
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
    }

    @ViewBuilder
    private var participantsArea: some View {
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

// open, a pull down only takes the sheet back to its short height, however hard the flick:
// closing is for a swipe from there, as discord's is
private struct VoiceSheetDetents: ViewModifier {
    let growsIntoSettings: Bool

    @State private var detent = GrowingSheet.resting

    func body(content: Content) -> some View {
        if growsIntoSettings {
            content
                .presentationDetents([GrowingSheet.resting, GrowingSheet.open], selection: $detent)
                .interactiveDismissDisabled(detent != GrowingSheet.resting)
        } else {
            content.sheetDetents([.medium, .large])
        }
    }
}

// the two heights of the phone's sheet and how far it has moved between them, both counted
// above the home indicator's strip as the sheet's contents are
private enum GrowingSheet {
    // the header, the channel and the join box
    static let restingHeight: CGFloat = 300
    // what of the resting sheet the header and the channel take, the join box has the rest
    static let channelHeight: CGFloat = 190

    static let resting = PresentationDetent.height(restingHeight)
    static let open = PresentationDetent.custom(OpenDetent.self)

    static func progress(height: CGFloat) -> CGFloat {
        let openHeight = OpenDetent.height

        guard openHeight > restingHeight else {
            return 0
        }

        return min(max((height - restingHeight) / (openHeight - restingHeight), 0), 1)
    }
}

// discord's open sheet, about two thirds of the screen. it keeps the height it last worked out,
// so the contents can tell how far between the two the sheet stands
private struct OpenDetent: CustomPresentationDetent {
    static var height: CGFloat = 0

    static func height(in context: Context) -> CGFloat? {
        let openHeight = (context.maxDetentValue * 0.68).rounded()

        height = openHeight

        return openHeight
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
    var showsGrip = false
    // the box around it, which melts into the sheet as the sheet grows around it
    var boxOpacity = 1.0

    @Environment(SessionStore.self) private var session

    var body: some View {
        VStack(spacing: 10) {
            if showsGrip {
                Capsule()
                    .fill(Theme.muted.opacity(0.6))
                    .frame(width: 36, height: 5)
            }

            row
        }
        .padding(14)
        .background(Theme.deepBackground.opacity(0.6 * boxOpacity), in: .rect(cornerRadius: 22))
        .padding(.horizontal, 12 * boxOpacity)
        .padding(.bottom, 8)
    }

    private var row: some View {
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
