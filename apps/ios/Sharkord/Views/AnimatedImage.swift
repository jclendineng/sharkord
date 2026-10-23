import CryptoKit
import ImageIO
import SwiftUI
import UIKit

// a gif, apng or animated webp that plays, which AsyncImage does not do. frames are decoded off
// the main thread at the size they are shown and kept, so a grid of them scrolls smoothly
struct AnimatedImage: View {
    let url: URL?
    // the longest side it is drawn at, in points, so frames are not decoded larger than that
    var maxPointSize: CGFloat = 320
    var contentMode: UIView.ContentMode = .scaleAspectFill
    // takes the image's own shape once loaded, for a gif shown in a message
    var sizesToImage = false

    @State private var image: UIImage?

    // what is on screen: the loaded image, one already decoded for this url, or the first frame
    // kept on disk, so a row drawn again, or after a launch, keeps its size instead of starting
    // empty and growing
    private var shown: UIImage? {
        image ?? url.flatMap { url in
            AnimatedImageLoader.shared.cached(for: url, maxPixelSize: maxPointSize * 3)
                ?? AnimatedImageLoader.shared.still(for: url, maxPixelSize: maxPointSize * 3)
        }
    }

    private var aspectRatio: CGFloat? {
        guard sizesToImage, let size = shown?.size, size.height > 0 else {
            return nil
        }

        return size.width / size.height
    }

    var body: some View {
        AnimatedImageView(image: shown, contentMode: contentMode)
            .aspectRatio(aspectRatio, contentMode: .fit)
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

private struct AnimatedImageView: UIViewRepresentable {
    let image: UIImage?
    let contentMode: UIView.ContentMode

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
        view.contentMode = contentMode

        if view.image !== image {
            view.image = image
        }
    }
}

// downloads through the shared url cache, decodes once per url and size
actor AnimatedImageLoader {
    static let shared = AnimatedImageLoader()

    // nscache is safe from any thread, so a view can read it while it is drawn
    nonisolated(unsafe) private let cache = NSCache<NSString, UIImage>()
    // first frames read back from disk, which a row asks for each time it is drawn
    nonisolated(unsafe) private let stills = NSCache<NSString, UIImage>()
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

    nonisolated func cached(for url: URL, maxPixelSize: CGFloat) -> UIImage? {
        cache.object(forKey: Self.key(url, maxPixelSize))
    }

    // the first frame kept from an earlier decode, a small file read there and then so a launch
    // draws it in the first frame, as FileImageCache does for files
    nonisolated func still(for url: URL, maxPixelSize: CGFloat) -> UIImage? {
        let key = Self.key(url, maxPixelSize)

        if let still = stills.object(forKey: key) {
            return still
        }

        guard
            let stillURL = Self.stillURL(for: key),
            let data = try? Data(contentsOf: stillURL),
            let still = UIImage(data: data)
        else {
            return nil
        }

        stills.setObject(still, forKey: key)

        return still
    }

    func firstFrame(for url: URL, maxPixelSize: CGFloat) async -> UIImage? {
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

        let still = UIImage(cgImage: frame)
        let key = Self.key(url, maxPixelSize)

        stills.setObject(still, forKey: key)

        if let stillURL = Self.stillURL(for: key), let png = still.pngData() {
            try? png.write(to: stillURL, options: .atomic)
        }

        return still
    }

    func image(for url: URL, maxPixelSize: CGFloat) async -> UIImage? {
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

    private static func cost(of image: UIImage) -> Int {
        if let frames = image.images {
            return frames.reduce(0) { $0 + bytes(of: $1) }
        }

        return bytes(of: image)
    }

    private static func bytes(of image: UIImage) -> Int {
        guard let frame = image.cgImage else {
            return 0
        }

        return frame.bytesPerRow * frame.height
    }

    // every frame of an animated image at the given size, with its own frame durations
    private static func decode(_ data: Data, maxPixelSize: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        let count = CGImageSourceGetCount(source)
        let options = thumbnailOptions(maxPixelSize)

        guard count > 1 else {
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map { UIImage(cgImage: $0) }
        }

        var frames: [UIImage] = []
        var duration: Double = 0

        frames.reserveCapacity(count)

        for index in 0..<count {
            // drains image io's temporary objects each frame instead of at the end of the decode
            autoreleasepool {
                guard let frame = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else {
                    return
                }

                frames.append(UIImage(cgImage: frame))
                duration += frameDuration(source, at: index)
            }
        }

        return UIImage.animatedImage(with: frames, duration: max(duration, 0.1))
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
