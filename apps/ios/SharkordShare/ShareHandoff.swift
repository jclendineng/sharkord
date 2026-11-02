import Foundation
import UniformTypeIdentifiers

// copies what was shared into the app group's inbox for the app to send on, the same on a phone
// and on a mac
@MainActor
enum ShareHandoff {
    // the link that opens the app on the copied share, nil when there was nowhere to copy it
    static func copy(_ items: [NSExtensionItem]) async -> URL? {
        let shareId = UUID().uuidString

        guard let inbox = ShareInbox.directory else {
            return nil
        }

        let folder = inbox.appending(path: shareId, directoryHint: .isDirectory)
        let providers = items.flatMap { $0.attachments ?? [] }
        var texts: [String] = []

        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        for provider in providers {
            if let text = await text(of: provider) {
                texts.append(text)
            } else {
                await saveFile(of: provider, into: folder)
            }
        }

        if !texts.isEmpty {
            let text = texts.joined(separator: "\n")

            try? text.write(to: folder.appending(path: ShareInbox.textFileName), atomically: true, encoding: .utf8)
        }

        return ShareInbox.openURL(for: shareId)
    }

    // a web link, or a piece of text. a text file carries its name and stays a file
    private static func text(of provider: NSItemProvider) async -> String? {
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
           !provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
           let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
            return url.absoluteString
        }

        if provider.suggestedName == nil,
           provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
           let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
            return text
        }

        return nil
    }

    private static func saveFile(of provider: NSItemProvider, into folder: URL) async {
        let typeIdentifier = provider.registeredTypeIdentifiers.first { identifier in
            UTType(identifier)?.conforms(to: .data) == true
        }

        guard let typeIdentifier else {
            return
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            _ = provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, _ in
                if let url {
                    let target = folder.appending(path: fileName(for: url, provider: provider, typeIdentifier: typeIdentifier))

                    try? FileManager.default.copyItem(at: url, to: target)
                }

                continuation.resume()
            }
        }
    }

    // photos come out as a temporary name, the shared item's own reads better in the message
    private nonisolated static func fileName(for url: URL, provider: NSItemProvider, typeIdentifier: String) -> String {
        guard let name = provider.suggestedName, !name.isEmpty else {
            return url.lastPathComponent
        }

        let fileExtension = url.pathExtension.isEmpty ? UTType(typeIdentifier)?.preferredFilenameExtension : url.pathExtension

        guard let fileExtension, (name as NSString).pathExtension.isEmpty else {
            return name
        }

        return "\(name).\(fileExtension)"
    }
}
