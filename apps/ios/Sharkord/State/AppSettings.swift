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

    private init() {
        defaults.register(defaults: [
            Key.echoCancellation: true,
            Key.noiseSuppression: true,
            Key.autoGainControl: true,
            Key.speakerByDefault: true,
            Key.outputVolume: 1.0
        ])

        echoCancellation = defaults.bool(forKey: Key.echoCancellation)
        noiseSuppression = defaults.bool(forKey: Key.noiseSuppression)
        autoGainControl = defaults.bool(forKey: Key.autoGainControl)
        speakerByDefault = defaults.bool(forKey: Key.speakerByDefault)
        outputVolume = defaults.double(forKey: Key.outputVolume)
        streamQuality = defaults.string(forKey: Key.streamQuality).flatMap(StreamQuality.init(rawValue:)) ?? .standard
    }
}
