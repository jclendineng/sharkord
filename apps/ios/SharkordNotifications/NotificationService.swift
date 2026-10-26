import UserNotifications

// a push the relay carried holds only ciphertext, sealed by the server to this device's key for
// it. here it becomes the real title and body, with the server and channel a tap opens. one that
// does not open keeps the relay's own generic text
final class NotificationService: UNNotificationServiceExtension {
    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        guard
            let content = request.content.mutableCopy() as? UNMutableNotificationContent,
            let encrypted = content.userInfo["encrypted"] as? String,
            let opened = PushKeys.open(encrypted),
            var payload = (try? JSONSerialization.jsonObject(with: opened)) as? [String: Any]
        else {
            contentHandler(request.content)
            return
        }

        if let aps = payload.removeValue(forKey: "aps") as? [String: Any] {
            if let alert = aps["alert"] as? [String: Any] {
                content.title = alert["title"] as? String ?? ""
                content.subtitle = alert["subtitle"] as? String ?? ""
                content.body = alert["body"] as? String ?? ""
            } else if let body = aps["alert"] as? String {
                content.body = body
            }

            if let threadId = aps["thread-id"] as? String {
                content.threadIdentifier = threadId
            }
        }

        content.userInfo = payload
        contentHandler(content)
    }
}
