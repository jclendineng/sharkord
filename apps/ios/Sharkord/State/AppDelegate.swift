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

// what a tapped notification opens, read from the payload the server built in
// queues/push-notifications
enum NotificationTarget {
    case message(serverId: String, channelId: Int, messageId: Int?, threadParentId: Int?)
    // someone signed in somewhere else: the devices, to sign it out if it was not you
    case newLogin(serverId: String)

    var serverId: String {
        switch self {
        case let .message(serverId, _, _, _), let .newLogin(serverId):
            serverId
        }
    }

    init?(_ userInfo: [AnyHashable: Any]) {
        guard let serverId = userInfo["serverId"] as? String else {
            return nil
        }

        if userInfo["kind"] as? String == "newLogin" {
            self = .newLogin(serverId: serverId)
        } else if let channelId = userInfo["channelId"] as? Int {
            self = .message(
                serverId: serverId,
                channelId: channelId,
                messageId: userInfo["messageId"] as? Int,
                threadParentId: userInfo["parentMessageId"] as? Int
            )
        } else {
            return nil
        }
    }
}

// remote notifications still only reach an app through its UIKit or AppKit delegate
final class AppDelegate: NSObject, PlatformApplicationDelegate, UNUserNotificationCenterDelegate {
    // handed over by SharkordApp, the system creates the delegate before any SwiftUI state exists
    var servers: ServerListStore? {
        didSet {
            if let servers, let pendingTarget {
                self.pendingTarget = nil
                servers.open(pendingTarget)
            }
        }
    }

    // a tap that launched the app comes in before SharkordApp has handed the servers over
    private var pendingTarget: NotificationTarget?

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
        guard let target = NotificationTarget(response.notification.request.content.userInfo) else {
            return
        }

        if let servers {
            servers.open(target)
        } else {
            pendingTarget = target
        }
    }

    private func target(_ notification: UNNotification) -> (SessionStore, Int)? {
        guard
            case let .message(serverId, channelId, _, _) = NotificationTarget(notification.request.content.userInfo),
            let session = servers?.session(serverId: serverId)
        else {
            return nil
        }

        return (session, channelId)
    }
}
