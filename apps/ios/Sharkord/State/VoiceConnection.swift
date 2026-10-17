import AVFoundation
import Foundation
import Mediasoup
import os
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
    // held here, the capturer only keeps a weak reference to its delegate
    private var cameraRotation: CameraRotation?
    private var cameraTrack: RTCVideoTrack?
    private var cameraProducer: Producer?
    private var cameraPosition = AVCaptureDevice.Position.front
    // the camera filming now, which the reactions are played on
    private var cameraDevice: AVCaptureDevice?
    private var screenProducer: Producer?
    private var screenTrack: RTCVideoTrack?
    private var rtpCapabilities = "{}"
    private var sendVideoCodec: String?
    // the web's three camera layers, sent when the server has simulcast on, in vp8: this webrtc
    // build splits only vp8 into layers, h264 went out as one
    private var simulcastCodec: String?
    private var soundMuted = false
    private var outputVolume: Double
    private let audioOptions: AudioOptions
    private let mixingDevice: MixingAudioDevice?
    private var isClosed = false

    init(
        audioOptions: AudioOptions,
        mixingDevice: MixingAudioDevice?,
        signal: @escaping Signal,
        onFailure: @escaping @MainActor @Sendable () -> Void,
        onVideo: @escaping VideoHandler
    ) {
        // the mixing device sets up the audio session itself
        if mixingDevice == nil {
            Self.configureAudioSession(audioOptions)
        }

        self.audioOptions = audioOptions
        self.mixingDevice = mixingDevice
        self.outputVolume = audioOptions.outputVolume
        self.signal = signal
        self.onFailure = onFailure
        self.onVideo = onVideo
        // the factories are passed either way: the plain init knows only h264 baseline, so the
        // phone could not take vp8, vp9 or av1 from a browser
        self.factory = mixingDevice.map { mixer in
            RTCPeerConnectionFactory(
                encoderFactory: RTCDefaultVideoEncoderFactory(),
                decoderFactory: RTCDefaultVideoDecoderFactory(),
                audioDevice: mixer
            )
        } ?? RTCPeerConnectionFactory(
            encoderFactory: RTCDefaultVideoEncoderFactory(),
            decoderFactory: RTCDefaultVideoDecoderFactory()
        )
        self.device = Device(pcFactory: factory)
    }

    func start(routerRtpCapabilities: String, micMuted: Bool, soundMuted: Bool, canSpeak: Bool, simulcast: Bool) async throws {
        try await onQueue {
            try self.device.load(with: routerRtpCapabilities)
            self.rtpCapabilities = try self.device.rtpCapabilities()
            self.sendVideoCodec = Self.baselineH264(in: self.rtpCapabilities)
            self.simulcastCodec = simulcast ? Self.codec(in: self.rtpCapabilities) { $0 == "video/vp8" } : nil
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

    func consumedVideoKeys() async -> [VoiceStreamKey] {
        await onQueueValue { self.consumers.keys.filter(\.kind.isVideo) }
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
            self.cameraRotation = nil
            self.cameraTrack = nil
            self.cameraDevice = nil
        }

        await onVideo(VoiceStreamKey(kind: .video, remoteId: ownUserId), nil)

        let json = Data("{\"kind\":\"video\"}".utf8)

        _ = try? await signal("voice.closeProducer", json)
    }

    // frames come from ScreenCapture, the returned sink takes them on whatever thread they
    // arrive
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

    struct CameraEffects: Sendable {
        // the reactions the camera can play now, empty when its format or the phone has none
        let reactions: [AVCaptureReactionType]
        let supportsCenterStage: Bool
    }

    func cameraEffects() async -> CameraEffects {
        await onQueueValue {
            guard let device = self.cameraDevice else {
                return CameraEffects(reactions: [], supportsCenterStage: false)
            }

            let reactions = device.canPerformReactionEffects ? Array(device.availableReactionTypes) : []

            return CameraEffects(reactions: reactions, supportsCenterStage: device.activeFormat.isCenterStageSupported)
        }
    }

    // drawn into the video by the camera itself, so everyone in the call sees it
    func performReaction(_ reaction: AVCaptureReactionType) {
        queue.async {
            self.cameraDevice?.performEffect(for: reaction)
        }
    }

    func flipCamera() {
        queue.async {
            guard let camera = self.camera else {
                return
            }

            self.cameraPosition = self.cameraPosition == .front ? .back : .front

            if let device = Self.captureDevice(self.cameraPosition) {
                self.cameraRotation?.follow(device)
                Self.startCapture(camera, device: device)
                self.cameraDevice = device
            }
        }
    }

    func setMicMuted(_ muted: Bool) {
        // with game audio in the same track, only the voice may go quiet
        if let mixingDevice {
            mixingDevice.isMicMuted = muted
            return
        }

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
            self.cameraRotation = nil
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

        // game audio rides in this track when mixing, and webrtc's noise suppression and gain
        // control treat music as noise to remove. ios's voice processing still cleans the mic
        let isMixing = mixingDevice != nil
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: [
                "googEchoCancellation": audioOptions.echoCancellation ? "true" : "false",
                "googNoiseSuppression": audioOptions.noiseSuppression && !isMixing ? "true" : "false",
                "googAutoGainControl": audioOptions.autoGainControl && !isMixing ? "true" : "false"
            ]
        )
        let track = factory.audioTrack(with: factory.audioSource(with: constraints), trackId: "microphone")

        if let mixingDevice {
            mixingDevice.isMicMuted = muted
        }

        track.isEnabled = isMixing || !muted

        let producer = try sendTransport.createProducer(
            for: track,
            encodings: nil,
            codecOptions: nil,
            codec: nil,
            appData: nil
        )

        if muted && !isMixing {
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

    // the phone sends h264 baseline: the hardware encodes it and chrome, safari and firefox all
    // decode it. left to itself mediasoup takes the server's first codec, vp9, encoded in software
    private static func baselineH264(in capabilities: String) -> String? {
        codec(in: capabilities) { mimeType, parameters in
            let profile = parameters["profile-level-id"] as? String

            return mimeType == "video/h264" && profile?.hasPrefix("42e0") == true
        }
    }

    private static func codec(in capabilities: String, where matches: (String) -> Bool) -> String? {
        codec(in: capabilities) { mimeType, _ in
            matches(mimeType)
        }
    }

    // the first of the router's codecs that matches, as the json createProducer takes
    private static func codec(in capabilities: String, where matches: (String, [String: Any]) -> Bool) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: Data(capabilities.utf8)) as? [String: Any],
            let codecs = object["codecs"] as? [[String: Any]]
        else {
            return nil
        }

        let codec = codecs.first { codec in
            let mimeType = (codec["mimeType"] as? String)?.lowercased() ?? ""
            let parameters = codec["parameters"] as? [String: Any] ?? [:]

            return matches(mimeType, parameters)
        }

        guard let codec, let data = try? JSONSerialization.data(withJSONObject: codec) else {
            return nil
        }

        return String(decoding: data, as: UTF8.self)
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
            codec: sendVideoCodec,
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
        let rotation = CameraRotation(source: source, device: device)
        let capturer = RTCCameraVideoCapturer(delegate: rotation)
        let track = factory.videoTrack(with: source, trackId: "camera")

        Self.startCapture(capturer, device: device)
        cameraDevice = device

        let isLayered = simulcastCodec != nil
        // the kind travels in appData, onProduce reads it back for voice.produce. the layer names
        // are the web's
        let appData = isLayered
            ? "{\"kind\":\"video\",\"qualityLayers\":[{\"spatialLayer\":0,\"label\":\"Low\"},{\"spatialLayer\":1,\"label\":\"Medium\"},{\"spatialLayer\":2,\"label\":\"High\"}]}"
            : "{\"kind\":\"video\"}"
        let producer: Producer

        do {
            producer = try sendTransport.createProducer(
                for: track,
                encodings: isLayered ? Self.cameraLayers() : nil,
                codecOptions: nil,
                codec: simulcastCodec ?? sendVideoCodec,
                appData: appData
            )
        } catch {
            capturer.stopCapture()
            throw sendSignaler?.produceError ?? error
        }

        camera = capturer
        cameraRotation = rotation
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

    // a quarter, a half and the whole picture, which the server hands out by what each viewer
    // shows and can take. the web's numbers, with more room at the top for 1080p
    private static func cameraLayers() -> [RTCRtpEncodingParameters] {
        let layers: [(scale: Double, bitrate: Int, framerate: Int)] = [
            (4, 150_000, 24),
            (2, 500_000, 30),
            (1, 2_500_000, 30)
        ]

        return layers.map { layer in
            let encoding = RTCRtpEncodingParameters()

            encoding.scaleResolutionDownBy = NSNumber(value: layer.scale)
            encoding.maxBitrateBps = NSNumber(value: layer.bitrate)
            encoding.maxFramerate = NSNumber(value: layer.framerate)

            return encoding
        }
    }

    // 1080p at 30fps where the camera has it, the size a call gets on a mac or a full screen.
    // of those, the one the most of the system's effects work in: reactions, the hand gestures
    // among them, are only drawn in a format that supports them
    private static func startCapture(_ capturer: RTCCameraVideoCapturer, device: AVCaptureDevice) {
        let formats = RTCCameraVideoCapturer.supportedFormats(for: device).filter { format in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let maxRate = format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0

            return dimensions.width == 1920 && dimensions.height == 1080 && maxRate >= 30
        }
        let format = formats.max { Self.effectCount(of: $0) < Self.effectCount(of: $1) }
            ?? RTCCameraVideoCapturer.supportedFormats(for: device).last

        guard let format else {
            return
        }

        let maxRate = format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 30
        let minRate = format.videoSupportedFrameRateRanges.map(\.minFrameRate).min() ?? 30

        capturer.startCapture(with: device, format: format, fps: Int(min(maxRate, 30))) { error in
            guard error == nil else {
                return
            }

            allowDimLight(on: device, slowestRate: max(minRate, 24))
        }
    }

    // webrtc holds the camera at exactly 30 frames a second, which caps each exposure at a 30th
    // of a second and left a dim room dark and smeared. the camera app slows down in the dark
    // instead, so this lets it drop to 24 when it needs the light, and turns on the phone's low
    // light boost where it has one
    private static func allowDimLight(on device: AVCaptureDevice, slowestRate: Double) {
        do {
            try device.lockForConfiguration()
        } catch {
            return
        }

        device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(slowestRate))

        if device.isLowLightBoostSupported {
            device.automaticallyEnablesLowLightBoostWhenAvailable = true
        }

        device.unlockForConfiguration()
    }

    private static func effectCount(of format: AVCaptureDevice.Format) -> Int {
        [format.reactionEffectsSupported, format.isPortraitEffectSupported, format.isStudioLightSupported]
            .filter { $0 }
            .count
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

    // how loud everyone is right now, 0 to 1, from webrtc's own measure of what each stream
    // carried: the people heard, and the microphone, nil when it sends nothing
    func audioLevels() async -> (own: Double?, remote: [Int: Double]) {
        await onQueueValue {
            var remote: [Int: Double] = [:]

            for (key, consumer) in self.consumers where key.kind == .audio {
                if let level = Self.audioLevel(in: consumer.stats, type: "inbound-rtp") {
                    remote[key.remoteId] = level
                }
            }

            let own = self.producer.flatMap { Self.audioLevel(in: $0.stats, type: "media-source") }


            return (own, remote)
        }
    }

    private static func audioLevel(in stats: String, type: String) -> Double? {
        let entry = entries(in: stats).first { $0["type"] as? String == type && $0["audioLevel"] != nil }

        return entry?["audioLevel"] as? Double
    }

    struct NetworkStats: Sendable {
        // to the server and back, in seconds
        let roundTrip: Double?
        // everything received so far, which the caller compares with the last reading
        let packetsLost: Int
        let packetsReceived: Int
    }

    // the round trip from the pair of addresses the send transport settled on, the losses from
    // everything the receive transport carries
    func networkStats() async -> NetworkStats {
        await onQueueValue {
            let sendEntries = self.sendTransport.map { Self.entries(in: $0.stats) } ?? []
            let receiveEntries = self.receiveTransport.map { Self.entries(in: $0.stats) } ?? []
            let pair = (sendEntries + receiveEntries).first { entry in
                entry["type"] as? String == "candidate-pair" && entry["nominated"] as? Bool == true && entry["currentRoundTripTime"] != nil
            }
            let inbound = receiveEntries.filter { $0["type"] as? String == "inbound-rtp" }

            return NetworkStats(
                roundTrip: pair?["currentRoundTripTime"] as? Double,
                packetsLost: inbound.reduce(0) { $0 + (($1["packetsLost"] as? Int) ?? 0) },
                packetsReceived: inbound.reduce(0) { $0 + (($1["packetsReceived"] as? Int) ?? 0) }
            )
        }
    }

    // a stats report as webrtc serialises it, a list of entries or a map of them by id
    private static func entries(in stats: String) -> [[String: Any]] {
        guard let json = try? JSONSerialization.jsonObject(with: Data(stats.utf8)) else {
            return []
        }

        if let list = json as? [[String: Any]] {
            return list
        }

        if let map = json as? [String: Any] {
            return map.values.compactMap { $0 as? [String: Any] }
        }

        return []
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
    // the server's own words when it turns a stream down, which mediasoup only reports as a
    // numbered error
    private(set) var produceError: Error?

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
        // a camera in layers names each one, the server turns it down otherwise
        let layers = ProducerAppData.qualityLayers(appData).map { ",\"qualityLayers\":\($0)" } ?? ""
        let json = Data("{\"transportId\":\"\(transport.id)\",\"kind\":\"\(kind)\",\"rtpParameters\":\(rtpParameters)\(layers)}".utf8)

        produceError = nil

        Task {
            do {
                let data = try await signal("voice.produce", json)
                let producerId = try JSONDecoder().decode(String.self, from: data)

                reply.value(producerId)
            } catch {
                self.produceError = error
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

// hands screen frames to the screen track's source. webrtc's sources take frames from any
// thread, so this needs no queue of its own
nonisolated final class ScreenFrameSink: @unchecked Sendable {
    private let source: RTCVideoSource
    private let capturer: RTCVideoCapturer

    init(source: RTCVideoSource, capturer: RTCVideoCapturer) {
        self.source = source
        self.capturer = capturer
    }

    func push(_ pixelBuffer: CVPixelBuffer, rotation: RTCVideoRotation) {
        let buffer = RTCCVPixelBuffer(pixelBuffer: pixelBuffer)
        let frame = RTCVideoFrame(
            buffer: buffer,
            rotation: rotation,
            timeStampNs: Int64(CACurrentMediaTime() * 1_000_000_000)
        )

        source.capturer(capturer, didCapture: frame)
    }
}

// between the camera and its track, turning each frame by apple's rotation coordinator. webrtc's
// capturer works the turn out from the device orientation for an iphone's camera, which put the
// picture on its side on an ipad held upright, whose camera sits on another edge
nonisolated private final class CameraRotation: NSObject, RTCVideoCapturerDelegate, @unchecked Sendable {
    private let source: RTCVideoSource
    private let rotation = OSAllocatedUnfairLock(initialState: RTCVideoRotation._0)
    private var coordinator: AVCaptureDevice.RotationCoordinator?
    private var observation: NSKeyValueObservation?

    init(source: RTCVideoSource, device: AVCaptureDevice) {
        self.source = source
        super.init()
        follow(device)
    }

    // a flip to the other camera, which can sit another way round
    func follow(_ device: AVCaptureDevice) {
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)

        self.coordinator = coordinator
        observation = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.initial, .new]) { [weak self] coordinator, _ in
            let rotation = Self.turn(degrees: coordinator.videoRotationAngleForHorizonLevelCapture)

            self?.rotation.withLock { $0 = rotation }
        }
    }

    func capturer(_ capturer: RTCVideoCapturer, didCapture frame: RTCVideoFrame) {
        let rotation = rotation.withLock { $0 }
        let turned = RTCVideoFrame(buffer: frame.buffer, rotation: rotation, timeStampNs: frame.timeStampNs)

        source.capturer(capturer, didCapture: turned)
    }

    private static func turn(degrees: CGFloat) -> RTCVideoRotation {
        switch Int(degrees.rounded()) {
        case 90:
            return ._90
        case 180:
            return ._180
        case 270:
            return ._270
        default:
            return ._0
        }
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

    // the layers' names as json, nil for a stream sent as one
    static func qualityLayers(_ appData: String) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: Data(appData.utf8)) as? [String: Any],
            let layers = object["qualityLayers"],
            let data = try? JSONSerialization.data(withJSONObject: layers)
        else {
            return nil
        }

        return String(decoding: data, as: UTF8.self)
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

// the call's ping and packet loss, graded the way discord colours its signal bars
nonisolated struct ConnectionQuality: Equatable, Sendable {
    enum Grade {
        case good
        case fair
        case poor
    }

    // milliseconds, nil until the connection has measured one
    let ping: Int?
    // the share of packets lost lately, 0 to 1
    let loss: Double

    var grade: Grade {
        let ping = ping ?? 0

        if ping < 150 && loss < 0.02 {
            return .good
        }

        if ping < 300 && loss < 0.08 {
            return .fair
        }

        return .poor
    }
}
