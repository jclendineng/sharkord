import AVFoundation
import os
import WebRTC
#if canImport(ScreenCaptureKit)
import ScreenCaptureKit

// the screen share. the system picker asks what to share, then the app captures it itself and
// hands each frame straight to webrtc, with the game's sound for the mixer when app audio is on
nonisolated final class ScreenCapture: NSObject, @unchecked Sendable {
    typealias AudioHandler = @Sendable (UnsafeBufferPointer<Float>) -> Void

    // MixingAudioDevice.gameSampleRate
    private static let gameFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false)!

    private let onPicked: @Sendable () -> Void
    private let onStopped: @Sendable () -> Void
    private let queue = DispatchQueue(label: "com.sharkord.screen-capture")
    // SCStream is not marked sendable, but every touch of it is under this lock
    private let state = OSAllocatedUnfairLock(uncheckedState: State())
    // the game's audio format can change mid share, the converter follows it. only touched on
    // the queue the stream hands samples to
    private var audioConverter: AVAudioConverter?
    private var audioSourceDescription: AudioStreamBasicDescription?

    private struct State {
        // what the picker last chose, kept here rather than handed across to the main actor
        var filter: SCContentFilter?
        var stream: SCStream?
        var sink: ScreenFrameSink?
        var onAudio: AudioHandler?
        var framesPerSecond = 30.0
        var lastFrameTime: CFTimeInterval = 0
    }

    init(onPicked: @escaping @Sendable () -> Void, onStopped: @escaping @Sendable () -> Void) {
        self.onPicked = onPicked
        self.onStopped = onStopped
        super.init()
    }

    // the whole screen, as the broadcast picker shared it, with the system's own mic button
    // left off: the voice channel already carries the mic
    @MainActor
    func presentPicker() {
        let picker = SCContentSharingPicker.shared
        var configuration = SCContentSharingPickerConfiguration()

        configuration.showsMicrophoneControl = false
        configuration.showsCameraControl = false
        picker.defaultConfiguration = configuration
        picker.add(self)
        picker.isActive = true
        picker.present(using: .display)
    }

    func start(
        sink: ScreenFrameSink,
        maxDimension: Int,
        framesPerSecond: Int,
        onAudio: AudioHandler?
    ) async throws {
        guard let filter = state.withLockUnchecked({ $0.filter }) else {
            return
        }

        let configuration = SCStreamConfiguration()
        let pixelSize = CGSize(
            width: filter.contentRect.width * CGFloat(filter.pointPixelScale),
            height: filter.contentRect.height * CGFloat(filter.pointPixelScale)
        )
        let scale = min(1, CGFloat(maxDimension) / max(pixelSize.width, pixelSize.height, 1))

        configuration.width = Int(pixelSize.width * scale)
        configuration.height = Int(pixelSize.height * scale)
        configuration.capturesAudio = onAudio != nil
        configuration.sampleRate = Int(Self.gameFormat.sampleRate)
        configuration.channelCount = 1
        configuration.excludesCurrentProcessAudio = true

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)

        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)

        if onAudio != nil {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        }

        state.withLockUnchecked { state in
            state.stream = stream
            state.sink = sink
            state.onAudio = onAudio
            state.framesPerSecond = Double(max(framesPerSecond, 1))
            state.lastFrameTime = 0
        }

        try await stream.startCapture()
    }

    func stop() async {
        let stream = state.withLockUnchecked { state in
            let stream = state.stream

            state.stream = nil
            state.sink = nil
            state.onAudio = nil

            return stream
        }

        try? await stream?.stopCapture()

        await MainActor.run {
            SCContentSharingPicker.shared.remove(self)
            SCContentSharingPicker.shared.isActive = false
        }
    }

    private func processVideo(_ sampleBuffer: CMSampleBuffer) {
        guard
            Self.isComplete(sampleBuffer),
            let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else {
            return
        }

        let now = CACurrentMediaTime()
        // the stream has no frame rate of its own on ios, so frames past the setting are dropped
        let sink = state.withLockUnchecked { state -> ScreenFrameSink? in
            guard now - state.lastFrameTime >= 1 / state.framesPerSecond else {
                return nil
            }

            state.lastFrameTime = now

            return state.sink
        }

        sink?.push(pixelBuffer, rotation: Self.rotation(of: sampleBuffer))
    }

    private func processAudio(_ sampleBuffer: CMSampleBuffer) {
        guard let handler = state.withLockUnchecked({ $0.onAudio }) else {
            return
        }

        convertAudio(sampleBuffer) { samples in
            handler(samples)
        }
    }

    private func convertAudio(_ sampleBuffer: CMSampleBuffer, into handler: (UnsafeBufferPointer<Float>) -> Void) {
        guard
            let description = CMSampleBufferGetFormatDescription(sampleBuffer),
            let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(description)
        else {
            return
        }

        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        var source = streamDescription.pointee

        guard frames > 0 else {
            return
        }

        if audioConverter == nil || !Self.sameFormat(audioSourceDescription, source) {
            guard let format = AVAudioFormat(streamDescription: &source) else {
                return
            }

            audioConverter = AVAudioConverter(from: format, to: Self.gameFormat)
            audioSourceDescription = source
        }

        guard
            let converter = audioConverter,
            let input = AVAudioPCMBuffer(pcmFormat: converter.inputFormat, frameCapacity: frames),
            let output = AVAudioPCMBuffer(
                pcmFormat: Self.gameFormat,
                frameCapacity: AVAudioFrameCount(Double(frames) * Self.gameFormat.sampleRate / source.mSampleRate) + 32
            )
        else {
            return
        }

        input.frameLength = frames

        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frames),
            into: input.mutableAudioBufferList
        ) == noErr else {
            return
        }

        var consumed = false

        converter.convert(to: output, error: nil) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }

            consumed = true
            status.pointee = .haveData

            return input
        }

        guard let channel = output.floatChannelData?[0], output.frameLength > 0 else {
            return
        }

        handler(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    }

    // a frame only says something changed once it is complete, the others carry no image
    private static func isComplete(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard
            let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
            let rawStatus = attachments.first?[.status] as? Int,
            let status = SCFrameStatus(rawValue: rawStatus)
        else {
            return false
        }

        return status == .complete
    }

    // the frame arrives as the screen lies and says separately which way is up, webrtc turns it
    // on the far side rather than every frame being rotated here
    private static func rotation(of sampleBuffer: CMSampleBuffer) -> RTCVideoRotation {
        guard
            let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
            let rawOrientation = attachments.first?[.videoOrientation] as? UInt32,
            let orientation = CGImagePropertyOrientation(rawValue: rawOrientation)
        else {
            return ._0
        }

        switch orientation {
        case .right, .rightMirrored:
            return ._90
        case .down, .downMirrored:
            return ._180
        case .left, .leftMirrored:
            return ._270
        default:
            return ._0
        }
    }

    private static func sameFormat(_ previous: AudioStreamBasicDescription?, _ current: AudioStreamBasicDescription) -> Bool {
        guard let previous else {
            return false
        }

        return previous.mSampleRate == current.mSampleRate
            && previous.mChannelsPerFrame == current.mChannelsPerFrame
            && previous.mFormatFlags == current.mFormatFlags
            && previous.mBitsPerChannel == current.mBitsPerChannel
    }
}

nonisolated extension ScreenCapture: SCContentSharingPickerObserver {
    func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        state.withLockUnchecked { $0.filter = filter }
        onPicked()
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {}

    func contentSharingPickerStartDidFailWithError(_ error: any Error) {}
}

nonisolated extension ScreenCapture: SCStreamDelegate, SCStreamOutput {
    // stopped from the system, the control centre's stop button or the screen locking
    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        onStopped()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        switch type {
        case .screen:
            processVideo(sampleBuffer)
        case .audio:
            processAudio(sampleBuffer)
        default:
            break
        }
    }
}
#else
// the simulator has no screencapturekit. a stand in so the app still builds there, where a share
// never starts
nonisolated final class ScreenCapture: NSObject, @unchecked Sendable {
    typealias AudioHandler = @Sendable (UnsafeBufferPointer<Float>) -> Void

    init(onPicked: @escaping @Sendable () -> Void, onStopped: @escaping @Sendable () -> Void) {
        super.init()
    }

    @MainActor
    func presentPicker() {}

    func start(sink: ScreenFrameSink, maxDimension: Int, framesPerSecond: Int, onAudio: AudioHandler?) async throws {}

    func stop() async {}
}
#endif
