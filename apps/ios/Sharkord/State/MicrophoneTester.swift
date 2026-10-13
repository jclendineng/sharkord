import AVFoundation
import Observation

// the settings screen's mic check: a level meter, and optionally hearing yourself back.
// it takes the audio session for itself, so it is only offered outside a call
@Observable
final class MicrophoneTester {
    private(set) var level: Float = 0
    private(set) var isRunning = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let engine = AVAudioEngine()

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

            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)

            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                let level = Self.rms(buffer)

                Task { @MainActor in
                    self?.level = level
                }
            }

            if playback {
                engine.connect(input, to: engine.mainMixerNode, format: format)
            }

            try engine.start()
            isRunning = true
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            stop()
        }
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        engine.reset()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isRunning = false
        level = 0
    }

    // a rough loudness from 0 to 1, a meter needs nothing more exact
    nonisolated private static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else {
            return 0
        }

        var sum: Float = 0

        for index in 0..<Int(buffer.frameLength) {
            sum += samples[index] * samples[index]
        }

        let rms = (sum / Float(buffer.frameLength)).squareRoot()
        let decibels = 20 * log10(max(rms, 0.000_001))

        return min(max((decibels + 60) / 60, 0), 1)
    }
}
