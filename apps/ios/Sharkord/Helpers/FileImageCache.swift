import SwiftUI
import UIKit

// pictures of the server's files kept by server and file id, not by link: a signed link changes
// every time the server sends the file again, and asyncimage keeps nothing, so an avatar would go
// blank and download again whenever a screen is rebuilt. a file never changes under its id, a new
// picture is a new file, so a copy on disk stays good and the next launch draws it straight away
enum FileImageCache {
    private static let cache = NSCache<NSString, UIImage>()

    private static let directory: URL? = {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }

        let directory = caches.appending(path: "file-images", directoryHint: .isDirectory)

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        return directory
    }()

    static func cached(_ file: SharkordFile, at url: URL) -> UIImage? {
        cache.object(forKey: file.cacheKey(at: url))
    }

    static func load(_ file: SharkordFile, from url: URL) async -> UIImage? {
        let key = file.cacheKey(at: url)

        if let image = cache.object(forKey: key) {
            return image
        }

        let diskURL = directory?.appending(path: key as String)

        if let image = await decode(at: diskURL) {
            cache.setObject(image, forKey: key)

            return image
        }

        guard
            let (data, response) = try? await URLSession.shared.data(from: url),
            (response as? HTTPURLResponse)?.statusCode == 200,
            let image = await decode(data)
        else {
            return nil
        }

        cache.setObject(image, forKey: key)

        if let diskURL {
            try? data.write(to: diskURL, options: .atomic)
        }

        return image
    }

    // decoding a banner is too slow for the main thread
    private nonisolated static func decode(at url: URL?) async -> UIImage? {
        guard let url, let data = try? Data(contentsOf: url) else {
            return nil
        }

        return await decode(data)
    }

    private nonisolated static func decode(_ data: Data) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            UIImage(data: data)?.preparingForDisplay()
        }.value
    }
}

extension SharkordFile {
    // ids are only unique on one server and the app can be signed in to several
    func cacheKey(at url: URL) -> NSString {
        "\(url.host() ?? "")-\(id)" as NSString
    }
}

// a file's picture drawn straight from FileImageCache when it is there, the placeholder only
// until the first load
struct CachedFileImage<Placeholder: View>: View {
    let file: SharkordFile
    let url: URL
    var contentMode: ContentMode = .fill
    @ViewBuilder let placeholder: Placeholder

    @State private var image: UIImage?

    var body: some View {
        if let image = image ?? FileImageCache.cached(file, at: url) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: contentMode)
        } else {
            placeholder
                .task(id: file.id) {
                    image = await FileImageCache.load(file, from: url)
                }
        }
    }
}
