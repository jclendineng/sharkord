import CoreImage
import CoreVideo
import Foundation
import os
import Security

// the app's end of the broadcast extension's connection (SharkordBroadcast/SampleHandler.swift).
// it listens on a loopback port while the app is in a voice channel, a broadcast connecting is
// what starts a screen share, and it ends when the broadcast closes the connection. the first
// frame has to be the secret from ScreenShareEndpoint, anything else is turned away
nonisolated final class ScreenShareReceiver: @unchecked Sendable {
    // a frame far larger than any jpeg the extension makes means the stream is out of step
    private static let maxFrameBytes = 8 * 1024 * 1024

    typealias FrameHandler = @Sendable (CVPixelBuffer) -> Void
    typealias AudioHandler = @Sendable (UnsafeBufferPointer<Float>) -> Void

    // the first byte after each message's length, SampleHandler.MessageType mirrors it
    private enum MessageType: UInt8 {
        case secret = 0
        case video = 1
        case audio = 2
    }

    private let options: OSAllocatedUnfairLock<(maxDimension: Int, framesPerSecond: Int, shareAudio: Bool)>
    private let onConnect: @Sendable () -> Void
    private let onDisconnect: @Sendable () -> Void
    private let queue = DispatchQueue(label: "com.sharkord.screen-share")
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let state = OSAllocatedUnfairLock(initialState: State())

    private struct State {
        var listener: Int32 = -1
        var client: Int32 = -1
        var onFrame: FrameHandler?
        var onAudio: AudioHandler?
        var isStopped = false
    }

    init(
        maxDimension: Int,
        framesPerSecond: Int,
        shareAudio: Bool,
        onConnect: @escaping @Sendable () -> Void,
        onDisconnect: @escaping @Sendable () -> Void
    ) {
        self.options = OSAllocatedUnfairLock(initialState: (maxDimension, framesPerSecond, shareAudio))
        self.onConnect = onConnect
        self.onDisconnect = onDisconnect
    }

    // set once the screen producer exists, frames before then are dropped
    func setFrameHandler(_ handler: FrameHandler?) {
        state.withLock { $0.onFrame = handler }
    }

    func start() {
        let listener = socket(AF_INET, SOCK_STREAM, 0)

        guard listener >= 0 else {
            return
        }

        // port 0 lets the system pick a free one, the extension reads it from the keychain
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0

        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listener, $0, length) == 0 && getsockname(listener, $0, &length) == 0
            }
        }

        guard bound, listen(listener, 1) == 0 else {
            close(listener)
            return
        }

        let secret = Self.makeSecret()

        let (maxDimension, framesPerSecond, shareAudio) = options.withLock { $0 }

        ScreenShareEndpoint(
            port: UInt16(bigEndian: address.sin_port),
            secret: secret,
            maxDimension: maxDimension,
            framesPerSecond: framesPerSecond,
            shareAudio: shareAudio
        ).save()
        state.withLock { $0.listener = listener }

        queue.async {
            self.acceptLoop(listener, secret: secret)
        }
    }

    // game audio, only set while a share with app audio is running
    func setAudioHandler(_ handler: AudioHandler?) {
        state.withLock { $0.onAudio = handler }
    }

    // read by the extension when the next broadcast starts
    func setQuality(maxDimension: Int, framesPerSecond: Int) {
        options.withLock { options in
            options.maxDimension = maxDimension
            options.framesPerSecond = framesPerSecond
        }

        guard var endpoint = ScreenShareEndpoint.load() else {
            return
        }

        endpoint.maxDimension = maxDimension
        endpoint.framesPerSecond = framesPerSecond
        endpoint.save()
    }

    // closing the client tells the extension to end the broadcast
    func dropClient() {
        let client = state.withLock { state in
            let client = state.client

            state.client = -1

            return client
        }

        if client >= 0 {
            shutdown(client, SHUT_RDWR)
            close(client)
        }
    }

    func stop() {
        let (listener, client) = state.withLock { state in
            let sockets = (state.listener, state.client)

            state.isStopped = true
            state.listener = -1
            state.client = -1
            state.onFrame = nil
            state.onAudio = nil

            return sockets
        }

        for descriptor in [client, listener] where descriptor >= 0 {
            shutdown(descriptor, SHUT_RDWR)
            close(descriptor)
        }

        ScreenShareEndpoint.delete()
    }

    private func acceptLoop(_ listener: Int32, secret: String) {
        while !state.withLock({ $0.isStopped }) {
            let client = accept(listener, nil, nil)

            guard client >= 0 else {
                return
            }

            var noSigPipe: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

            // something that connects and says nothing cannot hold up the next connection
            Self.setReceiveTimeout(client, seconds: 2)

            guard isAuthorized(client, secret: secret) else {
                close(client)
                continue
            }

            Self.setReceiveTimeout(client, seconds: 0)

            state.withLock { $0.client = client }
            onConnect()
            readFrames(client)
            dropClient()
            onDisconnect()
        }
    }

    private func isAuthorized(_ client: Int32, secret: String) -> Bool {
        guard let (type, payload) = readMessage(client), type == .secret else {
            return false
        }

        return payload == Data(secret.utf8)
    }

    private func readFrames(_ client: Int32) {
        while let (type, payload) = readMessage(client) {
            switch type {
            case .video:
                let handler = state.withLock { $0.onFrame }

                if let handler, let pixelBuffer = decode(payload) {
                    handler(pixelBuffer)
                }
            case .audio:
                let handler = state.withLock { $0.onAudio }

                payload.withUnsafeBytes { bytes in
                    handler?(bytes.bindMemory(to: Float.self))
                }
            case .secret:
                continue
            }
        }
    }

    // a 4 byte big endian length, a type byte, then that many bytes
    private func readMessage(_ client: Int32) -> (MessageType, Data)? {
        guard let header = read(client, count: 5) else {
            return nil
        }

        let length = header.prefix(4).withUnsafeBytes { Int(UInt32(bigEndian: $0.loadUnaligned(as: UInt32.self))) }

        guard
            let type = MessageType(rawValue: header[header.startIndex + 4]),
            length > 0,
            length <= Self.maxFrameBytes,
            let payload = read(client, count: length)
        else {
            return nil
        }

        return (type, payload)
    }

    private func read(_ client: Int32, count: Int) -> Data? {
        var data = Data(count: count)
        var offset = 0

        let complete = data.withUnsafeMutableBytes { buffer in
            while offset < count {
                let received = recv(client, buffer.baseAddress! + offset, count - offset, 0)

                if received <= 0 {
                    return false
                }

                offset += received
            }

            return true
        }

        return complete ? data : nil
    }

    private func decode(_ jpeg: Data) -> CVPixelBuffer? {
        guard let image = CIImage(data: jpeg) else {
            return nil
        }

        let width = Int(image.extent.width)
        let height = Int(image.extent.height)
        var pixelBuffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [:]]

        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &pixelBuffer)

        guard let pixelBuffer else {
            return nil
        }

        context.render(image, to: pixelBuffer)

        return pixelBuffer
    }

    private static func setReceiveTimeout(_ client: Int32, seconds: Int) {
        var timeout = timeval(tv_sec: seconds, tv_usec: 0)

        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    }

    private static func makeSecret() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)

        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)

        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
