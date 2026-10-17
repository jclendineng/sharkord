import AVFoundation
import Observation

// the settings screen's mic check: a level meter, and optionally hearing yourself back.
// it takes the audio session for itself, so it is only offered outside a call
@Observable
final class MicrophoneTester {
    private(set) var level: Float = 0
    private(set) var isRunning = false
    private(set) var errorMessage: String?

    // a new engine each run, so a connection from hearing yourself last time does not linger
    @ObservationIgnored private var engine = AVAudioEngine()
    @ObservationIgnored private var configurationTask: Task<Void, Never>?

    func start(playback: Bool) async {
        guard !isRunning else {
            return
        }

        guard await AVAudioApplication.requestRecordPermission() else {
            errorMessage = "Allow microphone access in Settings to test your mic."
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()

            // voice chat's echo cancellation takes your own voice out of the speaker as if it were
            // echo, so hearing yourself needs the plain mode
            try session.setCategory(.playAndRecord, mode: playback ? .default : .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
            AudioInputPreference.apply()

            engine = AVAudioEngine()

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)

            // sendable so it is not tied to the main actor like the rest of the app: the engine
            // calls it on its audio thread, and a main actor closure there traps
            try input.installAudioTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable [weak self] buffer, _ in
                let level = Self.rms(buffer)

                Task { @MainActor in
                    self?.level = level
                }
            }

            if playback {
                try engine.connectNode(input, to: engine.mainMixerNode, format: format)
            }

            try engine.start()
            isRunning = true
            errorMessage = nil
            restartOnConfigurationChange(playback: playback)
        } catch {
            errorMessage = error.localizedDescription
            stop()
        }
    }

    func stop() {
        configurationTask?.cancel()
        configurationTask = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isRunning = false
        level = 0
    }

    // airpods switch the mic to a different sample rate once the session is active, and the
    // engine stops itself on that rather than carry on, so the test starts over on the new route
    private func restartOnConfigurationChange(playback: Bool) {
        let notifications = NotificationCenter.default.notifications(named: .AVAudioEngineConfigurationChange, object: engine)

        configurationTask = Task { [weak self] in
            for await _ in notifications {
                guard let self, !Task.isCancelled else {
                    return
                }

                stop()
                await start(playback: playback)
                return
            }
        }
    }

    // a rough loudness from 0 to 1, a meter needs nothing more exact
    nonisolated private static func rms(_ buffer: AVReadOnlyAudioPCMBuffer) -> Float {
        guard buffer.frameLength > 0, case .float(let samples) = buffer.channelData(0) else {
            return 0
        }

        var sum: Float = 0

        for index in 0..<buffer.frameLength {
            let sample = samples[index * buffer.stride]

            sum += sample * sample
        }

        let rms = (sum / Float(buffer.frameLength)).squareRoot()
        let decibels = 20 * log10(max(rms, 0.000_001))

        return min(max((decibels + 60) / 60, 0), 1)
    }
}
