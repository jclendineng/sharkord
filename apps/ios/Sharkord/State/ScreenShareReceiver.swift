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

    private let quality: OSAllocatedUnfairLock<(maxDimension: Int, framesPerSecond: Int)>
    private let onConnect: @Sendable () -> Void
    private let onDisconnect: @Sendable () -> Void
    private let queue = DispatchQueue(label: "com.sharkord.screen-share")
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let state = OSAllocatedUnfairLock(initialState: State())

    private struct State {
        var listener: Int32 = -1
        var client: Int32 = -1
        var onFrame: FrameHandler?
        var isStopped = false
    }

    init(
        maxDimension: Int,
        framesPerSecond: Int,
        onConnect: @escaping @Sendable () -> Void,
        onDisconnect: @escaping @Sendable () -> Void
    ) {
        self.quality = OSAllocatedUnfairLock(initialState: (maxDimension, framesPerSecond))
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

        let (maxDimension, framesPerSecond) = quality.withLock { $0 }

        ScreenShareEndpoint(
            port: UInt16(bigEndian: address.sin_port),
            secret: secret,
            maxDimension: maxDimension,
            framesPerSecond: framesPerSecond
        ).save()
        state.withLock { $0.listener = listener }

        queue.async {
            self.acceptLoop(listener, secret: secret)
        }
    }

    // read by the extension when the next broadcast starts
    func setQuality(maxDimension: Int, framesPerSecond: Int) {
        quality.withLock { $0 = (maxDimension, framesPerSecond) }

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
        guard
            let header = read(client, count: 4),
            header.withUnsafeBytes({ Int(UInt32(bigEndian: $0.loadUnaligned(as: UInt32.self))) }) == secret.utf8.count,
            let received = read(client, count: secret.utf8.count)
        else {
            return false
        }

        return received == Data(secret.utf8)
    }

    private func readFrames(_ client: Int32) {
        while let header = read(client, count: 4) {
            let length = header.withUnsafeBytes { Int(UInt32(bigEndian: $0.loadUnaligned(as: UInt32.self))) }

            guard length > 0, length <= Self.maxFrameBytes, let jpeg = read(client, count: length) else {
                return
            }

            let handler = state.withLock { $0.onFrame }

            if let handler, let pixelBuffer = decode(jpeg) {
                handler(pixelBuffer)
            }
        }
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
