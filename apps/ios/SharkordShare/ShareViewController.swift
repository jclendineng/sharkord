import UIKit
import UniformTypeIdentifiers

// the share sheet's Sharkord. it copies what was shared where the app can read it and opens the
// app, whose Share To screen picks where it goes, since only the app is signed in to servers
final class ShareViewController: UIViewController {
    private var hasStarted = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        guard !hasStarted else {
            return
        }

        hasStarted = true

        Task {
            await handOff()
        }
    }

    private func handOff() async {
        let shareId = UUID().uuidString

        guard let inbox = ShareInbox.directory else {
            finish()
            return
        }

        let folder = inbox.appending(path: shareId, directoryHint: .isDirectory)
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        let providers = items.flatMap { $0.attachments ?? [] }
        var texts: [String] = []

        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            finish()
            return
        }

        for provider in providers {
            if let text = await Self.text(of: provider) {
                texts.append(text)
            } else {
                await Self.saveFile(of: provider, into: folder)
            }
        }

        if !texts.isEmpty {
            let text = texts.joined(separator: "\n")

            try? text.write(to: folder.appending(path: ShareInbox.textFileName), atomically: true, encoding: .utf8)
        }

        if let url = ShareInbox.openURL(for: shareId) {
            openApp(url)
        }

        finish()
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

    // an extension may not call UIApplication's open, so it is found up the responder chain and
    // called through the runtime. should iOS stop allowing it, the app still finds the share the
    // next time it comes forward
    private func openApp(_ url: URL) {
        typealias Open = @convention(c) (AnyObject, Selector, URL, [String: Any], ((Bool) -> Void)?) -> Void

        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        var responder: UIResponder? = self

        while let current = responder {
            if current is UIApplication, current.responds(to: selector) {
                let open = unsafeBitCast(current.method(for: selector), to: Open.self)

                open(current, selector, url, [:], nil)
                return
            }

            responder = current.next
        }
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
