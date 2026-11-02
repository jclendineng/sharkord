import Foundation

// what the share sheet's Sharkord hands the app: a folder for each share in the app group, with
// the shared files and, for shared text or a link, a text file the message starts from
enum ShareInbox {
    // a mac only lets a group named for the team into a sandbox without a profile granting it,
    // and xcode signs the extension there with one that grants none
    #if os(macOS)
    static let groupId = "KNSS87R6RR.com.sharkord.ios"
    #else
    static let groupId = "group.com.sharkord.ios"
    #endif
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
