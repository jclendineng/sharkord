import ImageIO
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// pictures of the server's files kept by server and file id, not by link: a signed link changes
// every time the server sends the file again, and asyncimage keeps nothing, so an avatar would go
// blank and download again whenever a screen is rebuilt. a file never changes under its id, a new
// picture is a new file, so a copy on disk stays good and the next launch draws it straight away
enum FileImageCache {
    private static let cache = NSCache<NSString, PlatformImage>()
    // pictures decoded at the size they are drawn, an avatar's few dozen pixels rather than the
    // whole upload. kept apart from the full ones so an attachment never gets a small copy
    private static let scaledCache = NSCache<NSString, PlatformImage>()
    // files with no small copy on disk yet, so a view drawn again does not look every time
    private static var missingThumbnails = Set<NSString>()

    private static let directory: URL? = {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }

        let directory = caches.appending(path: "file-images", directoryHint: .isDirectory)

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        return directory
    }()

    static func cached(_ file: SharkordFile, at url: URL) -> PlatformImage? {
        cache.object(forKey: file.cacheKey(at: url))
    }

    // a picture this device just uploaded, so it shows straight away rather than downloading back
    static func store(_ data: Data, image: PlatformImage, for file: SharkordFile, at url: URL) {
        let key = file.cacheKey(at: url)

        cache.setObject(image, forKey: key)

        if let diskURL = directory?.appending(path: key as String) {
            try? data.write(to: diskURL, options: .atomic)
        }
    }

    // any copy at all, for the first frame of a view that has not measured itself yet. after a
    // launch nothing is in memory, so the small copy kept on disk is read there and then: it is
    // a few kilobytes, quicker to decode than the frame it would otherwise leave blank
    static func cachedScaled(_ file: SharkordFile, at url: URL) -> PlatformImage? {
        let key = file.cacheKey(at: url)

        if let image = cache.object(forKey: key) ?? scaledCache.object(forKey: key) {
            return image
        }

        guard
            !missingThumbnails.contains(key),
            let thumbnailURL = thumbnailURL(for: key),
            let data = try? Data(contentsOf: thumbnailURL),
            let image = PlatformImage(data: data)?.preparingForDisplay()
        else {
            missingThumbnails.insert(key)
            return nil
        }

        scaledCache.setObject(image, forKey: key)

        return image
    }

    static func load(_ file: SharkordFile, from url: URL) async -> PlatformImage? {
        let key = file.cacheKey(at: url)

        if let image = cache.object(forKey: key) {
            return image
        }

        guard let data = await data(for: key, from: url), let image = await decode(data) else {
            return nil
        }

        cache.setObject(image, forKey: key)

        return image
    }

    // at most maxPixelSize on its longer side, from the copy on disk when there is one
    static func load(_ file: SharkordFile, from url: URL, maxPixelSize: CGFloat) async -> PlatformImage? {
        let key = file.cacheKey(at: url)

        if let image = cache.object(forKey: key) {
            return image
        }

        if let image = scaledCache.object(forKey: key), image.pixelSize >= maxPixelSize {
            return image
        }

        guard let data = await data(for: key, from: url), let image = await decode(data, maxPixelSize: maxPixelSize) else {
            return nil
        }

        // the largest copy asked for so far is the one kept, on disk too for the next launch
        if image.pixelSize >= scaledCache.object(forKey: key)?.pixelSize ?? 0 {
            scaledCache.setObject(image, forKey: key)
            missingThumbnails.remove(key)
            saveThumbnail(image, at: thumbnailURL(for: key))
        }

        return image
    }

    private static func thumbnailURL(for key: NSString) -> URL? {
        directory?.appending(path: "\(key).thumb")
    }

    private nonisolated static func saveThumbnail(_ image: PlatformImage, at url: URL?) {
        guard let url else {
            return
        }

        Task.detached(priority: .utility) {
            try? image.pngData()?.write(to: url, options: .atomic)
        }
    }

    // the file from disk, downloaded and kept there the first time
    private static func data(for key: NSString, from url: URL) async -> Data? {
        let diskURL = directory?.appending(path: key as String)

        if let data = await read(diskURL) {
            return data
        }

        guard
            let (data, response) = try? await URLSession.shared.data(from: url),
            (response as? HTTPURLResponse)?.statusCode == 200
        else {
            return nil
        }

        if let diskURL {
            try? data.write(to: diskURL, options: .atomic)
        }

        return data
    }

    private nonisolated static func read(_ url: URL?) async -> Data? {
        guard let url else {
            return nil
        }

        return await Task.detached(priority: .userInitiated) {
            try? Data(contentsOf: url)
        }.value
    }

    // decoding a banner is too slow for the main thread
    private nonisolated static func decode(_ data: Data) async -> PlatformImage? {
        await Task.detached(priority: .userInitiated) {
            PlatformImage(data: data)?.preparingForDisplay()
        }.value
    }

    // image io reads only what the smaller size needs, far quicker than decoding the whole
    // picture and shrinking it after
    private nonisolated static func decode(_ data: Data, maxPixelSize: CGFloat) async -> PlatformImage? {
        await Task.detached(priority: .userInitiated) {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
            ]

            guard
                let source = CGImageSourceCreateWithData(data as CFData, nil),
                let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            else {
                return nil
            }

            return PlatformImage(cgImage: image)
        }.value
    }
}

extension PlatformImage {
    // the longer side in pixels
    fileprivate var pixelSize: CGFloat {
        max(size.width, size.height) * scale
    }
}

extension SharkordFile {
    // ids are only unique on one server and the app can be signed in to several
    func cacheKey(at url: URL) -> NSString {
        "\(url.host() ?? "")-\(id)" as NSString
    }
}

// a file's picture drawn straight from FileImageCache when it is there, the placeholder only
// until the first load. it is decoded at the size it is drawn, measured once it is laid out
struct CachedFileImage<Placeholder: View>: View {
    let file: SharkordFile
    let url: URL
    var contentMode: ContentMode = .fill
    @ViewBuilder let placeholder: Placeholder

    @Environment(\.displayScale) private var displayScale

    @State private var image: PlatformImage?
    @State private var pointSize: CGFloat = 0

    // rounded up to a step, so a view resizing by a point does not decode the picture again
    private var maxPixelSize: CGFloat {
        let pixels = pointSize * displayScale

        return (pixels / 64).rounded(.up) * 64
    }

    var body: some View {
        Group {
            if let image = image ?? FileImageCache.cachedScaled(file, at: url) {
                Image(platformImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder
            }
        }
        .onGeometryChange(for: CGFloat.self, of: { max($0.size.width, $0.size.height) }) { size in
            pointSize = size
        }
        .task(id: [CGFloat(file.id), maxPixelSize]) {
            guard maxPixelSize > 0 else {
                return
            }

            image = await FileImageCache.load(file, from: url, maxPixelSize: maxPixelSize)
        }
    }
}
