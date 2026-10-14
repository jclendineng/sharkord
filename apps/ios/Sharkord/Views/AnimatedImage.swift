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

    // what is on screen: the loaded image, or one already decoded for this url, so a row that is
    // drawn again keeps its size instead of starting empty and growing
    private var shown: UIImage? {
        image ?? url.flatMap { AnimatedImageLoader.shared.cached(for: $0, maxPixelSize: maxPointSize * 3) }
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

                image = await AnimatedImageLoader.shared.image(for: url, maxPixelSize: maxPointSize * 3)
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

    init() {
        cache.countLimit = 120
    }

    private nonisolated static func key(_ url: URL, _ maxPixelSize: CGFloat) -> NSString {
        "\(url.absoluteString)@\(Int(maxPixelSize))" as NSString
    }

    nonisolated func cached(for url: URL, maxPixelSize: CGFloat) -> UIImage? {
        cache.object(forKey: Self.key(url, maxPixelSize))
    }

    func image(for url: URL, maxPixelSize: CGFloat) async -> UIImage? {
        let key = Self.key(url, maxPixelSize)

        if let cached = cache.object(forKey: key) {
            return cached
        }

        guard
            let (data, _) = try? await URLSession.shared.data(from: url),
            let image = Self.decode(data, maxPixelSize: maxPixelSize)
        else {
            return nil
        }

        cache.setObject(image, forKey: key)

        return image
    }

    // every frame of an animated image at the given size, with its own frame durations
    private static func decode(_ data: Data, maxPixelSize: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        let count = CGImageSourceGetCount(source)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        guard count > 1 else {
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map { UIImage(cgImage: $0) }
        }

        var frames: [UIImage] = []
        var duration: Double = 0

        for index in 0..<count {
            guard let frame = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else {
                continue
            }

            frames.append(UIImage(cgImage: frame))
            duration += frameDuration(source, at: index)
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
