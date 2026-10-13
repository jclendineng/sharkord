import Observation
import UIKit

// custom emoji render inline inside Text, which needs a ready UIImage rather than an AsyncImage
@Observable
final class EmojiImageCache {
    static let shared = EmojiImageCache()

    private(set) var images: [URL: UIImage] = [:]

    @ObservationIgnored private var requested: Set<URL> = []

    func image(for url: URL, pointSize: CGFloat) -> UIImage? {
        if let image = images[url] {
            return image
        }

        if !requested.contains(url) {
            requested.insert(url)

            // deferred so the state change never happens during the view update that asked
            Task {
                await load(url, pointSize: pointSize)
            }
        }

        return nil
    }

    private func load(_ url: URL, pointSize: CGFloat) async {
        guard
            let (data, _) = try? await URLSession.shared.data(from: url),
            let image = UIImage(data: data)
        else {
            return
        }

        let scale = pointSize / max(image.size.width, image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        images[url] = UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
