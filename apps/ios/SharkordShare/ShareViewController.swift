#if os(iOS)
import UIKit

// the share sheet's Sharkord. it copies what was shared where the app can read it and opens the
// app, whose Share To screen picks where it goes, since only the app is signed in to servers
final class ShareViewController: UIViewController {
    // starts as soon as it loads rather than once its sheet is up, and draws nothing, so only
    // a moment of the system's sheet shows before the app opens
    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .clear

        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []

        Task {
            if let url = await ShareHandoff.copy(items) {
                openApp(url)
            }

            finish()
        }
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
#elseif os(macOS)
import AppKit

// the share menu's Sharkord on a mac, which hands off the same way and opens the app the usual way
final class ShareViewController: NSViewController {
    override func loadView() {
        view = NSView(frame: .zero)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []

        Task {
            if let url = await ShareHandoff.copy(items) {
                NSWorkspace.shared.open(url)
            }

            extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
#endif
