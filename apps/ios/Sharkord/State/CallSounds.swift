import AVFoundation

// the web client's sounds for joining and leaving a call and for your own mic, deafen, camera
// and share, its own recipes rendered to files, played out of whatever the call plays through.
// off the main thread: a player starting can wait on the audio hardware, which stalled the call
// sheet's slide
nonisolated final class CallSounds: @unchecked Sendable {
    enum Sound: String {
        case join = "call-join"
        case leave = "call-leave"
        case mute = "call-mute"
        // deafening plays these too
        case unmute = "call-unmute"
        case cameraOn = "call-camera-on"
        case cameraOff = "call-camera-off"
        case shareOn = "call-share-on"
        case shareOff = "call-share-off"
    }

    private let queue = DispatchQueue(label: "call-sounds")
    // kept for the next time, a player let go stops at once
    private var players: [Sound: AVAudioPlayer] = [:]

    func play(_ sound: Sound) {
        queue.async {
            guard let player = self.player(for: sound) else {
                return
            }

            player.currentTime = 0
            player.play()
        }
    }

    private func player(for sound: Sound) -> AVAudioPlayer? {
        if let player = players[sound] {
            return player
        }

        guard
            let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "caf"),
            let player = try? AVAudioPlayer(contentsOf: url)
        else {
            return nil
        }

        players[sound] = player
        return player
    }
}
