import AVFoundation
import Foundation
import Mediasoup
import WebRTC

// the webrtc side of a voice channel: one send transport carrying the microphone and one
// receive transport carrying everyone else (apps/server/src/routers/voice).
// mediasoup blocks the calling thread until the server answers, createProducer waits for
// onProduce to be called back with the producer id, so everything touching it runs on one
// serial queue and signaling hops to the main actor where the tRPC client lives
nonisolated final class VoiceConnection: @unchecked Sendable {
    typealias Signal = @MainActor @Sendable (_ path: String, _ json: Data?) async throws -> Data

    struct VoiceError: LocalizedError {
        let message: String

        var errorDescription: String? { message }
    }

    private let queue = DispatchQueue(label: "com.sharkord.voice")
    private let signal: Signal
    private let onFailure: @MainActor @Sendable () -> Void
    private let factory: RTCPeerConnectionFactory
    private let device: Device

    private var sendSignaler: TransportSignaler?
    private var receiveSignaler: TransportSignaler?
    private var sendTransport: SendTransport?
    private var receiveTransport: ReceiveTransport?
    private var producer: Producer?
    private var microphone: RTCAudioTrack?
    private var consumers: [Int: Consumer] = [:]
    private var rtpCapabilities = "{}"
    private var soundMuted = false
    private var isClosed = false

    init(signal: @escaping Signal, onFailure: @escaping @MainActor @Sendable () -> Void) {
        Self.configureAudioSession()

        self.signal = signal
        self.onFailure = onFailure
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

    func consume(remoteId: Int) async {
        let input = await onQueueValue { self.rtpCapabilities }

        do {
            let json = try JSONSerialization.data(withJSONObject: [
                "kind": "audio",
                "remoteId": remoteId,
                "rtpCapabilities": try JSONSerialization.jsonObject(with: Data(input.utf8))
            ])
            let data = try await signal("voice.consume", json)
            let consumed = try ConsumeResponse(data)

            try await onQueue {
                try self.addConsumer(remoteId: remoteId, consumed)
            }
        } catch {
            print("[voice] could not consume \(remoteId): \(error)")
        }
    }

    func closeConsumer(remoteId: Int) {
        queue.async {
            self.consumers.removeValue(forKey: remoteId)?.close()
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

    func setSoundMuted(_ muted: Bool) {
        queue.async {
            self.soundMuted = muted

            for consumer in self.consumers.values {
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

        let track = factory.audioTrack(withTrackId: "microphone")

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

    private func addConsumer(remoteId: Int, _ consumed: ConsumeResponse) throws {
        guard let receiveTransport, !isClosed else {
            return
        }

        let consumer = try receiveTransport.consume(
            consumerId: consumed.consumerId,
            producerId: consumed.producerId,
            kind: .audio,
            rtpParameters: consumed.rtpParameters,
            appData: nil
        )

        consumer.track.isEnabled = !soundMuted
        consumers.removeValue(forKey: remoteId)?.close()
        consumers[remoteId] = consumer
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

    private func onQueueValue<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: work())
            }
        }
    }

    // speaker by default like other voice chat apps, voiceChat mode turns on echo cancellation
    private static func configureAudioSession() {
        let configuration = RTCAudioSessionConfiguration.webRTC()

        configuration.category = AVAudioSession.Category.playAndRecord.rawValue
        configuration.mode = AVAudioSession.Mode.voiceChat.rawValue
        configuration.categoryOptions = [.allowBluetoothHFP, .defaultToSpeaker]

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
        let json = Data("{\"transportId\":\"\(transport.id)\",\"kind\":\"audio\",\"rtpParameters\":\(rtpParameters)}".utf8)

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
