import AVKit
import SwiftUI

// discord's voice channel sheet: who is in the channel, a mute toggle to join muted, and the
// join button, with the voice settings under them once the sheet is pulled up. joining puts the
// sheet away and the call grows out of the call bar, so it always goes back into the bar
struct VoiceChannelSheet: View {
    let channel: Channel

    @Environment(SessionStore.self) private var session
    @Environment(ServerListStore.self) private var servers
    @Environment(\.dismiss) private var dismiss

    @State private var isSettingsPresented = false
    // the call opens once the sheet is gone: the bar presents it, and could not while this sheet
    // was still up
    @State private var opensCall = false
    @State private var detent = GrowingSheet.resting

    private var participants: [(user: PublicUser?, state: VoiceUserState)] {
        session.voiceParticipants(in: channel.id)
    }

    private var isConnectedHere: Bool {
        session.currentVoiceChannelId == channel.id
    }

    // discord's on a phone: a short sheet that a swipe grows into the settings, the join box
    // becoming the sheet as it rises. the system drags the sheet, the contents only follow its
    // height, so nothing fights the finger. a mac and an ipad draw the sheet as a form in the
    // middle with no heights to move between, so there it stays one list. asked of the device,
    // not the size class: inside that form an ipad is compact too, and got the phone's sheet
    private var growsIntoSettings: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
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
        .modifier(VoiceSheetDetents(growsIntoSettings: growsIntoSettings, detent: $detent))
        // the join box carries the grip there, as discord's does
        .presentationDragIndicator(growsIntoSettings ? .hidden : .visible)
        .presentationBackground(Theme.listBackground)
        .onDisappear(perform: openCallIfAsked)
        // handed over by hand: on a mac a sheet's background is worked out before it inherits
        // anything, so a sheet reading a store it was not given crashed on opening
        .sheet(isPresented: $isSettingsPresented) {
            NavigationStack {
                VoiceVideoSettingsScreen()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close", systemImage: "xmark", action: hideSettings)
                        }
                    }
            }
            .environment(session)
            .environment(servers)
            .appSheet()
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

            if session.currentVoiceChannelId == channel.id {
                ConnectionBadge()
            }
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

    // the join button spins until the call is up, then the sheet goes and the bar opens the call
    private func join() {
        Task {
            await session.joinVoice(channel.id)

            if session.currentVoiceChannelId == channel.id {
                openRoom()
            }
        }
    }

    private func openRoom() {
        opensCall = true
        dismiss()
    }

    private func openCallIfAsked() {
        if opensCall {
            servers.isCallPresented = true
        }
    }

    private func showSettings() {
        isSettingsPresented = true
    }

    private func hideSettings() {
        isSettingsPresented = false
    }

    private func close() {
        dismiss()
    }
}

// open, a pull down only takes the sheet back to its short height, however hard the flick:
// closing is for a swipe from there, as discord's is
private struct VoiceSheetDetents: ViewModifier {
    let growsIntoSettings: Bool

    @Binding var detent: PresentationDetent

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
struct VoiceSheetSettings: View {
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

        VStack(alignment: .leading, spacing: 20) {
            // the three a call reaches for most, lit like the call bar's buttons when on
            HStack(spacing: 10) {
                QuickTile(title: "Deafen", systemImage: session.soundMuted ? "headphones.slash" : "headphones", isOn: isDeafened)

                OutputTile()

                QuickTile(
                    title: "No Video",
                    systemImage: settings.incomingVideoOff ? "video.slash.fill" : "video.fill",
                    isOn: $settings.incomingVideoOff
                )
                .onChange(of: settings.incomingVideoOff) { _, off in
                    Task {
                        await session.setIncomingVideoOff(off)
                    }
                }
            }

            SettingsCard(title: "Audio") {
                SettingToggle(
                    title: "Noise Suppression",
                    subtitle: "Cuts background noise from your mic",
                    systemImage: "waveform",
                    isOn: $settings.noiseSuppression
                )

                CardDivider()

                SettingToggle(
                    title: "Hear Yourself",
                    subtitle: "Plays your mic back to you, use headphones",
                    systemImage: "ear",
                    isOn: $settings.hearYourselfInCalls
                )
                .onChange(of: settings.hearYourselfInCalls) { _, hears in
                    session.setHearsYourself(hears)
                }

                CardDivider()

                // ios fills these panels only for a mic and a camera in use, before that they
                // came up empty
                SystemPanelRow(
                    title: "Mic Mode",
                    subtitle: "Voice Isolation or Wide Spectrum",
                    systemImage: "mic.badge.plus",
                    panel: .microphoneModes,
                    unavailableReason: session.currentVoiceChannelId == nil ? "Join a voice channel first" : nil
                )
            }

            SettingsCard(title: "Video", footnote: footnote) {
                VideoEffectsRow(unavailableReason: session.cameraEnabled ? nil : "Turn on your camera first")
            }

            Button(action: onOpenSettings) {
                HStack(spacing: 14) {
                    SettingIcon(systemImage: "slider.horizontal.3")

                    Text("All Voice & Video Settings")

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.muted)
                }
                .foregroundStyle(Theme.header)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Theme.deepBackground, in: .rect(cornerRadius: 16))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 24)
    }

    private func toggleSound() {
        Task {
            await session.toggleSoundMuted()
        }
    }
}

struct SettingToggle: View {
    let title: String
    let subtitle: String
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 14) {
                SettingIcon(systemImage: systemImage)

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

// a row's symbol on a soft square, so a card of settings reads as a list of things at a glance
struct SettingIcon: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.header)
            .frame(width: 32, height: 32)
            .background(Theme.listBackground, in: .rect(cornerRadius: 9))
    }
}

// a titled group of rows on one rounded card, with a note under it when there is one
struct SettingsCard<Content: View>: View {
    let title: String
    var footnote: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content
            }
            .background(Theme.deepBackground, in: .rect(cornerRadius: 16))

            if let footnote {
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 4)
            }
        }
    }
}

struct CardDivider: View {
    var body: some View {
        Theme.divider
            .frame(height: 1)
            .padding(.leading, 60)
    }
}

// a big square switch, white with a dark symbol while on, as the call bar's are
private struct QuickTile: View {
    let title: String
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        Button(action: toggle) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(height: 28)

                Text(title)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isOn ? Color.black : Theme.header)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isOn ? Color.white : Theme.deepBackground, in: .rect(cornerRadius: 16))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isOn)
        .accessibilityValue(isOn ? "On" : "Off")
    }

    private func toggle() {
        withAnimation(.snappy(duration: 0.2)) {
            isOn.toggle()
        }
    }
}

// the system's route picker as a tile: speaker, earpiece, headphones or a car
private struct OutputTile: View {
    var body: some View {
        VStack(spacing: 8) {
            AudioRoutePicker()
                .frame(width: 32, height: 28)

            Text("Output")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.header)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Theme.deepBackground, in: .rect(cornerRadius: 16))
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

// the system's own panel for the mic or the camera, the ones control center shows during a call
private struct SystemPanelRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let panel: AVCaptureDevice.SystemUserInterface
    // why it cannot open yet, shown in place of the subtitle
    var unavailableReason: String?

    var body: some View {
        Button(action: show) {
            HStack(spacing: 14) {
                SettingIcon(systemImage: systemImage)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)

                    Text(unavailableReason ?? subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }

                Spacer()

                Image(systemName: "arrow.up.forward.app")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.muted)
            }
            .foregroundStyle(Theme.header)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(.rect)
            .opacity(unavailableReason == nil ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(unavailableReason != nil)
    }

    private func show() {
        AVCaptureDevice.showSystemUserInterface(panel)
    }
}

// opens the app's own video effects sheet, once there is a camera for them to work on
private struct VideoEffectsRow: View {
    let unavailableReason: String?

    @Environment(SessionStore.self) private var session
    @Environment(ServerListStore.self) private var servers

    @State private var isPresented = false

    var body: some View {
        Button(action: show) {
            HStack(spacing: 14) {
                SettingIcon(systemImage: "camera.filters")

                VStack(alignment: .leading, spacing: 2) {
                    Text("Video Effects")

                    Text(unavailableReason ?? "Reactions, Center Stage, Portrait and Studio Light")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.muted)
            }
            .foregroundStyle(Theme.header)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(.rect)
            .opacity(unavailableReason == nil ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(unavailableReason != nil)
        .sheet(isPresented: $isPresented) {
            VideoEffectsSheet()
                .environment(session)
                .environment(servers)
                .appSheet()
        }
    }

    private func show() {
        isPresented = true
    }
}
