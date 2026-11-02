#if os(iOS)
import UIKit
import UniformTypeIdentifiers

// the field's own paste takes text and pictures, and drops any other file without a word, even
// though the edit menu offers Paste for it. its pastes come here first, and anything that isn't
// text goes to the message as an attachment. the rest is swiftui's, passed on untouched
final class FilePaste: NSObject, UITextPasteDelegate {
    var canTakeFiles: () -> Bool = { false }
    var onFiles: ([NSItemProvider]) -> Void = { _ in }

    // read by the runtime from outside the main actor when it forwards a call
    nonisolated(unsafe) private weak var forwarded: UITextPasteDelegate?

    // swiftui's text view is out of reach, so it is found as the first responder once focused.
    // the text view holds its delegate weakly, so the caller keeps this one
    @MainActor
    func install() {
        guard let textView = FirstResponder.find() as? UITextView, textView.pasteDelegate !== self else {
            return
        }

        forwarded = textView.pasteDelegate
        textView.pasteDelegate = self
    }

    func textPasteConfigurationSupporting(_ textPasteConfigurationSupporting: UITextPasteConfigurationSupporting, transform item: UITextPasteItem) {
        let provider = item.itemProvider
        // a file copied in Files carries its name, which copied text doesn't, and a text file
        // conforms to text as well
        let isFile = provider.suggestedName != nil || provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        let isText = provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) || provider.hasItemConformingToTypeIdentifier(UTType.url.identifier)

        guard (isText && !isFile) || !canTakeFiles() else {
            onFiles([provider])
            item.setNoResult()
            return
        }

        if let forwarded, forwarded.responds(to: #selector(UITextPasteDelegate.textPasteConfigurationSupporting(_:transform:))) {
            forwarded.textPasteConfigurationSupporting?(textPasteConfigurationSupporting, transform: item)
        } else {
            item.setDefaultResult()
        }
    }

    nonisolated override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || forwarded?.responds(to: selector) == true
    }

    nonisolated override func forwardingTarget(for selector: Selector!) -> Any? {
        forwarded
    }
}

@MainActor
private enum FirstResponder {
    static weak var found: UIResponder?

    static func find() -> UIResponder? {
        found = nil
        UIApplication.shared.sendAction(#selector(UIResponder.recordAsFirstResponder), to: nil, from: nil, for: nil)

        return found
    }
}

private extension UIResponder {
    @objc func recordAsFirstResponder() {
        FirstResponder.found = self
    }
}
#endif
