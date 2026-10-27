import SwiftUI
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

    static func dismissKeyboard() {
        #if os(macOS)
        NSApp.keyWindow?.makeFirstResponder(nil)
        #else
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }
}

// a mac taps through a force touch trackpad, the only part of it that can, and only while a
// finger is on it. it has one kind of tap, so all three are the same there
enum Haptics {
    static func light() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #else
        tapTrackpad()
        #endif
    }

    static func medium() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #else
        tapTrackpad()
        #endif
    }

    static func success() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
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
