import AVFoundation
import Foundation
import Mediasoup
import WebRTC

// the webrtc side of a voice channel: one send transport carrying the microphone and camera,
// one receive transport carrying everyone else's audio, webcams and screen shares
// (apps/server/src/routers/voice).
// mediasoup blocks the calling thread until the server answers, createProducer waits for
// onProduce to be called back with the producer id, so everything touching it runs on one
// serial queue and signaling hops to the main actor where the tRPC client lives
nonisolated final class VoiceConnection: @unchecked Sendable {
    typealias Signal = @MainActor @Sendable (_ path: String, _ json: Data?) async throws -> Data
    // a remote webcam or screen share arriving, or going away with nil
    typealias VideoHandler = @MainActor @Sendable (_ key: VoiceStreamKey, _ track: VideoTrackBox?) -> Void

    // from the voice and video settings, read once when the call starts
    struct AudioOptions: Sendable {
        let echoCancellation: Bool
        let noiseSuppression: Bool
        let autoGainControl: Bool
        let speakerByDefault: Bool
        let outputVolume: Double
    }

    struct VoiceError: LocalizedError {
        let message: String

        var errorDescription: String? { message }
    }

    private let queue = DispatchQueue(label: "com.sharkord.voice")
    private let signal: Signal
    private let onFailure: @MainActor @Sendable () -> Void
    private let onVideo: VideoHandler
    private let factory: RTCPeerConnectionFactory
    private let device: Device

    private var sendSignaler: TransportSignaler?
    private var receiveSignaler: TransportSignaler?
    private var sendTransport: SendTransport?
    private var receiveTransport: ReceiveTransport?
    private var producer: Producer?
    private var microphone: RTCAudioTrack?
    private var consumers: [VoiceStreamKey: Consumer] = [:]
    private var camera: RTCCameraVideoCapturer?
    private var cameraTrack: RTCVideoTrack?
    private var cameraProducer: Producer?
    private var cameraPosition = AVCaptureDevice.Position.front
    private var screenProducer: Producer?
    private var screenTrack: RTCVideoTrack?
    private var rtpCapabilities = "{}"
    private var soundMuted = false
    private var outputVolume: Double
    private let audioOptions: AudioOptions
    private var isClosed = false

    init(
        audioOptions: AudioOptions,
        signal: @escaping Signal,
        onFailure: @escaping @MainActor @Sendable () -> Void,
        onVideo: @escaping VideoHandler
    ) {
        Self.configureAudioSession(audioOptions)

        self.audioOptions = audioOptions
        self.outputVolume = audioOptions.outputVolume
        self.signal = signal
        self.onFailure = onFailure
        self.onVideo = onVideo
        self.factory = RTCPeerConnectionFactory()
        self.device = Device(pcFactory: factory)
    }

    func start(routerRtpCapabilities: String, micMuted: Bool, soundMuted: Bool, canSpeak: Bool) async throws {
        try await onQueue {
            try self.device.load(with: routerRtpCapabilities)
            self.rtpCapabilities = try self.device.rtpCapabilities()
            self.soundMuted = soundMuted
        }

        let sendParams = try await signal("voice.createProducerTransport", nil)

        try await onQueue {
            try self.createSendTransport(sendParams)
        }

        let receiveParams = try await signal("voice.createConsumerTransport", nil)

        try await onQueue {
            try self.createReceiveTransport(receiveParams)
        }

        if canSpeak {
            try await onQueue {
                try self.produceMicrophone(muted: micMuted)
            }
        }
    }

    func consume(_ key: VoiceStreamKey) async {
        let input = await onQueueValue { self.rtpCapabilities }

        do {
            let json = try JSONSerialization.data(withJSONObject: [
                "kind": key.kind.rawValue,
                "remoteId": key.remoteId,
                "rtpCapabilities": try JSONSerialization.jsonObject(with: Data(input.utf8))
            ])
            let data = try await signal("voice.consume", json)
            let consumed = try ConsumeResponse(data)

            try await onQueue {
                try self.addConsumer(key, consumed)
            }
        } catch {
            print("[voice] could not consume \(key): \(error)")
        }
    }

    func closeConsumer(_ key: VoiceStreamKey) {
        queue.async {
            self.consumers.removeValue(forKey: key)?.close()
        }

        if key.kind.isVideo {
            let onVideo = onVideo

            Task { @MainActor in
                onVideo(key, nil)
            }
        }
    }

    // the local preview comes back through the handler under the caller's own id
    func startCamera(ownUserId: Int) async throws {
        try await onQueue {
            try self.produceCamera(ownUserId: ownUserId)
        }
    }

    func stopCamera(ownUserId: Int) async {
        await onQueueValue {
            self.cameraProducer?.close()
            self.cameraProducer = nil
            self.camera?.stopCapture()
            self.camera = nil
            self.cameraTrack = nil
        }

        await onVideo(VoiceStreamKey(kind: .video, remoteId: ownUserId), nil)

        let json = Data("{\"kind\":\"video\"}".utf8)

        _ = try? await signal("voice.closeProducer", json)
    }

    // frames come from the broadcast extension through ScreenShareReceiver, the returned sink
    // takes them on whatever thread they arrive
    func startScreenShare() async throws -> ScreenFrameSink {
        try await onQueueResult {
            try self.produceScreen()
        }
    }

    func stopScreenShare() async {
        await onQueueValue {
            self.screenProducer?.close()
            self.screenProducer = nil
            self.screenTrack = nil
        }

        let json = Data("{\"kind\":\"screen\"}".utf8)

        _ = try? await signal("voice.closeProducer", json)
    }

    func flipCamera() {
        queue.async {
            guard let camera = self.camera else {
                return
            }

            self.cameraPosition = self.cameraPosition == .front ? .back : .front

            if let device = Self.captureDevice(self.cameraPosition) {
                Self.startCapture(camera, device: device)
            }
        }
    }

    func setMicMuted(_ muted: Bool) {
        queue.async {
            self.microphone?.isEnabled = !muted

            if muted {
                self.producer?.pause()
            } else {
                self.producer?.resume()
            }
        }
    }

    func setOutputVolume(_ volume: Double) {
        queue.async {
            self.outputVolume = volume

            for (key, consumer) in self.consumers where !key.kind.isVideo {
                (consumer.track as? RTCAudioTrack)?.source.volume = volume
            }
        }
    }

    func setSoundMuted(_ muted: Bool) {
        queue.async {
            self.soundMuted = muted

            for (key, consumer) in self.consumers where !key.kind.isVideo {
                consumer.track.isEnabled = !muted
            }
        }
    }

    func close() {
        queue.async {
            guard !self.isClosed else {
                return
            }

            self.isClosed = true
            self.consumers.values.forEach { $0.close() }
            self.consumers = [:]
            self.producer?.close()
            self.cameraProducer?.close()
            self.camera?.stopCapture()
            self.camera = nil
            self.cameraTrack = nil
            self.cameraProducer = nil
            self.screenProducer?.close()
            self.screenProducer = nil
            self.screenTrack = nil
            self.sendTransport?.close()
            self.receiveTransport?.close()
            self.producer = nil
            self.sendTransport = nil
            self.receiveTransport = nil
        }
    }

    private func createSendTransport(_ data: Data) throws {
        let params = try TransportParams(data)
        let signaler = TransportSignaler(connectPath: "voice.connectProducerTransport", signal: signal, onFailure: onFailure)
        let transport = try device.createSendTransport(
            id: params.id,
            iceParameters: params.iceParameters,
            iceCandidates: params.iceCandidates,
            dtlsParameters: params.dtlsParameters,
            sctpParameters: nil,
            appData: nil
        )

        transport.delegate = signaler
        sendSignaler = signaler
        sendTransport = transport
    }

    private func createReceiveTransport(_ data: Data) throws {
        let params = try TransportParams(data)
        let signaler = TransportSignaler(connectPath: "voice.connectConsumerTransport", signal: signal, onFailure: onFailure)
        let transport = try device.createReceiveTransport(
            id: params.id,
            iceParameters: params.iceParameters,
            iceCandidates: params.iceCandidates,
            dtlsParameters: params.dtlsParameters
        )

        transport.delegate = signaler
        receiveSignaler = signaler
        receiveTransport = transport
    }

    private func produceMicrophone(muted: Bool) throws {
        guard let sendTransport else {
            return
        }

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: [
                "googEchoCancellation": audioOptions.echoCancellation ? "true" : "false",
                "googNoiseSuppression": audioOptions.noiseSuppression ? "true" : "false",
                "googAutoGainControl": audioOptions.autoGainControl ? "true" : "false"
            ]
        )
        let track = factory.audioTrack(with: factory.audioSource(with: constraints), trackId: "microphone")

        track.isEnabled = !muted

        let producer = try sendTransport.createProducer(
            for: track,
            encodings: nil,
            codecOptions: nil,
            codec: nil,
            appData: nil
        )

        if muted {
            producer.pause()
        }

        microphone = track
        self.producer = producer
    }

    private func addConsumer(_ key: VoiceStreamKey, _ consumed: ConsumeResponse) throws {
        guard let receiveTransport, !isClosed else {
            return
        }

        let consumer = try receiveTransport.consume(
            consumerId: consumed.consumerId,
            producerId: consumed.producerId,
            kind: key.kind.isVideo ? .video : .audio,
            rtpParameters: consumed.rtpParameters,
            appData: nil
        )

        consumers.removeValue(forKey: key)?.close()
        consumers[key] = consumer

        guard key.kind.isVideo else {
            consumer.track.isEnabled = !soundMuted
            (consumer.track as? RTCAudioTrack)?.source.volume = outputVolume
            return
        }

        if let track = consumer.track as? RTCVideoTrack {
            let onVideo = onVideo
            let box = VideoTrackBox(track: track)

            Task { @MainActor in
                onVideo(key, box)
            }
        }
    }

    private func produceScreen() throws -> ScreenFrameSink {
        guard let sendTransport else {
            throw VoiceError(message: "Join a voice channel before sharing your screen.")
        }

        screenProducer?.close()

        let source = factory.videoSource(forScreenCast: true)
        let capturer = RTCVideoCapturer(delegate: source)
        let track = factory.videoTrack(with: source, trackId: "screen")

        let producer = try sendTransport.createProducer(
            for: track,
            encodings: nil,
            codecOptions: nil,
            codec: nil,
            appData: "{\"kind\":\"screen\"}"
        )

        screenTrack = track
        screenProducer = producer

        return ScreenFrameSink(source: source, capturer: capturer)
    }

    private func produceCamera(ownUserId: Int) throws {
        guard let sendTransport, cameraProducer == nil else {
            return
        }

        guard let device = Self.captureDevice(cameraPosition) else {
            throw VoiceError(message: "No camera is available.")
        }

        let source = factory.videoSource()
        let capturer = RTCCameraVideoCapturer(delegate: source)
        let track = factory.videoTrack(with: source, trackId: "camera")

        Self.startCapture(capturer, device: device)

        // the kind travels in appData, onProduce reads it back for voice.produce
        let producer = try sendTransport.createProducer(
            for: track,
            encodings: nil,
            codecOptions: nil,
            codec: nil,
            appData: "{\"kind\":\"video\"}"
        )

        camera = capturer
        cameraTrack = track
        cameraProducer = producer

        let onVideo = onVideo
        let box = VideoTrackBox(track: track)

        Task { @MainActor in
            onVideo(VoiceStreamKey(kind: .video, remoteId: ownUserId), box)
        }
    }

    private static func captureDevice(_ position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        RTCCameraVideoCapturer.captureDevices().first { $0.position == position }
            ?? RTCCameraVideoCapturer.captureDevices().first
    }

    // 720p at 30fps where the camera has it, which is plenty for a phone sized tile
    private static func startCapture(_ capturer: RTCCameraVideoCapturer, device: AVCaptureDevice) {
        let formats = RTCCameraVideoCapturer.supportedFormats(for: device)
        let format = formats.first { format in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)

            return dimensions.width == 1280 && dimensions.height == 720
        } ?? formats.last

        guard let format else {
            return
        }

        let maxRate = format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 30

        capturer.startCapture(with: device, format: format, fps: Int(min(maxRate, 30)))
    }

    private func onQueue(_ work: @escaping @Sendable () throws -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    try work()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func onQueueResult<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try work())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func onQueueValue<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: work())
            }
        }
    }

    // speaker by default like other voice chat apps, voiceChat mode adds the system's own echo
    // cancellation on top of webrtc's
    private static func configureAudioSession(_ options: AudioOptions) {
        let configuration = RTCAudioSessionConfiguration.webRTC()

        configuration.category = AVAudioSession.Category.playAndRecord.rawValue
        configuration.mode = options.echoCancellation
            ? AVAudioSession.Mode.voiceChat.rawValue
            : AVAudioSession.Mode.default.rawValue
        configuration.categoryOptions = options.speakerByDefault
            ? [.allowBluetoothHFP, .defaultToSpeaker]
            : [.allowBluetoothHFP]

        RTCAudioSessionConfiguration.setWebRTC(configuration)
    }
}

// answers the transports' signaling callbacks, which arrive on webrtc's own threads
nonisolated private final class TransportSignaler: SendTransportDelegate, ReceiveTransportDelegate, @unchecked Sendable {
    private let connectPath: String
    private let signal: VoiceConnection.Signal
    private let onFailure: @MainActor @Sendable () -> Void

    init(connectPath: String, signal: @escaping VoiceConnection.Signal, onFailure: @escaping @MainActor @Sendable () -> Void) {
        self.connectPath = connectPath
        self.signal = signal
        self.onFailure = onFailure
    }

    func onConnect(transport: Transport, dtlsParameters: String) {
        let path = connectPath
        let signal = signal
        let json = Data("{\"dtlsParameters\":\(dtlsParameters)}".utf8)

        Task {
            do {
                _ = try await signal(path, json)
            } catch {
                print("[voice] \(path) failed: \(error)")
            }
        }
    }

    func onConnectionStateChange(transport: Transport, connectionState: TransportConnectionState) {
        guard connectionState == .failed else {
            return
        }

        let onFailure = onFailure

        Task { @MainActor in
            onFailure()
        }
    }

    func onProduce(
        transport: Transport,
        kind: MediaKind,
        rtpParameters: String,
        appData: String,
        callback: @escaping (String?) -> Void
    ) {
        let signal = signal
        let reply = UncheckedBox(callback)
        let kind = ProducerAppData.kind(appData)
        let json = Data("{\"transportId\":\"\(transport.id)\",\"kind\":\"\(kind)\",\"rtpParameters\":\(rtpParameters)}".utf8)

        Task {
            do {
                let data = try await signal("voice.produce", json)
                let producerId = try JSONDecoder().decode(String.self, from: data)

                reply.value(producerId)
            } catch {
                // nil fails createProducer, which is waiting on this, instead of hanging it
                reply.value(nil)
            }
        }
    }

    func onProduceData(
        transport: Transport,
        sctpParameters: String,
        label: String,
        protocol dataProtocol: String,
        appData: String,
        callback: @escaping (String?) -> Void
    ) {
        callback(nil)
    }
}

// a stream from the voice channel, the server keys them by kind and the sender's user id
nonisolated struct VoiceStreamKey: Hashable, Sendable, CustomStringConvertible {
    enum Kind: String, Sendable {
        case audio
        case video
        case screen
        case screenAudio = "screen_audio"

        var isVideo: Bool {
            self == .video || self == .screen
        }
    }

    let kind: Kind
    let remoteId: Int

    var description: String {
        "\(kind.rawValue)/\(remoteId)"
    }
}

// hands broadcast frames to the screen track's source. webrtc's sources take frames from any
// thread, so this needs no queue of its own
nonisolated final class ScreenFrameSink: @unchecked Sendable {
    private let source: RTCVideoSource
    private let capturer: RTCVideoCapturer

    init(source: RTCVideoSource, capturer: RTCVideoCapturer) {
        self.source = source
        self.capturer = capturer
    }

    func push(_ pixelBuffer: CVPixelBuffer) {
        let buffer = RTCCVPixelBuffer(pixelBuffer: pixelBuffer)
        let frame = RTCVideoFrame(
            buffer: buffer,
            rotation: ._0,
            timeStampNs: Int64(CACurrentMediaTime() * 1_000_000_000)
        )

        source.capturer(capturer, didCapture: frame)
    }
}

// webrtc tracks are not sendable, they only ever get attached to a renderer on the main actor
nonisolated struct VideoTrackBox: @unchecked Sendable {
    let track: RTCVideoTrack
}

nonisolated private enum ProducerAppData {
    static func kind(_ appData: String) -> String {
        guard
            let object = try? JSONSerialization.jsonObject(with: Data(appData.utf8)) as? [String: Any],
            let kind = object["kind"] as? String
        else {
            return "audio"
        }

        return kind
    }
}

nonisolated private struct UncheckedBox<T>: @unchecked Sendable {
    let value: T

    init(_ value: T) {
        self.value = value
    }
}

// mediasoup takes every parameter as a json string, so the server's objects are re-serialized
nonisolated private struct TransportParams {
    let id: String
    let iceParameters: String
    let iceCandidates: String
    let dtlsParameters: String

    init(_ data: Data) throws {
        guard
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let id = object["id"] as? String
        else {
            throw VoiceConnection.VoiceError(message: "The server sent an unexpected voice transport.")
        }

        self.id = id
        self.iceParameters = try jsonString(object["iceParameters"])
        self.iceCandidates = try jsonString(object["iceCandidates"])
        self.dtlsParameters = try jsonString(object["dtlsParameters"])
    }
}

nonisolated private struct ConsumeResponse {
    let producerId: String
    let consumerId: String
    let rtpParameters: String

    init(_ data: Data) throws {
        guard
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let producerId = object["producerId"] as? String,
            let consumerId = object["consumerId"] as? String
        else {
            throw VoiceConnection.VoiceError(message: "The server sent an unexpected voice consumer.")
        }

        self.producerId = producerId
        self.consumerId = consumerId
        self.rtpParameters = try jsonString(object["consumerRtpParameters"])
    }
}

nonisolated private func jsonString(_ value: Any?) throws -> String {
    guard let value else {
        throw VoiceConnection.VoiceError(message: "The server left out part of the voice setup.")
    }

    let data = try JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed)

    return String(decoding: data, as: UTF8.self)
}
