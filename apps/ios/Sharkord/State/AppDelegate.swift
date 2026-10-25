import UserNotifications
#if os(macOS)
import AppKit

typealias PlatformApplication = NSApplication
typealias PlatformApplicationDelegate = NSApplicationDelegate
#else
import UIKit

typealias PlatformApplication = UIApplication
typealias PlatformApplicationDelegate = UIApplicationDelegate
#endif

// remote notifications still only reach an app through its UIKit or AppKit delegate
final class AppDelegate: NSObject, PlatformApplicationDelegate, UNUserNotificationCenterDelegate {
    // handed over by SharkordApp, the system creates the delegate before any SwiftUI state exists
    var servers: ServerListStore?

    #if os(macOS)
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        // one window, as messages has, with no tab bar to show in the view menu
        NSWindow.allowsAutomaticWindowTabbing = false
    }
    #else
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self

        return true
    }
    #endif

    // the same token goes to every server, each one only pushes for its own account
    func application(_ application: PlatformApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()

        Task {
            await servers?.registerPushDevice(token)
        }
    }

    // the channel already on screen shows the message as it arrives, a banner on top is noise
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        if
            let (session, channelId) = target(notification),
            session.isChannelVisible(channelId)
        {
            return []
        }

        return [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo

        // a new login somewhere else: the devices, to sign it out if it was not you
        if
            userInfo["kind"] as? String == "newLogin",
            let serverId = userInfo["serverId"] as? String,
            let session = servers?.session(serverId: serverId)
        {
            servers?.showDevices(for: session)
            return
        }

        if let (session, channelId) = target(response.notification) {
            servers?.open(channelId: channelId, in: session)
        }
    }

    private func target(_ notification: UNNotification) -> (SessionStore, Int)? {
        let userInfo = notification.request.content.userInfo

        guard
            let serverId = userInfo["serverId"] as? String,
            let channelId = userInfo["channelId"] as? Int,
            let session = servers?.session(serverId: serverId)
        else {
            return nil
        }

        return (session, channelId)
    }
}
