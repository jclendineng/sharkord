import SwiftUI
import UIKit

// pictures of the server's files kept in memory by file id, not by link: a signed link changes
// every time the server sends the file again, and asyncimage keeps nothing, so an avatar would
// go blank and download again whenever a screen is rebuilt
enum FileImageCache {
    private static let cache = NSCache<NSNumber, UIImage>()

    static func cached(_ file: SharkordFile) -> UIImage? {
        cache.object(forKey: NSNumber(value: file.id))
    }

    static func load(_ file: SharkordFile, from url: URL) async -> UIImage? {
        if let image = cached(file) {
            return image
        }

        guard
            let (data, response) = try? await URLSession.shared.data(from: url),
            (response as? HTTPURLResponse)?.statusCode == 200,
            let image = UIImage(data: data)
        else {
            return nil
        }

        cache.setObject(image, forKey: NSNumber(value: file.id))

        return image
    }
}

// a file's picture drawn straight from FileImageCache when it is there, the placeholder only
// until the first download
struct CachedFileImage<Placeholder: View>: View {
    let file: SharkordFile
    let url: URL
    @ViewBuilder let placeholder: Placeholder

    @State private var image: UIImage?

    var body: some View {
        if let image = image ?? FileImageCache.cached(file) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            placeholder
                .task(id: file.id) {
                    image = await FileImageCache.load(file, from: url)
                }
        }
    }
}
