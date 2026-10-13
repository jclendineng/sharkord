import AVFoundation
import SwiftUI

struct VoiceVideoSettingsScreen: View {
    @Environment(ServerListStore.self) private var servers

    @State private var settings = AppSettings.shared
    @State private var tester = MicrophoneTester()
    @State private var hearYourself = false
    @State private var isCameraPreviewOn = false
    @State private var cameraPosition = AVCaptureDevice.Position.front

    private var isInCall: Bool {
        servers.voiceSession != nil
    }

    var body: some View {
        @Bindable var settings = settings

        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    MicLevelMeter(level: tester.level)

                    Toggle("Hear yourself", isOn: $hearYourself)
                        .disabled(tester.isRunning)

                    Button(tester.isRunning ? "Stop Testing" : "Let's Check", action: toggleMicTest)
                        .buttonStyle(.borderedProminent)
                        .disabled(isInCall)
                }
                .padding(.vertical, 4)

                if let errorMessage = tester.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(Theme.red)
                }
            } header: {
                Text("Mic Test")
            } footer: {
                Text(isInCall
                    ? "Leave the voice channel to test your mic."
                    : "Talk and watch the meter move. Use headphones to hear yourself without feedback.")
            }

            Section {
                Toggle("Echo Cancellation", isOn: $settings.echoCancellation)
                Toggle("Noise Suppression", isOn: $settings.noiseSuppression)
                Toggle("Automatic Gain Control", isOn: $settings.autoGainControl)
            } header: {
                Text("Input Processing")
            } footer: {
                Text("Applies the next time you join a voice channel.")
            }

            Section("Output") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Volume")
                        .foregroundStyle(Theme.header)

                    HStack(spacing: 12) {
                        Image(systemName: "speaker.slash.fill")
                            .foregroundStyle(Theme.muted)

                        Slider(value: $settings.outputVolume, in: 0...2)

                        Image(systemName: "speaker.wave.3.fill")
                            .foregroundStyle(Theme.muted)
                    }
                }
                .padding(.vertical, 4)

                Toggle("Use Speaker by Default", isOn: $settings.speakerByDefault)
            }

            Section {
                if isCameraPreviewOn {
                    CameraPreview(position: cameraPosition)
                        .aspectRatio(3 / 4, contentMode: .fit)
                        .clipShape(.rect(cornerRadius: 12))
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))

                    Button("Flip Camera", systemImage: "arrow.triangle.2.circlepath.camera", action: flipCamera)
                }

                Button(isCameraPreviewOn ? "Stop Video Preview" : "Test Video", action: toggleCameraPreview)
                    .disabled(isInCall)
            } header: {
                Text("Video")
            } footer: {
                if isInCall {
                    Text("Leave the voice channel to preview your camera.")
                }
            }
        }
        .settingsListStyle()
        .navigationTitle("Voice & Video")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: settings.outputVolume) { _, volume in
            servers.voiceSession?.setOutputVolume(volume)
        }
        .onDisappear {
            tester.stop()
        }
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

    private func flipCamera() {
        cameraPosition = cameraPosition == .front ? .back : .front
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
private struct CameraPreview: UIViewRepresentable {
    let position: AVCaptureDevice.Position

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()

        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = context.coordinator.session
        context.coordinator.start(position)

        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        context.coordinator.start(position)
    }

    static func dismantleUIView(_ view: PreviewView, coordinator: Coordinator) {
        coordinator.stop()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        let session = AVCaptureSession()
        private var position: AVCaptureDevice.Position?
        private let queue = DispatchQueue(label: "com.sharkord.camera-preview")

        func start(_ newPosition: AVCaptureDevice.Position) {
            guard newPosition != position else {
                return
            }

            position = newPosition

            let session = session

            queue.async {
                session.beginConfiguration()
                session.inputs.forEach { session.removeInput($0) }

                if
                    let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition),
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

    final class PreviewView: UIView {
        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
