import Foundation
import Observation

// device wide preferences from the settings screens, kept in UserDefaults
@Observable
final class AppSettings {
    enum StreamQuality: String, CaseIterable {
        case standard
        case high

        var maxDimension: Int {
            self == .high ? 1920 : 1280
        }

        // jpeg frames through the extension, 30 per second is what it keeps up with
        var framesPerSecond: Int {
            30
        }
    }

    static let shared = AppSettings()

    private enum Key {
        static let echoCancellation = "settings.echoCancellation"
        static let noiseSuppression = "settings.noiseSuppression"
        static let autoGainControl = "settings.autoGainControl"
        static let speakerByDefault = "settings.speakerByDefault"
        static let outputVolume = "settings.outputVolume"
        static let streamQuality = "settings.streamQuality"
        static let shareAppAudio = "settings.shareAppAudio"
        static let hearYourselfInCalls = "settings.hearYourselfInCalls"
        static let incomingVideoOff = "settings.incomingVideoOff"
        static let soundboardVolume = "settings.soundboardVolume"
        static let doubleTapReaction = "settings.doubleTapReaction"
        static let inputDeviceId = "settings.inputDeviceId"
        static let cameraDeviceId = "settings.cameraDeviceId"
        static let pushToTalk = "settings.pushToTalk"
        static let pushToTalkKey = "settings.pushToTalkKey"
        static let inputGain = "settings.inputGain"
    }

    private let defaults = UserDefaults.standard

    var echoCancellation: Bool {
        didSet { defaults.set(echoCancellation, forKey: Key.echoCancellation) }
    }

    var noiseSuppression: Bool {
        didSet { defaults.set(noiseSuppression, forKey: Key.noiseSuppression) }
    }

    var autoGainControl: Bool {
        didSet { defaults.set(autoGainControl, forKey: Key.autoGainControl) }
    }

    var speakerByDefault: Bool {
        didSet { defaults.set(speakerByDefault, forKey: Key.speakerByDefault) }
    }

    // 0 to 2, where 1 plays everyone as they arrive
    var outputVolume: Double {
        didSet { defaults.set(outputVolume, forKey: Key.outputVolume) }
    }

    var streamQuality: StreamQuality {
        didSet { defaults.set(streamQuality.rawValue, forKey: Key.streamQuality) }
    }

    // puts the game's sound into a screen share, by swapping webrtc's audio device for
    // MixingAudioDevice. off by default while that is new
    var shareAppAudio: Bool {
        didSet { defaults.set(shareAppAudio, forKey: Key.shareAppAudio) }
    }

    // plays your own mic back to you during a call. like app audio it needs MixingAudioDevice,
    // the built in device has no way to send the mic to the speaker
    var hearYourselfInCalls: Bool {
        didSet { defaults.set(hearYourselfInCalls, forKey: Key.hearYourselfInCalls) }
    }

    // cameras and screen shares are not received at all, to save a weak connection
    var incomingVideoOff: Bool {
        didSet { defaults.set(incomingVideoOff, forKey: Key.incomingVideoOff) }
    }

    // 0 to 1, how loud soundboard sounds play for this person, on top of each sound's own volume
    var soundboardVolume: Double {
        didSet { defaults.set(soundboardVolume, forKey: Key.soundboardVolume) }
    }

    // the shortcode a double tap on a message reacts with, picked from the message menu's
    // edit link like discord's
    var doubleTapReaction: String {
        didSet { defaults.set(doubleTapReaction, forKey: Key.doubleTapReaction) }
    }

    // the mic picked in voice settings, nil for automatic, see AudioInputPreference
    var inputDeviceId: String? {
        didSet { defaults.set(inputDeviceId, forKey: Key.inputDeviceId) }
    }

    // the mac camera picked in voice settings by its unique id, nil for the first one there
    var cameraDeviceId: String? {
        didSet { defaults.set(cameraDeviceId, forKey: Key.cameraDeviceId) }
    }

    // the mic stays closed in a call until a key is held, see PushToTalk
    var pushToTalk: Bool {
        didSet { defaults.set(pushToTalk, forKey: Key.pushToTalk) }
    }

    var pushToTalkKey: PushToTalkKey {
        didSet { defaults.set(pushToTalkKey.rawValue, forKey: Key.pushToTalkKey) }
    }

    // 0 to 1, the input device's own gain where it lets it be set, see AudioInputPreference
    var inputGain: Double {
        didSet { defaults.set(inputGain, forKey: Key.inputGain) }
    }

    private init() {
        defaults.register(defaults: [
            Key.echoCancellation: true,
            Key.noiseSuppression: true,
            Key.autoGainControl: true,
            Key.speakerByDefault: true,
            Key.outputVolume: 1.0,
            Key.soundboardVolume: 1.0,
            Key.doubleTapReaction: "heart",
            Key.inputGain: 1.0
        ])

        echoCancellation = defaults.bool(forKey: Key.echoCancellation)
        noiseSuppression = defaults.bool(forKey: Key.noiseSuppression)
        autoGainControl = defaults.bool(forKey: Key.autoGainControl)
        speakerByDefault = defaults.bool(forKey: Key.speakerByDefault)
        outputVolume = defaults.double(forKey: Key.outputVolume)
        shareAppAudio = defaults.bool(forKey: Key.shareAppAudio)
        hearYourselfInCalls = defaults.bool(forKey: Key.hearYourselfInCalls)
        incomingVideoOff = defaults.bool(forKey: Key.incomingVideoOff)
        soundboardVolume = defaults.double(forKey: Key.soundboardVolume)
        doubleTapReaction = defaults.string(forKey: Key.doubleTapReaction) ?? "heart"
        inputDeviceId = defaults.string(forKey: Key.inputDeviceId)
        cameraDeviceId = defaults.string(forKey: Key.cameraDeviceId)
        pushToTalk = defaults.bool(forKey: Key.pushToTalk)
        pushToTalkKey = defaults.string(forKey: Key.pushToTalkKey).flatMap(PushToTalkKey.init(rawValue:)) ?? .rightOption
        inputGain = defaults.double(forKey: Key.inputGain)
        streamQuality = defaults.string(forKey: Key.streamQuality).flatMap(StreamQuality.init(rawValue:)) ?? .standard
    }
}
