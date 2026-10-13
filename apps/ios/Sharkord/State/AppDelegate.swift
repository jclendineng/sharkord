import UIKit
import UserNotifications

// remote notifications still only reach an app through its UIKit delegate
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    // handed over by SharkordApp, UIKit creates the delegate before any SwiftUI state exists
    var servers: ServerListStore?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self

        return true
    }

    // the same token goes to every server, each one only pushes for its own account
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
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
