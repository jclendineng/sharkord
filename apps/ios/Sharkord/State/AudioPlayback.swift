import AVFoundation
import Observation

// the one voice message or audio attachment playing, starting another stops it
@Observable
final class AudioPlayback {
    static let shared = AudioPlayback()

    private(set) var currentFileId: Int?
    private(set) var isPlaying = false
    private(set) var progress: Double = 0

    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?

    private init() {}

    func toggle(fileId: Int, url: URL) {
        if currentFileId == fileId, let player {
            if isPlaying {
                player.pause()
            } else {
                player.play()
            }

            isPlaying.toggle()
            return
        }

        stop()
        prepareSession()

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)

        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 20), queue: .main) { [weak self] time in
            let duration = item.duration.seconds

            MainActor.assumeIsolated {
                self?.progress = duration.isFinite && duration > 0 ? time.seconds / duration : 0
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.stop()
            }
        }

        self.player = player
        currentFileId = fileId
        isPlaying = true
        player.play()
    }

    func stop() {
        player?.pause()

        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
        }

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }

        player = nil
        timeObserver = nil
        endObserver = nil
        currentFileId = nil
        isPlaying = false
        progress = 0
    }

    // in a call the session already plays and records, switching it would cut the call
    private func prepareSession() {
        let session = AVAudioSession.sharedInstance()

        guard session.category != .playAndRecord else {
            return
        }

        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
    }
}
