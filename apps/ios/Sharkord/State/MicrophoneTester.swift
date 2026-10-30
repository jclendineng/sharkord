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
    // hearing yourself at the output volume a call plays at. a mixer stops at 1 and the setting
    // goes to 2, so it is a gain in decibels instead
    @ObservationIgnored private var outputGain = AVAudioUnitEQ(numberOfBands: 0)

    func start(playback: Bool) async {
        guard !isRunning else {
            return
        }

        guard await AVAudioApplication.requestRecordPermission() else {
            errorMessage = String(localized: "Allow microphone access in Settings to test your mic.")
            return
        }

        do {
            let settings = AppSettings.shared

            // processed as a call is, so the test is a way to hear each setting: echo cancellation
            // is ios's voice processing, which also brings its noise suppression and the mic modes
            #if os(iOS)
            let session = AVAudioSession.sharedInstance()

            try session.setCategory(.playAndRecord, mode: settings.echoCancellation ? .voiceChat : .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
            AudioInputPreference.apply()
            #endif

            engine = AVAudioEngine()

            let input = engine.inputNode

            // before the format is read, which voice processing changes. a mac call keeps
            // webrtc's echo canceller instead, see MixingAudioDevice, and takes the picked mic
            #if os(iOS)
            if settings.echoCancellation {
                try input.setVoiceProcessingEnabled(true)
                input.isVoiceProcessingAGCEnabled = settings.autoGainControl
            }
            #else
            AudioInputPreference.apply(to: engine, inputDeviceId: settings.inputDeviceId)
            #endif

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
                outputGain = AVAudioUnitEQ(numberOfBands: 0)
                engine.attach(outputGain)
                setOutputVolume(AppSettings.shared.outputVolume)
                try engine.connectNode(input, to: outputGain, format: format)
                try engine.connectNode(outputGain, to: engine.mainMixerNode, format: format)
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

    func setOutputVolume(_ volume: Double) {
        let decibels = 20 * log10(max(volume, 0.000_01))

        outputGain.globalGain = Float(min(max(decibels, -96), 24))
    }

    func stop() {
        configurationTask?.cancel()
        configurationTask = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
        isRunning = false
        level = 0
    }

    // airpods switch the mic to a different sample rate once the session is active, and voice
    // processing settles its formats once the engine runs, and either stops the engine. starting
    // it again is enough for both: building the test over turned voice processing on again, which
    // stopped it again, round and round. it is built over only when it will not start
    private func restartOnConfigurationChange(playback: Bool) {
        let notifications = NotificationCenter.default.notifications(named: .AVAudioEngineConfigurationChange, object: engine)

        configurationTask = Task { [weak self] in
            for await _ in notifications {
                guard let self, !Task.isCancelled else {
                    return
                }

                if (try? engine.start()) != nil {
                    continue
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
