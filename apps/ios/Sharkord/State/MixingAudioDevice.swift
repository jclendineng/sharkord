import AVFoundation
import os
import WebRTC

// webrtc's own ios audio device only ever records the microphone. this one stands in for it
// when a screen share should carry the game's sound: it records the mic and plays the call
// through AVAudioEngine like the built in one does, and mixes in the game audio ScreenCapture
// hands over. it also plays the mic back for hearing yourself. only used when "share app audio"
// or "hear yourself in calls" is on, every other call keeps webrtc's device
nonisolated final class MixingAudioDevice: NSObject, RTCAudioDevice, @unchecked Sendable {
    // what ScreenCapture hands over
    static let gameSampleRate = 48_000.0
    // enough for the largest buffer core audio hands a callback
    private static let maxFrames = 8192
    // game audio further behind than this is dropped rather than played late
    private static let maxGameLatency = 0.2
    // your own voice is played back no later than this, any more and it sounds like an echo
    private static let maxMonitorLatency = 0.08

    private let engine = AVAudioEngine()
    private let options: VoiceConnection.AudioOptions
    private var delegate: RTCAudioDeviceDelegate?
    private var sourceNode: AVAudioSourceNode?
    private var sinkNode: AVAudioSinkNode?
    private var inputRate = 48_000.0
    private var outputRate = 48_000.0
    private var gameConverter: AVAudioConverter?
    private let gameAudio = GameAudioRing(capacity: 48_000)
    // the mic on its way to the speaker, written on the input thread and read on the output one
    private let monitorAudio = GameAudioRing(capacity: 48_000)
    private let monitorScratch = UnsafeMutablePointer<Float>.allocate(capacity: MixingAudioDevice.maxFrames)
    // the mic brought to the speaker's rate, which on a headset can be several times the mic's
    private let resampleScratch = UnsafeMutablePointer<Float>.allocate(capacity: MixingAudioDevice.maxFrames * 4)
    private let recordScratch = UnsafeMutablePointer<Int16>.allocate(capacity: MixingAudioDevice.maxFrames)
    private let playoutScratch = UnsafeMutablePointer<Int16>.allocate(capacity: MixingAudioDevice.maxFrames)
    private let gameScratch = UnsafeMutablePointer<Float>.allocate(capacity: MixingAudioDevice.maxFrames)
    private let flags = OSAllocatedUnfairLock(initialState: Flags())

    private struct Flags {
        var isInitialized = false
        var isPlayoutInitialized = false
        var isRecordingInitialized = false
        var isPlaying = false
        var isRecording = false
        var isMicMuted = false
        var isMonitoring = false
    }

    init(options: VoiceConnection.AudioOptions) {
        self.options = options
    }

    deinit {
        recordScratch.deallocate()
        playoutScratch.deallocate()
        gameScratch.deallocate()
        monitorScratch.deallocate()
        resampleScratch.deallocate()
    }

    // with game audio in the same track, muting has to silence only the voice
    var isMicMuted: Bool {
        get { flags.withLock { $0.isMicMuted } }
        set { flags.withLock { $0.isMicMuted = newValue } }
    }

    var isMonitoring: Bool {
        get { flags.withLock { $0.isMonitoring } }
        set {
            flags.withLock { $0.isMonitoring = newValue }

            if !newValue {
                monitorAudio.clear()
            }
        }
    }

    // MARK: game audio from the screen share

    // mono float samples at gameSampleRate, from the screen capture's thread
    func writeGameAudio(_ samples: UnsafeBufferPointer<Float>) {
        guard !samples.isEmpty else {
            return
        }

        if inputRate == Self.gameSampleRate {
            gameAudio.write(samples, keepAtMost: Int(inputRate * Self.maxGameLatency))
            return
        }

        guard
            let converter = gameConverter,
            let source = AVAudioPCMBuffer(pcmFormat: converter.inputFormat, frameCapacity: AVAudioFrameCount(samples.count)),
            let output = AVAudioPCMBuffer(
                pcmFormat: converter.outputFormat,
                frameCapacity: AVAudioFrameCount(Double(samples.count) * inputRate / Self.gameSampleRate) + 32
            )
        else {
            return
        }

        source.frameLength = AVAudioFrameCount(samples.count)
        source.floatChannelData?[0].update(from: samples.baseAddress!, count: samples.count)

        var consumed = false

        converter.convert(to: output, error: nil) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }

            consumed = true
            status.pointee = .haveData

            return source
        }

        if let channel = output.floatChannelData?[0] {
            gameAudio.write(
                UnsafeBufferPointer(start: channel, count: Int(output.frameLength)),
                keepAtMost: Int(inputRate * Self.maxGameLatency)
            )
        }
    }

    func clearGameAudio() {
        gameAudio.clear()
    }

    // MARK: RTCAudioDevice

    var deviceInputSampleRate: Double { inputRate }
    var inputIOBufferDuration: TimeInterval { AVAudioSession.sharedInstance().ioBufferDuration }
    var inputNumberOfChannels: Int { 1 }
    var inputLatency: TimeInterval { AVAudioSession.sharedInstance().inputLatency }
    var deviceOutputSampleRate: Double { outputRate }
    var outputIOBufferDuration: TimeInterval { AVAudioSession.sharedInstance().ioBufferDuration }
    var outputNumberOfChannels: Int { 1 }
    var outputLatency: TimeInterval { AVAudioSession.sharedInstance().outputLatency }
    var isInitialized: Bool { flags.withLock { $0.isInitialized } }
    var isPlayoutInitialized: Bool { flags.withLock { $0.isPlayoutInitialized } }
    var isPlaying: Bool { flags.withLock { $0.isPlaying } }
    var isRecordingInitialized: Bool { flags.withLock { $0.isRecordingInitialized } }
    var isRecording: Bool { flags.withLock { $0.isRecording } }

    func initialize(with delegate: RTCAudioDeviceDelegate) -> Bool {
        self.delegate = delegate

        do {
            let session = AVAudioSession.sharedInstance()

            try session.setCategory(
                .playAndRecord,
                mode: options.echoCancellation ? .voiceChat : .default,
                options: options.speakerByDefault ? [.allowBluetoothHFP, .defaultToSpeaker] : [.allowBluetoothHFP]
            )
            try session.setPreferredSampleRate(Self.gameSampleRate)
            try session.setPreferredIOBufferDuration(0.01)
            try session.setActive(true)
            Self.preferHeadset(session)
            try setUpEngine()
        } catch {
            print("[voice] mixing audio device could not start: \(error)")
            return false
        }

        flags.withLock { $0.isInitialized = true }

        delegate.notifyAudioInputParametersChange()
        delegate.notifyAudioOutputParametersChange()

        return true
    }

    func terminateDevice() -> Bool {
        engine.stop()
        flags.withLock { $0 = Flags() }
        gameAudio.clear()

        return true
    }

    func initializePlayout() -> Bool {
        flags.withLock { $0.isPlayoutInitialized = true }

        return true
    }

    func startPlayout() -> Bool {
        flags.withLock { $0.isPlaying = true }

        return startEngine()
    }

    func stopPlayout() -> Bool {
        let stillRecording = flags.withLock { flags in
            flags.isPlaying = false

            return flags.isRecording
        }

        if !stillRecording {
            engine.stop()
        }

        return true
    }

    func initializeRecording() -> Bool {
        flags.withLock { $0.isRecordingInitialized = true }

        return true
    }

    func startRecording() -> Bool {
        flags.withLock { $0.isRecording = true }

        return startEngine()
    }

    func stopRecording() -> Bool {
        let stillPlaying = flags.withLock { flags in
            flags.isRecording = false

            return flags.isPlaying
        }

        if !stillPlaying {
            engine.stop()
        }

        return true
    }

    // airpods or any other headset, when one is there. the session comes up before a bluetooth
    // headset's call link does, and default to speaker then keeps the call on the speaker with
    // the headset in. asking for its mic moves the sound there with it. a pick in the output
    // picker afterwards still wins
    private static func preferHeadset(_ session: AVAudioSession) {
        let headsets: Set<AVAudioSession.Port> = [.bluetoothHFP, .headsetMic, .usbAudio]

        guard let headset = session.availableInputs?.first(where: { headsets.contains($0.portType) }) else {
            return
        }

        try? session.setPreferredInput(headset)
    }

    // MARK: engine

    private func setUpEngine() throws {
        let input = engine.inputNode

        // the system's echo cancellation, which the built in device gets from its voice
        // processing unit. it has to be on before the formats are read
        if options.echoCancellation {
            try input.setVoiceProcessingEnabled(true)
        }

        let inputFormat = input.outputFormat(forBus: 0)
        let outputFormat = engine.outputNode.inputFormat(forBus: 0)

        inputRate = inputFormat.sampleRate
        outputRate = outputFormat.sampleRate > 0 ? outputFormat.sampleRate : inputRate

        if
            inputRate != Self.gameSampleRate,
            let from = AVAudioFormat(standardFormatWithSampleRate: Self.gameSampleRate, channels: 1),
            let to = AVAudioFormat(standardFormatWithSampleRate: inputRate, channels: 1)
        {
            gameConverter = AVAudioConverter(from: from, to: to)
        }

        let sink = AVAudioSinkNode { [unowned self] timestamp, frameCount, bufferList in
            self.deliverRecorded(timestamp: timestamp, frameCount: frameCount, bufferList: bufferList)
        }

        engine.attach(sink)
        try engine.connectNode(input, to: sink, format: inputFormat)

        guard let playoutFormat = AVAudioFormat(standardFormatWithSampleRate: outputRate, channels: 1) else {
            throw VoiceConnection.VoiceError(message: "Could not set up call audio.")
        }

        let source = AVAudioSourceNode(format: playoutFormat) { [unowned self] _, timestamp, frameCount, bufferList in
            self.renderPlayout(timestamp: timestamp, frameCount: frameCount, bufferList: bufferList)
        }

        engine.attach(source)
        try engine.connectNode(source, to: engine.mainMixerNode, format: playoutFormat)

        sinkNode = sink
        sourceNode = source
        engine.prepare()
    }

    private func startEngine() -> Bool {
        guard !engine.isRunning else {
            return true
        }

        do {
            try engine.start()
            return true
        } catch {
            print("[voice] mixing audio engine failed to start: \(error)")
            return false
        }
    }

    // the realtime input thread: mic, muted or not, plus whatever game audio is waiting
    private func deliverRecorded(
        timestamp: UnsafePointer<AudioTimeStamp>,
        frameCount: AVAudioFrameCount,
        bufferList: UnsafePointer<AudioBufferList>
    ) -> OSStatus {
        let state = flags.withLock { $0 }
        let frames = min(Int(frameCount), Self.maxFrames)

        guard state.isRecording, let delegate, frames > 0 else {
            return noErr
        }

        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferList))
        let mic = buffers.first?.mData?.assumingMemoryBound(to: Float.self)
        let gameFrames = gameAudio.read(into: gameScratch, count: frames)

        if state.isMonitoring, !state.isMicMuted, let mic {
            let count = resample(mic, frames: frames)

            monitorAudio.write(
                UnsafeBufferPointer(start: resampleScratch, count: count),
                keepAtMost: Int(outputRate * Self.maxMonitorLatency)
            )
        }

        for index in 0..<frames {
            let voice = state.isMicMuted || mic == nil ? 0 : mic![index]
            let game = index < gameFrames ? gameScratch[index] : 0
            let mixed = max(-1, min(1, voice + game))

            recordScratch[index] = Int16(mixed * Float(Int16.max))
        }

        var recorded = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(
                mNumberChannels: 1,
                mDataByteSize: UInt32(frames * MemoryLayout<Int16>.size),
                mData: recordScratch
            )
        )
        var actionFlags = AudioUnitRenderActionFlags()

        return delegate.deliverRecordedData(&actionFlags, timestamp, 1, UInt32(frames), &recorded, nil, nil)
    }

    // the mic at the speaker's rate, by straight lines between samples: a headset can record at
    // a lower rate than it plays, and played as it came the voice would be pitched. nothing is
    // allocated, this runs on the realtime input thread
    private func resample(_ mic: UnsafeMutablePointer<Float>, frames: Int) -> Int {
        let ratio = outputRate / inputRate
        let count = min(Int(Double(frames) * ratio), Self.maxFrames * 4)

        for index in 0..<count {
            let position = Double(index) / ratio
            let lower = min(Int(position), frames - 1)
            let upper = min(lower + 1, frames - 1)
            let fraction = Float(position - Double(lower))

            resampleScratch[index] = mic[lower] + (mic[upper] - mic[lower]) * fraction
        }

        return count
    }

    // the realtime output thread: webrtc mixes everyone in the call into 16 bit samples
    private func renderPlayout(
        timestamp: UnsafePointer<AudioTimeStamp>,
        frameCount: AVAudioFrameCount,
        bufferList: UnsafeMutablePointer<AudioBufferList>
    ) -> OSStatus {
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        let frames = min(Int(frameCount), Self.maxFrames)

        guard let output = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else {
            return noErr
        }

        let state = flags.withLock { $0 }
        let monitoredFrames = state.isMonitoring ? monitorAudio.read(into: monitorScratch, count: frames) : 0
        var callStatus: OSStatus = -1

        // webrtc only starts playing once someone else's audio arrives, so alone in a channel
        // there is no call to mix your own voice into, and it plays by itself
        if state.isPlaying, let delegate {
            var playout = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(
                    mNumberChannels: 1,
                    mDataByteSize: UInt32(frames * MemoryLayout<Int16>.size),
                    mData: playoutScratch
                )
            )
            var actionFlags = AudioUnitRenderActionFlags()

            callStatus = delegate.getPlayoutData(&actionFlags, timestamp, 0, UInt32(frames), &playout)
        }

        for index in 0..<frames {
            let call = callStatus == noErr ? Float(playoutScratch[index]) / Float(Int16.max) : 0
            let own = index < monitoredFrames ? monitorScratch[index] : 0

            output[index] = max(-1, min(1, call + own))
        }

        if Int(frameCount) > frames {
            (output + frames).update(repeating: 0, count: Int(frameCount) - frames)
        }

        return noErr
    }
}

// single producer, single consumer: the receiver writes, the realtime input thread reads
nonisolated final class GameAudioRing: @unchecked Sendable {
    private let storage: UnsafeMutablePointer<Float>
    private let capacity: Int
    private let state = OSAllocatedUnfairLock(initialState: (start: 0, count: 0))

    init(capacity: Int) {
        self.capacity = capacity
        self.storage = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
    }

    deinit {
        storage.deallocate()
    }

    // anything beyond keepAtMost is the oldest audio, and is dropped to stay close to live
    func write(_ samples: UnsafeBufferPointer<Float>, keepAtMost: Int) {
        let limit = min(keepAtMost, capacity)

        // the samples are only read inside the lock, the unchecked form lets the pointer in
        state.withLockUnchecked { state in
            for sample in samples.suffix(limit) {
                let end = (state.start + state.count) % capacity

                storage[end] = sample

                if state.count < limit {
                    state.count += 1
                } else {
                    state.start = (state.start + 1) % capacity
                }
            }
        }
    }

    func read(into destination: UnsafeMutablePointer<Float>, count: Int) -> Int {
        state.withLockUnchecked { state in
            let available = min(count, state.count)

            for index in 0..<available {
                destination[index] = storage[(state.start + index) % capacity]
            }

            state.start = (state.start + available) % capacity
            state.count -= available

            return available
        }
    }

    func clear() {
        state.withLock { $0 = (0, 0) }
    }
}
