import CoreImage
import Foundation
import os
import ReplayKit

// the screen broadcast. it only forwards frames: the app, already in the voice channel, sends
// them on through webrtc, which keeps this process far below the extension memory limit.
// frames go to the app over loopback tcp, each a 4 byte big endian length followed by a jpeg.
// the first one is the secret from ScreenShareEndpoint instead, see ScreenShareReceiver
final class SampleHandler: RPBroadcastSampleHandler, @unchecked Sendable {
    private static let jpegQuality: CGFloat = 0.7

    private let queue = DispatchQueue(label: "com.sharkord.broadcast")
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var socket: Int32 = -1
    private var lastFrameTime: CFTimeInterval = 0
    private var maxDimension: CGFloat = 1280
    private var framesPerSecond = 30.0
    // replaykit calls in on its own thread, the encoding runs on the queue
    private let isSending = OSAllocatedUnfairLock(initialState: false)

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        guard
            let endpoint = ScreenShareEndpoint.load(),
            configure(endpoint),
            connect(port: endpoint.port),
            send(Data(endpoint.secret.utf8))
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
        guard sampleBufferType == .video else {
            return
        }

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

            if !self.send(jpeg) {
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

        return true
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

    private func send(_ payload: Data) -> Bool {
        guard socket >= 0 else {
            return false
        }

        var length = UInt32(payload.count).bigEndian
        let header = Data(bytes: &length, count: 4)

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
