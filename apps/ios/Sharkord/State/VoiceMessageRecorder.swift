import AVFoundation
import Observation

// records a voice message to an m4a in tmp, which the composer then uploads like any file
@Observable
final class VoiceMessageRecorder {
    // discord's limit for a voice message
    static let maxDuration: TimeInterval = 20 * 60

    private(set) var isRecording = false
    private(set) var elapsed: TimeInterval = 0
    // recent loudness from 0 to 1, newest last, for the waveform
    private(set) var levels: [Float] = []

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var meterTask: Task<Void, Never>?

    func start() async throws {
        guard await AVAudioApplication.requestRecordPermission() else {
            throw VoiceConnection.VoiceError(message: "Allow microphone access in Settings to record a voice message.")
        }

        #if os(iOS)
        let session = AVAudioSession.sharedInstance()

        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)
        AudioInputPreference.apply()
        #endif

        let url = FileManager.default.temporaryDirectory.appending(path: "voice-message-\(UUID().uuidString).m4a")
        let recorder = try AVAudioRecorder(url: url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ])

        recorder.isMeteringEnabled = true

        guard recorder.record(forDuration: Self.maxDuration) else {
            throw VoiceConnection.VoiceError(message: "Could not start recording.")
        }

        self.recorder = recorder
        elapsed = 0
        levels = []
        isRecording = true

        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                self?.sample()
            }
        }
    }

    // the finished file, or nil when nothing worth sending was recorded
    func finish() -> URL? {
        guard let recorder else {
            return nil
        }

        let duration = recorder.currentTime

        stop()

        return duration >= 0.5 ? recorder.url : nil
    }

    func cancel() {
        guard let recorder else {
            return
        }

        stop()
        recorder.deleteRecording()
    }

    private func stop() {
        meterTask?.cancel()
        meterTask = nil
        recorder?.stop()
        recorder = nil
        isRecording = false
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    private func sample() {
        guard let recorder, recorder.isRecording else {
            return
        }

        recorder.updateMeters()
        elapsed = recorder.currentTime

        let level = max(0, min(1, (recorder.averagePower(forChannel: 0) + 50) / 50))

        levels = Array((levels + [level]).suffix(40))
    }
}
