import AVFoundation

// which mic calls, the mic test and voice messages use: the one picked in voice settings, or
// else a headset's whenever one is plugged in, which matters most on a mac with no mic of its
// own. kept to on every route change, since webrtc's own audio device sets the session up where
// nothing here can reach it
enum AudioInputPreference {
    private static let headsets: Set<AVAudioSession.Port> = [.bluetoothHFP, .headsetMic, .usbAudio]
    private static var observer: NSObjectProtocol?

    static func start() {
        guard observer == nil else {
            return
        }

        observer = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                apply()
            }
        }
    }

    static func apply() {
        let session = AVAudioSession.sharedInstance()

        guard session.category == .playAndRecord, let inputs = session.availableInputs else {
            return
        }

        let pickedId = AppSettings.shared.inputDeviceId
        let picked = inputs.first { $0.uid == pickedId }

        guard let target = picked ?? inputs.first(where: { headsets.contains($0.portType) }) else {
            return
        }

        // setting it is itself a route change, which would come straight back here
        let current = session.currentRoute.inputs.first

        if current?.uid != target.uid {
            try? session.setPreferredInput(target)
        }
    }
}
