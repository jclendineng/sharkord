import Foundation

// what the share sheet's Sharkord hands the app: a folder for each share in the app group, with
// the shared files and, for shared text or a link, a text file the message starts from
enum ShareInbox {
    static let groupId = "group.com.sharkord.ios"
    static let textFileName = "shared-text.txt"

    static var directory: URL? {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupId) else {
            return nil
        }

        return container.appending(path: "Shares", directoryHint: .isDirectory)
    }

    static func openURL(for shareId: String) -> URL? {
        URL(string: "sharkord://share/\(shareId)")
    }
}
