import AVFoundation
import CoreImage
import Foundation
import os
import ReplayKit

// the screen broadcast. it only forwards frames: the app, already in the voice channel, sends
// them on through webrtc, which keeps this process far below the extension memory limit.
// messages go to the app over loopback tcp, each a 4 byte big endian length, a type byte and
// the payload: the secret from ScreenShareEndpoint first, then jpeg frames and, with app audio
// on, the game's sound as 48khz mono float samples. see ScreenShareReceiver
final class SampleHandler: RPBroadcastSampleHandler, @unchecked Sendable {
    private enum MessageType: UInt8 {
        case secret = 0
        case video = 1
        case audio = 2
    }

    private static let jpegQuality: CGFloat = 0.7
    // MixingAudioDevice.gameSampleRate
    private static let gameFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false)!

    private let queue = DispatchQueue(label: "com.sharkord.broadcast")
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var socket: Int32 = -1
    private var lastFrameTime: CFTimeInterval = 0
    private var maxDimension: CGFloat = 1280
    private var framesPerSecond = 30.0
    private var shareAudio = false
    // replaykit's app audio format can change mid broadcast, the converter follows it
    private var audioConverter: AVAudioConverter?
    private var audioSourceDescription: AudioStreamBasicDescription?
    // replaykit calls in on its own thread, the encoding runs on the queue
    private let isSending = OSAllocatedUnfairLock(initialState: false)

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        guard
            let endpoint = ScreenShareEndpoint.load(),
            configure(endpoint),
            connect(port: endpoint.port),
            send(.secret, Data(endpoint.secret.utf8))
        else {
            finishBroadcastWithError(NSError(
                domain: "com.sharkord.broadcast",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Join a voice channel in Sharkord before sharing your screen."]
            ))
            return
        }
    }

    override func broadcastFinished() {
        queue.sync {
            closeSocket()
        }
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        switch sampleBufferType {
        case .video:
            processVideo(sampleBuffer)
        case .audioApp:
            processAudio(sampleBuffer)
        default:
            break
        }
    }

    // converted here, on replaykit's thread, so only plain data crosses to the queue
    private func processAudio(_ sampleBuffer: CMSampleBuffer) {
        guard shareAudio, let samples = convertAudio(sampleBuffer) else {
            return
        }

        queue.async {
            _ = self.send(.audio, samples)
        }
    }

    private func processVideo(_ sampleBuffer: CMSampleBuffer) {
        let now = CACurrentMediaTime()

        // a frame still on its way means the app is behind, this one is dropped rather than queued
        guard now - lastFrameTime >= 1 / framesPerSecond, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let claimed = isSending.withLock { sending in
            guard !sending else {
                return false
            }

            sending = true

            return true
        }

        guard claimed else {
            return
        }

        lastFrameTime = now

        let orientation = Self.orientation(of: sampleBuffer)
        let image = CIImage(cvPixelBuffer: pixelBuffer).oriented(orientation)

        queue.async {
            defer {
                self.isSending.withLock { $0 = false }
            }

            guard let jpeg = self.encode(image) else {
                return
            }

            if !self.send(.video, jpeg) {
                self.closeSocket()
                self.finishBroadcastWithError(NSError(
                    domain: "com.sharkord.broadcast",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Sharkord stopped receiving your screen."]
                ))
            }
        }
    }

    private func configure(_ endpoint: ScreenShareEndpoint) -> Bool {
        maxDimension = CGFloat(endpoint.maxDimension)
        framesPerSecond = Double(max(endpoint.framesPerSecond, 1))
        shareAudio = endpoint.shareAudio

        return true
    }

    private func convertAudio(_ sampleBuffer: CMSampleBuffer) -> Data? {
        guard
            let description = CMSampleBufferGetFormatDescription(sampleBuffer),
            let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(description)
        else {
            return nil
        }

        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        var source = streamDescription.pointee

        guard frames > 0 else {
            return nil
        }

        if audioConverter == nil || !Self.sameFormat(audioSourceDescription, source) {
            guard let format = AVAudioFormat(streamDescription: &source) else {
                return nil
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
            return nil
        }

        input.frameLength = frames

        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frames),
            into: input.mutableAudioBufferList
        ) == noErr else {
            return nil
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
            return nil
        }

        return Data(bytes: channel, count: Int(output.frameLength) * MemoryLayout<Float>.size)
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

    private func encode(_ image: CIImage) -> Data? {
        let extent = image.extent
        let scale = min(1, maxDimension / max(extent.width, extent.height))
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        return context.jpegRepresentation(
            of: scaled,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: Self.jpegQuality]
        )
    }

    private func connect(port: UInt16) -> Bool {
        let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)

        guard descriptor >= 0 else {
            return false
        }

        var noSigPipe: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = port.bigEndian

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard result == 0 else {
            close(descriptor)
            return false
        }

        socket = descriptor

        return true
    }

    private func send(_ type: MessageType, _ payload: Data) -> Bool {
        guard socket >= 0 else {
            return false
        }

        var length = UInt32(payload.count).bigEndian
        var header = Data(bytes: &length, count: 4)

        header.append(type.rawValue)

        return write(header) && write(payload)
    }

    private func write(_ data: Data) -> Bool {
        data.withUnsafeBytes { buffer in
            var offset = 0

            while offset < buffer.count {
                let written = Darwin.write(socket, buffer.baseAddress! + offset, buffer.count - offset)

                if written <= 0 {
                    return false
                }

                offset += written
            }

            return true
        }
    }

    private func closeSocket() {
        if socket >= 0 {
            close(socket)
            socket = -1
        }
    }

    // replaykit hands over portrait sized buffers and says separately which way is up
    private static func orientation(of sampleBuffer: CMSampleBuffer) -> CGImagePropertyOrientation {
        guard
            let value = CMGetAttachment(sampleBuffer, key: RPVideoSampleOrientationKey as CFString, attachmentModeOut: nil) as? NSNumber,
            let orientation = CGImagePropertyOrientation(rawValue: value.uint32Value)
        else {
            return .up
        }

        return orientation
    }
}
