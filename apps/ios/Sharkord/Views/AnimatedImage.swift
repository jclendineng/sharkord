import CryptoKit
import ImageIO
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// a gif, apng or animated webp that plays, which AsyncImage does not do. frames are decoded off
// the main thread at the size they are shown and kept, so a grid of them scrolls smoothly
struct AnimatedImage: View {
    let url: URL?
    // the longest side it is drawn at, in points, so frames are not decoded larger than that
    var maxPointSize: CGFloat = 320
    var contentMode: ContentMode = .fill
    // takes the image's own shape once loaded, for a gif shown in a message
    var sizesToImage = false

    @State private var image: PlatformImage?

    // what is on screen: the loaded image, one already decoded for this url, or the first frame
    // kept on disk, so a row drawn again, or after a launch, keeps its size instead of starting
    // empty and growing
    private var shown: PlatformImage? {
        image ?? url.flatMap { url in
            AnimatedImageLoader.shared.cached(for: url, maxPixelSize: maxPointSize * 3)
                ?? AnimatedImageLoader.shared.still(for: url, maxPixelSize: maxPointSize * 3)
        }
    }

    // a nil ratio is not left alone: it takes the content's own shape, which squeezed a tile
    // meant to fill its cell down to the gif's
    @ViewBuilder
    private var sized: some View {
        let image = AnimatedImageView(image: shown, contentMode: contentMode)
            .appKitAspect(of: shown?.size, contentMode: contentMode)

        if let aspectRatio {
            image.aspectRatio(aspectRatio, contentMode: .fit)
        } else {
            image
        }
    }

    private var aspectRatio: CGFloat? {
        guard sizesToImage, let size = shown?.size, size.height > 0 else {
            return nil
        }

        return size.width / size.height
    }

    var body: some View {
        sized
            .task(id: url) {
                image = nil

                guard let url else {
                    return
                }

                let loader = AnimatedImageLoader.shared
                let maxPixelSize = maxPointSize * 3

                // the first frame while the rest decode, a long gif took a second to show at all
                if loader.cached(for: url, maxPixelSize: maxPixelSize) == nil {
                    image = await loader.firstFrame(for: url, maxPixelSize: maxPixelSize)
                }

                image = await loader.image(for: url, maxPixelSize: maxPixelSize) ?? image
            }
    }
}

#if os(macOS)
// plays a gif by itself, from the image made of the file's own data. it stretches to its frame,
// appKitAspect gives that frame the image's shape
private struct AnimatedImageView: NSViewRepresentable {
    let image: PlatformImage?
    let contentMode: ContentMode

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()

        view.animates = true
        view.imageScaling = .scaleAxesIndependently

        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        if view.image !== image {
            view.image = image
        }
    }

    // whatever room it is offered. asked for its own size, the image view answered with the
    // image's, and a tile stayed small
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSImageView, context: Context) -> CGSize? {
        let size = image?.size ?? .zero

        return CGSize(width: proposal.width ?? size.width, height: proposal.height ?? size.height)
    }
}

private extension View {
    // appkit's image view has no aspect fill and only a fit that ignores swiftui's layout, so the
    // image is given its own shape inside the room offered and clipped to it, as a phone draws it
    @ViewBuilder
    func appKitAspect(of size: CGSize?, contentMode: ContentMode) -> some View {
        if let size, size.width > 0, size.height > 0 {
            Color.clear
                .overlay {
                    aspectRatio(size.width / size.height, contentMode: contentMode)
                }
                .clipped()
        } else {
            self
        }
    }
}
#else
private extension View {
    // a phone's image view fills and fits by itself
    func appKitAspect(of size: CGSize?, contentMode: ContentMode) -> some View {
        self
    }
}

private struct AnimatedImageView: UIViewRepresentable {
    let image: PlatformImage?
    let contentMode: ContentMode

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()

        view.clipsToBounds = true
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)

        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {
        view.contentMode = contentMode == .fit ? .scaleAspectFit : .scaleAspectFill

        if view.image !== image {
            view.image = image
        }
    }
}
#endif

// downloads through the shared url cache, decodes once per url and size
actor AnimatedImageLoader {
    static let shared = AnimatedImageLoader()

    // nscache is safe from any thread, so a view can read it while it is drawn
    nonisolated(unsafe) private let cache = NSCache<NSString, PlatformImage>()
    // first frames read back from disk, which a row asks for each time it is drawn
    nonisolated(unsafe) private let stills = NSCache<NSString, PlatformImage>()
    // what firstFrame downloaded, handed to the full decode right after instead of fetched twice
    private var downloads: [URL: Data] = [:]

    private nonisolated static let directory: URL? = {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }

        let directory = caches.appending(path: "animated-stills", directoryHint: .isDirectory)

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        return directory
    }()

    init() {
        cache.countLimit = 120
        // a count alone let a handful of long gifs keep every decoded frame, hundreds of
        // megabytes with the app in the background. costs are the frames' own bytes
        cache.totalCostLimit = 128 * 1024 * 1024
    }

    private nonisolated static func key(_ url: URL, _ maxPixelSize: CGFloat) -> NSString {
        "\(url.absoluteString)@\(Int(maxPixelSize))" as NSString
    }

    nonisolated func cached(for url: URL, maxPixelSize: CGFloat) -> PlatformImage? {
        cache.object(forKey: Self.key(url, maxPixelSize))
    }

    // the first frame kept from an earlier decode, a small file read there and then so a launch
    // draws it in the first frame, as FileImageCache does for files
    nonisolated func still(for url: URL, maxPixelSize: CGFloat) -> PlatformImage? {
        let key = Self.key(url, maxPixelSize)

        if let still = stills.object(forKey: key) {
            return still
        }

        guard
            let stillURL = Self.stillURL(for: key),
            let data = try? Data(contentsOf: stillURL),
            let still = PlatformImage(data: data)
        else {
            return nil
        }

        stills.setObject(still, forKey: key)

        return still
    }

    func firstFrame(for url: URL, maxPixelSize: CGFloat) async -> PlatformImage? {
        guard let data = await download(url) else {
            return nil
        }

        downloads[url] = data

        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let frame = CGImageSourceCreateThumbnailAtIndex(source, 0, Self.thumbnailOptions(maxPixelSize) as CFDictionary)
        else {
            return nil
        }

        let still = PlatformImage(cgImage: frame)
        let key = Self.key(url, maxPixelSize)

        stills.setObject(still, forKey: key)

        if let stillURL = Self.stillURL(for: key), let png = still.pngData() {
            try? png.write(to: stillURL, options: .atomic)
        }

        return still
    }

    func image(for url: URL, maxPixelSize: CGFloat) async -> PlatformImage? {
        let key = Self.key(url, maxPixelSize)

        if let cached = cache.object(forKey: key) {
            return cached
        }

        var data = downloads.removeValue(forKey: url)

        if data == nil {
            data = await download(url)
        }

        guard let data, let image = Self.decode(data, maxPixelSize: maxPixelSize) else {
            return nil
        }

        cache.setObject(image, forKey: key, cost: Self.cost(of: image))

        return image
    }

    private func download(_ url: URL) async -> Data? {
        try? await URLSession.shared.data(from: url).0
    }

    private nonisolated static func stillURL(for key: NSString) -> URL? {
        let name = SHA256.hash(data: Data((key as String).utf8))
            .map { String(format: "%02x", $0) }
            .joined()

        return directory?.appending(path: "\(name).png")
    }

    private nonisolated static func thumbnailOptions(_ maxPixelSize: CGFloat) -> [CFString: Any] {
        [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
    }

    private static func cost(of image: PlatformImage) -> Int {
        #if os(iOS)
        if let frames = image.images {
            return frames.reduce(0) { $0 + bytes(of: $1) }
        }
        #endif

        return bytes(of: image)
    }

    private static func bytes(of image: PlatformImage) -> Int {
        guard let frame = image.cgImage else {
            return 0
        }

        return frame.bytesPerRow * frame.height
    }

    // every frame of an animated image at the given size, with its own frame durations
    private static func decode(_ data: Data, maxPixelSize: CGFloat) -> PlatformImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        let count = CGImageSourceGetCount(source)
        let options = thumbnailOptions(maxPixelSize)

        guard count > 1 else {
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map { PlatformImage(cgImage: $0) }
        }

        #if os(macOS)
        // appkit plays the file's own frames, it has no image made from a list of them
        return NSImage(data: data)
        #else

        var frames: [PlatformImage] = []
        var duration: Double = 0

        frames.reserveCapacity(count)

        for index in 0..<count {
            // drains image io's temporary objects each frame instead of at the end of the decode
            autoreleasepool {
                guard let frame = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else {
                    return
                }

                frames.append(PlatformImage(cgImage: frame))
                duration += frameDuration(source, at: index)
            }
        }

        return PlatformImage.animatedImage(with: frames, duration: max(duration, 0.1))
        #endif
    }

    // gifs, apngs and webps each keep the delay under their own key
    private static func frameDuration(_ source: CGImageSource, at index: Int) -> Double {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] else {
            return 0.1
        }

        let containers: [(CFString, CFString, CFString)] = [
            (kCGImagePropertyGIFDictionary, kCGImagePropertyGIFUnclampedDelayTime, kCGImagePropertyGIFDelayTime),
            (kCGImagePropertyPNGDictionary, kCGImagePropertyAPNGUnclampedDelayTime, kCGImagePropertyAPNGDelayTime),
            (kCGImagePropertyWebPDictionary, kCGImagePropertyWebPUnclampedDelayTime, kCGImagePropertyWebPDelayTime)
        ]

        for (container, unclamped, clamped) in containers {
            guard let values = properties[container] as? [CFString: Any] else {
                continue
            }

            let delay = (values[unclamped] as? Double) ?? (values[clamped] as? Double) ?? 0.1

            // browsers treat very short delays as a tenth of a second, so the same gif plays alike
            return delay < 0.02 ? 0.1 : delay
        }

        return 0.1
    }
}
