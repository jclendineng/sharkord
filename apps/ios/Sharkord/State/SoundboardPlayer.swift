import AVFoundation

// plays soundboard sounds out of whatever the call plays through, each app on its own, so a
// sound is never mixed into anyone's mic. a sound is fetched once and kept for the next time
@MainActor
final class SoundboardPlayer {
    private var cache: [URL: Data] = [:]
    // held while they play, a player let go stops at once
    private var players: [AVAudioPlayer] = []

    func play(_ url: URL, volume: Float) async {
        let data: Data

        if let cached = cache[url] {
            data = cached
        } else {
            guard let (fetched, _) = try? await URLSession.shared.data(from: url) else {
                return
            }

            cache[url] = fetched
            data = fetched
        }

        guard let player = try? AVAudioPlayer(data: data) else {
            return
        }

        player.volume = volume
        players.removeAll { !$0.isPlaying }
        players.append(player)
        player.play()
    }
}
