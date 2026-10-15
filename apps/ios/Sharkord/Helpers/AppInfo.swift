import UIKit

enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    // shaped like safari's, so the server's user agent parser names the device and os in the
    // devices list instead of showing the networking library. the ipad app on a mac says it is
    // an ipad unless told otherwise, so there it is shaped like safari on a mac
    static let userAgent: String = {
        if ProcessInfo.processInfo.isiOSAppOnMac {
            let system = ProcessInfo.processInfo.operatingSystemVersion
            let os = "\(system.majorVersion)_\(system.minorVersion)"

            return "Mozilla/5.0 (Macintosh; Intel Mac OS X \(os)) AppleWebKit/605.1.15 (KHTML, like Gecko) Sharkord/\(version)"
        }

        let device = UIDevice.current
        let model = device.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        let os = device.systemVersion.replacingOccurrences(of: ".", with: "_")

        return "Mozilla/5.0 (\(model); CPU \(model) OS \(os) like Mac OS X) Sharkord/\(version)"
    }()
}
