import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit

typealias PlatformImage = NSImage
typealias PlatformColor = NSColor
typealias PlatformView = NSView
typealias PlatformTextContentType = NSTextContentType
#else
import UIKit

typealias PlatformImage = UIImage
typealias PlatformColor = UIColor
typealias PlatformView = UIView
typealias PlatformTextContentType = UITextContentType
#endif

enum Platform {
    // the native mac app, or the ipad app running on one: both get the pointer, the hover and the
    // window behaviour
    static let isMac: Bool = {
        #if os(macOS)
        true
        #else
        ProcessInfo.processInfo.isiOSAppOnMac
        #endif
    }()

    // the ipad app says it is an ipad on a mac too, so the native one keeps the layouts it had
    static let isPad: Bool = {
        #if os(macOS)
        true
        #else
        UIDevice.current.userInterfaceIdiom == .pad
        #endif
    }()

    static var isPhone: Bool {
        !isPad
    }

    // in front and in use. a mac app keeps running behind others, with its chat still on screen
    static var isAppActive: Bool {
        #if os(macOS)
        NSApp.isActive
        #else
        UIApplication.shared.applicationState == .active
        #endif
    }

    static var displayScale: CGFloat {
        #if os(macOS)
        NSScreen.main?.backingScaleFactor ?? 2
        #else
        UITraitCollection.current.displayScale
        #endif
    }

    static func copy(_ text: String?) {
        #if os(macOS)
        NSPasteboard.general.clearContents()

        if let text {
            NSPasteboard.general.setString(text, forType: .string)
        }
        #else
        UIPasteboard.general.string = text
        #endif
    }

    static func copy(_ url: URL?) {
        #if os(macOS)
        copy(url?.absoluteString)
        #else
        UIPasteboard.general.url = url
        #endif
    }

    // what was copied, for a paste the message box took as a picture it cannot show
    static var pasteboardItems: [NSItemProvider] {
        #if os(macOS)
        items(on: .general)
        #else
        UIPasteboard.general.itemProviders
        #endif
    }

    #if os(macOS)
    // files dragged or copied from Finder, else a picture, on the clipboard or a drag's own board
    static func items(on pasteboard: NSPasteboard) -> [NSItemProvider] {
        let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []

        // a provider made from a file is named for its type on a mac, "text.txt", unless told
        if !fileURLs.isEmpty {
            return fileURLs.compactMap { url in
                let provider = NSItemProvider(contentsOf: url)

                provider?.suggestedName = url.lastPathComponent

                return provider
            }
        }

        guard let png = pasteboard.data(forType: .png) else {
            return pasteboard.data(forType: .tiff).map { [NSItemProvider(item: $0 as NSData, typeIdentifier: UTType.tiff.identifier)] } ?? []
        }

        return [NSItemProvider(item: png as NSData, typeIdentifier: UTType.png.identifier)]
    }
    #endif

    static func dismissKeyboard() {
        #if os(macOS)
        NSApp.keyWindow?.makeFirstResponder(nil)
        #else
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }
}

// a mac taps through a force touch trackpad, the only part of it that can, and only while a
// finger is on it. it has one kind of tap, so they are all the same there. a phone's are kept
// rather than made for each tap: a new one has to wake the engine first and its tap landed a
// beat after what it was for
enum Haptics {
    #if os(iOS)
    private static let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private static let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private static let selectionChange = UISelectionFeedbackGenerator()
    private static let notification = UINotificationFeedbackGenerator()
    #endif

    // a finger has landed on something a hold will answer with a tap, so the engine is awake
    // by the time the hold is recognized
    static func prepare() {
        #if os(iOS)
        mediumImpact.prepare()
        #endif
    }

    static func light() {
        #if os(iOS)
        lightImpact.impactOccurred()
        lightImpact.prepare()
        #else
        tapTrackpad()
        #endif
    }

    static func medium() {
        #if os(iOS)
        mediumImpact.impactOccurred()
        #else
        tapTrackpad()
        #endif
    }

    static func selection() {
        #if os(iOS)
        selectionChange.selectionChanged()
        selectionChange.prepare()
        #else
        tapTrackpad()
        #endif
    }

    static func success() {
        #if os(iOS)
        notification.notificationOccurred(.success)
        #else
        tapTrackpad()
        #endif
    }

    #if os(macOS)
    private static func tapTrackpad() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }
    #endif
}

extension Image {
    init(platformImage: PlatformImage) {
        #if os(macOS)
        self.init(nsImage: platformImage)
        #else
        self.init(uiImage: platformImage)
        #endif
    }
}

#if os(macOS)
// the parts of UIImage the shared code calls, so it reads the same on both. nonisolated like
// UIImage's own, images are made and encoded off the main thread
nonisolated extension NSImage {
    convenience init(cgImage: CGImage) {
        self.init(cgImage: cgImage, size: .zero)
    }

    var cgImage: CGImage? {
        cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    // appkit decodes when it draws, there is nothing to prepare ahead of time
    func preparingForDisplay() -> NSImage? {
        self
    }

    // made from pixels, so a point is a pixel
    var scale: CGFloat {
        1
    }

    func pngData() -> Data? {
        bitmap?.representation(using: .png, properties: [:])
    }

    func jpegData(compressionQuality: CGFloat) -> Data? {
        bitmap?.representation(using: .jpeg, properties: [.compressionFactor: compressionQuality])
    }

    private var bitmap: NSBitmapImageRep? {
        guard let cgImage else {
            return nil
        }

        return NSBitmapImageRep(cgImage: cgImage)
    }
}
#endif
