import GameController

// discord's push to talk on a mac, or an ipad with a keyboard: in a call the mic stays closed
// until the key is held. read through the game controller framework, which sees a modifier held
// on its own and its release, where the responder chain only sees what a text field leaves
enum PushToTalk {
    private static weak var servers: ServerListStore?
    private static var observer: NSObjectProtocol?

    static func start(servers: ServerListStore) {
        self.servers = servers

        guard observer == nil else {
            return
        }

        attach(GCKeyboard.coalesced)

        // the coalesced keyboard is every keyboard as one, read again once a new one connects
        observer = NotificationCenter.default.addObserver(forName: .GCKeyboardDidConnect, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                attach(GCKeyboard.coalesced)
            }
        }
    }

    private static func attach(_ keyboard: GCKeyboard?) {
        keyboard?.keyboardInput?.keyChangedHandler = { _, _, keyCode, pressed in
            Task { @MainActor in
                keyChanged(keyCode, pressed: pressed)
            }
        }
    }

    private static func keyChanged(_ keyCode: GCKeyCode, pressed: Bool) {
        let settings = AppSettings.shared

        guard settings.pushToTalk, keyCode == settings.pushToTalkKey.keyCode else {
            return
        }

        servers?.voiceSession?.setPushToTalkHeld(pressed)
    }
}

// keys that type nothing on their own, so holding one to talk never ends up in a message
enum PushToTalkKey: String, CaseIterable, Identifiable {
    case rightOption
    case rightControl
    case rightCommand
    case rightShift

    var id: Self { self }

    var title: String {
        switch self {
        case .rightOption:
            String(localized: "Right Option")
        case .rightControl:
            String(localized: "Right Control")
        case .rightCommand:
            String(localized: "Right Command")
        case .rightShift:
            String(localized: "Right Shift")
        }
    }

    var keyCode: GCKeyCode {
        switch self {
        case .rightOption:
            .rightAlt
        case .rightControl:
            .rightControl
        case .rightCommand:
            .rightGUI
        case .rightShift:
            .rightShift
        }
    }
}
