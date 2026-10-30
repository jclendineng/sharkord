import AVFoundation
import AVKit
import SwiftUI

struct VoiceVideoSettingsScreen: View {
    @Environment(ServerListStore.self) private var servers

    @State private var settings = AppSettings.shared
    @State private var tester = MicrophoneTester()
    @State private var hearYourself = false
    @State private var isCameraPreviewOn = false
    @State private var cameraPosition = AVCaptureDevice.Position.front
    @State private var cameras: [AVCaptureDevice] = []
    #if os(iOS)
    @State private var inputs: [AVAudioSessionPortDescription] = []
    #else
    @State private var inputs: [AudioInputPreference.Input] = []
    #endif
    // whether the input device lets its gain be set, most built in and usb mics on a mac do not
    @State private var canSetInputGain = false
    // the mic mode picked in control center, which the system changes without telling the app
    @State private var micMode = AVCaptureDevice.activeMicrophoneMode

    private let isOnMac = Platform.isMac

    private var isInCall: Bool {
        servers.voiceSession != nil
    }

    // a call joined without it has webrtc's own device, which cannot play the mic back
    private var hearYourselfFooter: String {
        let note = String(localized: "Plays your mic back to you while you talk. Use headphones to avoid feedback.")

        if let voiceSession = servers.voiceSession, !voiceSession.canHearYourselfNow {
            return note + " Turning it on applies the next time you join a voice channel."
        }

        return note
    }

    private var micFooter: String {
        if isInCall {
            return String(localized: "Leave the voice channel to test your mic.")
        }

        return String(localized: "Talk and watch the meter move. Use headphones to hear yourself without feedback.")
    }

    var body: some View {
        @Bindable var settings = settings

        SettingsForm {
            // discord's input and output devices. a mac has no route picker of its own in the
            // app, and many have no mic either, a headset's is used once one is plugged in
            if isOnMac {
                Section {
                    Picker("Input Device", selection: $settings.inputDeviceId) {
                        Text("Automatic").tag(String?.none)

                        ForEach(inputs, id: \.uid) { input in
                            #if os(iOS)
                            Text(input.portName).tag(Optional(input.uid))
                            #else
                            Text(input.name).tag(Optional(input.uid))
                            #endif
                        }
                    }

                    HStack {
                        Text("Output Device")
                            .foregroundStyle(Theme.header)

                        Spacer()

                        OutputDevicePicker()
                            .frame(width: 36, height: 36)
                    }

                    if canSetInputGain {
                        VolumeSlider(title: "Input Volume", value: $settings.inputGain, range: 0...1, lowIcon: "mic.slash.fill", highIcon: "mic.fill")
                    }
                } header: {
                    SectionTitle("Devices")
                } footer: {
                    Text("Automatic uses a headset's mic whenever one is plugged in.")
                        .wrappingFooter()
                }
            }

            Section {
                if isOnMac {
                    Picker("Input Mode", selection: $settings.pushToTalk) {
                        Text("Voice Activity").tag(false)
                        Text("Push to Talk").tag(true)
                    }

                    if settings.pushToTalk {
                        Picker("Talk Key", selection: $settings.pushToTalkKey) {
                            ForEach(PushToTalkKey.allCases) { key in
                                Text(key.title).tag(key)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Mic Test")
                        .foregroundStyle(Theme.header)

                    MicLevelMeter(level: tester.level)

                    HStack {
                        Button(tester.isRunning ? "Stop Testing" : "Let's Check", action: toggleMicTest)
                            .font(.subheadline.weight(.semibold))
                            .buttonStyle(.borderedProminent)
                            .buttonBorderShape(.capsule)
                            .tint(tester.isRunning ? Theme.red : Theme.blurple)
                            .disabled(isInCall)

                        Spacer()

                        Toggle("Hear Yourself", isOn: $hearYourself)
                            .font(.subheadline)
                            .fixedSize()
                            .disabled(tester.isRunning)
                    }
                }
                .padding(.vertical, 6)

                if let errorMessage = tester.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(Theme.redText)
                }
            } header: {
                SectionTitle("Input")
            } footer: {
                Text(micFooter)
                    .wrappingFooter()
            }

            Section {
                VolumeSlider(title: "Volume", value: $settings.outputVolume, range: 0...2)

                // a phone's choice between its earpiece and speaker, a mac has neither
                if !isOnMac {
                    DetailToggle(
                        title: "Use Speaker by Default",
                        subtitle: "Calls start on the loudspeaker instead of the earpiece.",
                        isOn: $settings.speakerByDefault
                    )
                }
            } header: {
                SectionTitle("Output")
            }

            Section {
                VolumeSlider(title: "Soundboard Volume", value: $settings.soundboardVolume, range: 0...1)
            } header: {
                SectionTitle("Soundboard")
            } footer: {
                Text("Controls how loud sounds are for you personally.")
                    .wrappingFooter()
            }

            Section {
                RadioRow(title: "Standard", isSelected: settings.noiseSuppression) {
                    settings.noiseSuppression = true
                }

                RadioRow(title: "None", isSelected: !settings.noiseSuppression) {
                    settings.noiseSuppression = false
                }
            } header: {
                SectionTitle("Noise Suppression")
            } footer: {
                VoiceIsolationHint(isOn: micMode == .voiceIsolation, isMicInUse: isInCall || tester.isRunning)
            }

            Section {
                DetailToggle(
                    title: "Echo Cancellation",
                    subtitle: "Stops others hearing themselves through your speaker.",
                    isOn: $settings.echoCancellation
                )

                DetailToggle(
                    title: "Automatic Gain Control",
                    subtitle: "Automatically adjusts your mic volume to keep it clear and consistent.",
                    isOn: $settings.autoGainControl
                )

                DetailToggle(
                    title: "Hear Yourself in Calls",
                    subtitle: hearYourselfFooter,
                    isOn: $settings.hearYourselfInCalls
                )
                .onChange(of: settings.hearYourselfInCalls) { _, hears in
                    servers.voiceSession?.setHearsYourself(hears)
                }
            } header: {
                SectionTitle("Voice Processing")
            } footer: {
                Text("Noise suppression, echo cancellation and gain control apply the next time you join a voice channel.")
                    .wrappingFooter()
            }

            Section {
                Picker("Quality", selection: $settings.streamQuality) {
                    Text("Default (720p)").tag(AppSettings.StreamQuality.standard)
                    Text("High (1080p)").tag(AppSettings.StreamQuality.high)
                }

                DetailToggle(
                    title: "Share App Audio",
                    subtitle: "Beta. Sends the sound of what you share, like a game, mixed into your voice. Takes effect the next time you join.",
                    isOn: $settings.shareAppAudio
                )
            } header: {
                SectionTitle("Screen Share")
            }

            Section {
                #if os(macOS)
                Picker("Camera", selection: $settings.cameraDeviceId) {
                    Text("Automatic").tag(String?.none)

                    ForEach(cameras, id: \.uniqueID) { camera in
                        Text(camera.localizedName).tag(Optional(camera.uniqueID))
                    }
                }
                #endif

                if isCameraPreviewOn {
                    #if os(macOS)
                    // a mac camera films landscape
                    CameraPreview(position: cameraPosition, deviceId: settings.cameraDeviceId)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .clipShape(.rect(cornerRadius: 12))
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    #else
                    CameraPreview(position: cameraPosition, deviceId: nil)
                        .aspectRatio(3 / 4, contentMode: .fit)
                        .clipShape(.rect(cornerRadius: 12))
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))

                    Button("Flip Camera", action: flipCamera)
                    #endif
                }

                Button(isCameraPreviewOn ? "Stop Video Preview" : "Test Video", action: toggleCameraPreview)
                    .disabled(isInCall)
            } header: {
                SectionTitle("Video")
            } footer: {
                if isInCall {
                    Text("Leave the voice channel to preview your camera.")
                        .wrappingFooter()
                }
            }
        }
        .settingsListStyle()
        .navigationTitle("Voice & Video")
        .inlineNavigationTitle()
        .onChange(of: settings.outputVolume) { _, volume in
            servers.voiceSession?.setOutputVolume(volume)
            tester.setOutputVolume(volume)
        }
        .onChange(of: settings.streamQuality) { _, quality in
            servers.voiceSession?.setStreamQuality(quality)
        }
        .onChange(of: settings.inputDeviceId) { _, inputDeviceId in
            AudioInputPreference.apply()
            #if os(macOS)
            servers.voiceSession?.setInputDevice(inputDeviceId)
            canSetInputGain = AudioInputPreference.canSetInputGain
            #endif
        }
        #if os(macOS)
        .onChange(of: settings.cameraDeviceId) { _, cameraDeviceId in
            servers.voiceSession?.useCamera(cameraDeviceId)
        }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureDevice.wasConnectedNotification)) { _ in
            cameras = VoiceConnection.cameras
        }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureDevice.wasDisconnectedNotification), perform: cameraDisconnected)
        #endif
        .onChange(of: settings.inputGain) {
            AudioInputPreference.apply()
        }
        .onChange(of: settings.pushToTalk) {
            servers.voiceSession?.applyPushToTalk()
        }
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { _ in
            loadInputs()
        }
        #else
        .onReceive(NotificationCenter.default.publisher(for: AudioInputPreference.inputsDidChange)) { _ in
            loadInputs()
        }
        #endif
        .task {
            loadInputs()
            cameras = VoiceConnection.cameras
        }
        .task {
            while !Task.isCancelled {
                micMode = AVCaptureDevice.activeMicrophoneMode

                try? await Task.sleep(for: .seconds(1))
            }
        }
        .onDisappear {
            tester.stop()
        }
    }

    // the session only lists its inputs once it is active for recording, which a call already is
    private func loadInputs() {
        #if os(iOS)
        guard isOnMac else {
            return
        }

        let session = AVAudioSession.sharedInstance()

        // mixing with others, so opening the screen does not stop music playing elsewhere
        if session.category != .playAndRecord, !isInCall {
            try? session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetoothHFP, .mixWithOthers])
            try? session.setActive(true)
        }

        inputs = session.availableInputs ?? []
        canSetInputGain = session.isInputGainSettable
        #else
        inputs = AudioInputPreference.inputs()
        canSetInputGain = AudioInputPreference.canSetInputGain
        #endif
    }

    private func toggleMicTest() {
        if tester.isRunning {
            tester.stop()
            return
        }

        Task {
            await tester.start(playback: hearYourself)
        }
    }

    private func toggleCameraPreview() {
        if isCameraPreviewOn {
            isCameraPreviewOn = false
            return
        }

        Task {
            isCameraPreviewOn = await AVCaptureDevice.requestAccess(for: .video)
        }
    }

    #if os(macOS)
    // the preview stops with its camera rather than holding the last frame. automatic's pick is
    // not known here, so any camera leaving stops it
    private func cameraDisconnected(_ notification: Notification) {
        cameras = VoiceConnection.cameras

        guard let device = notification.object as? AVCaptureDevice else {
            return
        }

        let pickedId = settings.cameraDeviceId

        if pickedId == nil || pickedId == device.uniqueID {
            isCameraPreviewOn = false
        }
    }
    #endif

    private func flipCamera() {
        cameraPosition = cameraPosition == .front ? .back : .front
    }
}

// discord's section titles: sentence case and a size up, not the system's small capitals
private struct SectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    // a mac's grouped form draws its own section headers, bold like the other settings pages'
    @ViewBuilder
    var body: some View {
        if Platform.isMac {
            Text(title)
        } else {
            Text(title)
                .font(.body)
                .foregroundStyle(Theme.muted)
                .textCase(nil)
                .padding(.leading, -4)
        }
    }
}

// discord's note under its noise suppression: apple's voice isolation beats any of these, so it
// says whether it is on and opens the panel that turns it on. the panel only has the modes while
// the mic is in use, in a call or the mic test, so otherwise it says where to find it instead
private struct VoiceIsolationHint: View {
    let isOn: Bool
    let isMicInUse: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isOn {
                Label("Voice Isolation is on. Apple's own suppression already cleans your mic, so Standard adds little.", systemImage: "checkmark.circle.fill")
                    .labelStyle(HintLabelStyle(tint: Theme.green))
            } else {
                Label("For the strongest noise suppression, turn on Voice Isolation. It is Apple's own and runs on this device.", systemImage: "waveform.badge.mic")
                    .labelStyle(HintLabelStyle(tint: Theme.blurple))

                if isMicInUse {
                    Button("Open Mic Mode", action: openMicModes)
                        .font(.footnote.weight(.semibold))
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .tint(Theme.blurple)
                } else {
                    Text("Start the mic test or join a voice channel, then pick it under Mic Mode here or in Control Center.")
                }
            }
        }
        .padding(.top, 4)
        .wrappingFooter()
    }

    private func openMicModes() {
        AVCaptureDevice.showSystemUserInterface(.microphoneModes)
    }
}

private struct HintLabelStyle: LabelStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            configuration.icon
                .foregroundStyle(tint)

            configuration.title
        }
    }
}

// a switch with a line under its title saying what it does
private struct DetailToggle: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .foregroundStyle(Theme.header)

                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.vertical, 4)
    }
}

// a title over a slider with a speaker at each end, as discord's volumes are
private struct VolumeSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var lowIcon = "speaker.slash.fill"
    var highIcon = "speaker.wave.3.fill"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .foregroundStyle(Theme.header)

            HStack(spacing: 14) {
                Image(systemName: lowIcon)
                    .foregroundStyle(Theme.muted)

                Slider(value: $value, in: range)
                    .tint(Theme.blurple)

                Image(systemName: highIcon)
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.vertical, 6)
    }
}

// one of a few choices, the picked one filled, as discord lists its noise suppression
private struct RadioRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundStyle(Theme.header)

                Spacer()

                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Theme.accentText : Theme.muted)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}

private struct MicLevelMeter: View {
    let level: Float

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.deepBackground)

                Capsule()
                    .fill(level > 0.85 ? Theme.yellow : Theme.green)
                    .frame(width: proxy.size.width * CGFloat(level))
                    .animation(.linear(duration: 0.08), value: level)
            }
        }
        .frame(height: 10)
    }
}

// a plain capture preview, nothing is sent anywhere
#if os(macOS)
private typealias PreviewRepresentable = NSViewRepresentable
#else
private typealias PreviewRepresentable = UIViewRepresentable
#endif

private struct CameraPreview: PreviewRepresentable {
    let position: AVCaptureDevice.Position
    // a mac's pick from voice settings, which has no front or back
    let deviceId: String?

    #if os(macOS)
    func makeNSView(context: Context) -> PreviewView {
        makeView(context: context)
    }

    func updateNSView(_ view: PreviewView, context: Context) {
        context.coordinator.start(position, deviceId: deviceId)
    }

    static func dismantleNSView(_ view: PreviewView, coordinator: Coordinator) {
        coordinator.stop()
    }
    #else
    func makeUIView(context: Context) -> PreviewView {
        makeView(context: context)
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        context.coordinator.start(position, deviceId: deviceId)
    }

    static func dismantleUIView(_ view: PreviewView, coordinator: Coordinator) {
        coordinator.stop()
    }
    #endif

    private func makeView(context: Context) -> PreviewView {
        let view = PreviewView()

        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = context.coordinator.session
        context.coordinator.start(position, deviceId: deviceId)

        return view
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        let session = AVCaptureSession()
        private var position: AVCaptureDevice.Position?
        private var deviceId: String?
        private let queue = DispatchQueue(label: "com.sharkord.camera-preview")

        func start(_ newPosition: AVCaptureDevice.Position, deviceId newDeviceId: String?) {
            guard newPosition != position || newDeviceId != deviceId else {
                return
            }

            position = newPosition
            deviceId = newDeviceId

            let session = session

            queue.async {
                session.beginConfiguration()
                session.inputs.forEach { session.removeInput($0) }

                // the camera a call would film with, the picked one first on a mac
                if
                    let device = newDeviceId.flatMap(AVCaptureDevice.init(uniqueID:))
                        ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition)
                        ?? AVCaptureDevice.default(for: .video),
                    let input = try? AVCaptureDeviceInput(device: device),
                    session.canAddInput(input)
                {
                    session.addInput(input)
                }

                session.commitConfiguration()

                if !session.isRunning {
                    session.startRunning()
                }
            }
        }

        func stop() {
            let session = session

            queue.async {
                session.stopRunning()
            }
        }
    }

    #if os(macOS)
    final class PreviewView: NSView {
        let previewLayer = AVCaptureVideoPreviewLayer()

        override init(frame: NSRect) {
            super.init(frame: frame)

            wantsLayer = true
            layer = previewLayer
        }

        required init?(coder: NSCoder) {
            nil
        }
    }
    #else
    final class PreviewView: UIView {
        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
    #endif
}

// the system's own output list, the one place an ios app on a mac can switch where sound plays
#if os(macOS)
private struct OutputDevicePicker: NSViewRepresentable {
    func makeNSView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()

        picker.isRoutePickerButtonBordered = false
        picker.setRoutePickerButtonColor(NSColor(Theme.text), for: .normal)
        picker.setRoutePickerButtonColor(NSColor(Theme.blurple), for: .active)

        return picker
    }

    func updateNSView(_ picker: AVRoutePickerView, context: Context) {}
}
#else
private struct OutputDevicePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()

        picker.tintColor = UIColor(Theme.text)
        picker.activeTintColor = UIColor(Theme.blurple)

        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
#endif
