import UIKit

// where a permission is changed. an iphone or ipad app's own settings page is what apple's
// links open, but on a mac they land on Touch Alternatives, the page for running an ipad app
// there, so the mac goes to the matching pane of System Settings instead
enum SystemSettings {
    enum Pane {
        case notifications
        case camera
        case photos
    }

    private static let isMac = ProcessInfo.processInfo.isiOSAppOnMac

    // what the app is called on this device, for "set in ..." wording
    static var name: String {
        isMac ? "System Settings" : "Settings"
    }

    static func url(for pane: Pane) -> URL? {
        guard isMac else {
            return URL(string: pane == .notifications ? UIApplication.openNotificationSettingsURLString : UIApplication.openSettingsURLString)
        }

        switch pane {
        case .notifications:
            return URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
        case .camera:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")
        case .photos:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos")
        }
    }
}
