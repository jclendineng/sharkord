import UIKit

enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    // shaped like safari's, so the server's user agent parser names the device and os in the
    // devices list instead of showing the networking library
    static let userAgent: String = {
        let device = UIDevice.current
        let model = device.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        let os = device.systemVersion.replacingOccurrences(of: ".", with: "_")

        return "Mozilla/5.0 (\(model); CPU \(model) OS \(os) like Mac OS X) Sharkord/\(version)"
    }()
}

extension AppInfo {
    // where "report server" sends its email. empty until there is an address, the button
    // then says reporting is not set up yet
    static let reportEmail = ""
}
