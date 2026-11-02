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
#elseif os(macOS)
import AppKit
import ObjectiveC

// the mac field pastes a file copied in Finder as its path, and a dropped one too, and has no
// paste delegate to ask first. swiftui's text view class gets a paste and a drop of its own,
// which hand files and pictures to the composer whose text view this is, and pass everything
// else on as usual
final class FilePaste {
    var canTakeFiles: () -> Bool = { false }
    var onFiles: ([NSItemProvider]) -> Void = { _ in }

    private static weak var current: FilePaste?
    private weak var textView: NSTextView?

    func install() {
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else {
            return
        }

        self.textView = textView
        Self.current = self
        Self.override(Self.unobservedClass(of: textView))
    }

    // ready before anyone clicks into a box, so the first drag over it is caught too. found by
    // name, should swiftui rename it the first focus still does it
    static func prepare() {
        override(NSClassFromString("SwiftUI.AttributedPlatformTextView"))
    }

    // the class itself, under the subclass key-value observing puts on the instance
    private static func unobservedClass(of textView: NSTextView) -> AnyClass? {
        var textViewClass: AnyClass? = object_getClass(textView)

        while let observed = textViewClass, NSStringFromClass(observed).hasPrefix("NSKVONotifying_") {
            textViewClass = class_getSuperclass(observed)
        }

        return textViewClass
    }

    // whether the paste or drop was taken as files, leaving text to the field
    private func take(_ pasteboard: NSPasteboard, in textView: NSTextView) -> Bool {
        guard textView === self.textView, canTakeFiles() else {
            return false
        }

        let hasFiles = pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])

        guard hasFiles || pasteboard.string(forType: .string) == nil else {
            return false
        }

        let providers = Platform.items(on: pasteboard)

        guard !providers.isEmpty else {
            return false
        }

        onFiles(providers)

        return true
    }

    // a picture dragged out of Photos is a promise of a file, written out before it is attached
    private func takePromises(_ pasteboard: NSPasteboard, in textView: NSTextView) -> Bool {
        guard textView === self.textView, canTakeFiles(),
              let receivers = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver],
              !receivers.isEmpty else {
            return false
        }

        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return false
        }

        for receiver in receivers {
            receiver.receivePromisedFiles(atDestination: directory, operationQueue: .main) { [weak self] url, error in
                guard error == nil, let provider = NSItemProvider(contentsOf: url) else {
                    return
                }

                MainActor.assumeIsolated {
                    self?.onFiles([provider])
                }
            }
        }

        return true
    }

    // added to the class rather than the instance, so it outlasts any subclass put on the
    // instance. NSTextView's own paste and drop are the rest of the time
    private static func override(_ textViewClass: AnyClass?) {
        typealias Paste = @convention(c) (NSTextView, Selector, Any?) -> Void
        typealias Drop = @convention(c) (NSTextView, Selector, NSDraggingInfo) -> Bool
        typealias Enter = @convention(c) (NSTextView, Selector, NSDraggingInfo) -> NSDragOperation

        let pasteSelector = #selector(NSText.paste(_:))
        let dropSelector = #selector(NSTextView.performDragOperation(_:))
        let enterSelector = #selector(NSTextView.draggingEntered(_:))

        guard let textViewClass,
              let originalPaste = class_getMethodImplementation(NSTextView.self, pasteSelector),
              let originalDrop = class_getMethodImplementation(NSTextView.self, dropSelector),
              let originalEnter = class_getMethodImplementation(NSTextView.self, enterSelector) else {
            return
        }

        let paste: @convention(block) (NSTextView, Any?) -> Void = { textView, sender in
            let isTaken = MainActor.assumeIsolated {
                current?.take(.general, in: textView) == true
            }

            if !isTaken {
                unsafeBitCast(originalPaste, to: Paste.self)(textView, pasteSelector, sender)
            }
        }

        let drop: @convention(block) (NSTextView, NSDraggingInfo) -> Bool = { textView, info in
            let isTaken = MainActor.assumeIsolated {
                let pasteboard = info.draggingPasteboard

                return current?.take(pasteboard, in: textView) == true || current?.takePromises(pasteboard, in: textView) == true
            }

            return isTaken || unsafeBitCast(originalDrop, to: Drop.self)(textView, dropSelector, info)
        }

        // a drag over a box nobody has clicked into focuses it, so its composer installs this
        // before the drop lands
        let enter: @convention(block) (NSTextView, NSDraggingInfo) -> NSDragOperation = { textView, info in
            MainActor.assumeIsolated {
                if let window = textView.window, window.firstResponder !== textView {
                    window.makeFirstResponder(textView)
                }
            }

            return unsafeBitCast(originalEnter, to: Enter.self)(textView, enterSelector, info)
        }

        // each a no-op once the class has it
        class_addMethod(textViewClass, pasteSelector, imp_implementationWithBlock(paste), "v@:@")
        class_addMethod(textViewClass, dropSelector, imp_implementationWithBlock(drop), "B@:@")
        class_addMethod(textViewClass, enterSelector, imp_implementationWithBlock(enter), "Q@:@")
    }
}
#endif
