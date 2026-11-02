import Foundation

// what another app shared to Sharkord, waiting on the Share To screen for where it goes
struct PendingShare: Identifiable {
    let id: String
    let folder: URL
    let files: [URL]
    let text: String

    // the newest share in the inbox. an older one was never sent, and goes
    static func latest() -> PendingShare? {
        guard let inbox = ShareInbox.directory,
              let folders = try? FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: [.creationDateKey]) else {
            return nil
        }

        let newestFirst = folders.sorted { creationDate(of: $0) > creationDate(of: $1) }

        guard let folder = newestFirst.first else {
            return nil
        }

        for stale in newestFirst.dropFirst() {
            try? FileManager.default.removeItem(at: stale)
        }

        let contents = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let textFile = contents.first { $0.lastPathComponent == ShareInbox.textFileName }
        let files = contents
            .filter { $0.lastPathComponent != ShareInbox.textFileName }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let text = textFile.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""

        return PendingShare(id: folder.lastPathComponent, folder: folder, files: files, text: text)
    }

    func discard() {
        try? FileManager.default.removeItem(at: folder)
    }

    private static func creationDate(of url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.creationDateKey])

        return values?.creationDate ?? .distantPast
    }
}
